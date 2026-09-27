/*
 * SMC 特权助手（当前在 macOS 26.x Intel 上不可用，保留备用）
 *
 * 探测结论（2026-09，MacBookPro16,2 / macOS 26.6.2）：
 * - AppleSMCClient selector 2 的 struct 方法已从 user client 移除，
 *   所有输入尺寸（4-200）均返回 MIG_TYPE_MISMATCH (-536870206)，root 亦然
 * - 已对照 exelban/stats 仓库 smc.swift 的精确 SMCKeyData_t 布局复刻，同样失败
 * - stats 在新系统上正常工作的传感器读数走 IOHID/IOReport（Apple Silicon 专用）
 * - 本 helper 及主 App 侧 SMCHelperBridge/安装链路已就绪，
 *   若未来系统恢复通道或找到新入口，替换 smc_call() 即可启用
 */

#include <stdio.h>
#include <string.h>
#include <xpc/xpc.h>
#include <IOKit/IOKitLib.h>
#include <syslog.h>

#define SMCCmdRead 9
#define SMCCmdWrite 6
#define HelperVersion 1

typedef struct {
    uint32_t key;
    uint8_t vers;
    uint8_t data8;
    uint8_t dataSize;
    uint32_t dataType;
    uint8_t bytes[32];
} __attribute__((packed)) SMCParam;

static io_connect_t g_conn = 0;

static bool smc_open(void) {
    if (g_conn != 0) return true;
    io_iterator_t iter;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter) != KERN_SUCCESS) return false;
    io_object_t device = IOIteratorNext(iter);
    IOObjectRelease(iter);
    if (!device) return false;
    kern_return_t r = IOServiceOpen(device, mach_task_self_, 0, &g_conn);
    IOObjectRelease(device);
    syslog(LOG_NOTICE, "helper: IOServiceOpen -> %d", r);
    return r == KERN_SUCCESS;
}

static bool smc_call(SMCParam *input, SMCParam *output) {
    if (!smc_open()) return false;
    size_t outCount = sizeof(SMCParam);
    kern_return_t r = IOConnectCallStructMethod(g_conn, 2, input, sizeof(SMCParam), output, &outCount);
    return r == KERN_SUCCESS;
}

static xpc_object_t handle_read(xpc_object_t request) {
    const char *key = xpc_dictionary_get_string(request, "key");
    if (!key || strlen(key) != 4) {
        xpc_object_t err = xpc_dictionary_create_reply(request);
        xpc_dictionary_set_int64(err, "ok", 0);
        return err;
    }

    SMCParam input = {0};
    SMCParam output = {0};
    input.key = (uint32_t)key[0] << 24 | (uint32_t)key[1] << 16 | (uint32_t)key[2] << 8 | (uint32_t)key[3];
    input.data8 = SMCCmdRead;

    if (!smc_call(&input, &output)) {
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        xpc_dictionary_set_int64(reply, "ok", 0);
        return reply;
    }

    uint8_t size = output.dataSize;
    uint32_t type = output.dataType;

    SMCParam in2 = {0};
    SMCParam out2 = {0};
    in2.key = input.key;
    in2.data8 = 5;
    in2.dataSize = size;
    in2.dataType = type;
    if (!smc_call(&in2, &out2)) {
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        xpc_dictionary_set_int64(reply, "ok", 0);
        return reply;
    }

    xpc_object_t reply = xpc_dictionary_create_reply(request);
    xpc_dictionary_set_int64(reply, "ok", 1);
    xpc_dictionary_set_string(reply, "type", (const char *)&type);
    xpc_dictionary_set_int64(reply, "size", size);
    xpc_dictionary_set_data(reply, "data", out2.bytes, 32);
    return reply;
}

static xpc_object_t handle_write(xpc_object_t request) {
    const char *key = xpc_dictionary_get_string(request, "key");
    size_t dataLen = 0;
    const uint8_t *data = xpc_dictionary_get_data(request, "data", &dataLen);
    if (!key || strlen(key) != 4 || !data || dataLen == 0 || dataLen > 32) {
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        xpc_dictionary_set_int64(reply, "ok", 0);
        return reply;
    }

    SMCParam input = {0};
    SMCParam output = {0};
    input.key = (uint32_t)key[0] << 24 | (uint32_t)key[1] << 16 | (uint32_t)key[2] << 8 | (uint32_t)key[3];
    input.data8 = SMCCmdWrite;
    input.dataSize = (uint8_t)dataLen;
    memcpy(input.bytes, data, dataLen);

    xpc_object_t reply = xpc_dictionary_create_reply(request);
    xpc_dictionary_set_int64(reply, "ok", smc_call(&input, &output) ? 1 : 0);
    return reply;
}

static void peer_event_handler(xpc_connection_t peer) {
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        if (type == XPC_TYPE_ERROR) return;
        if (type != XPC_TYPE_DICTIONARY) return;

        const char *version = xpc_dictionary_get_string(event, "version");
        if (!version || strcmp(version, "1") != 0) return;

        const char *action = xpc_dictionary_get_string(event, "action");
        xpc_object_t reply = NULL;
        if (strcmp(action, "read") == 0) {
            reply = handle_read(event);
        } else if (strcmp(action, "write") == 0) {
            reply = handle_write(event);
        } else if (strcmp(action, "ping") == 0) {
            reply = xpc_dictionary_create_reply(event);
            xpc_dictionary_set_int64(reply, "ok", 1);
            xpc_dictionary_set_int64(reply, "version", HelperVersion);
        }
        if (reply) {
            xpc_connection_send_message(peer, reply);
            xpc_release(reply);
        }
    });
    xpc_connection_resume(peer);
}

int main(int argc, const char *argv[]) {
    openlog("local.toolkit.smchelper", LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_NOTICE, "helper started (uid=%d)", getuid());

    if (!smc_open()) {
        syslog(LOG_ERR, "cannot open AppleSMC");
    }

    xpc_connection_t service = xpc_connection_create_mach_service(
        "local.toolkit.smchelper", dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!service) {
        syslog(LOG_ERR, "xpc listener create failed");
        return 1;
    }
    xpc_connection_set_event_handler(service, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        if (type == XPC_TYPE_ERROR) {
            syslog(LOG_ERR, "xpc listener error");
            exit(1);
        }
        if (xpc_get_type(event) == XPC_TYPE_CONNECTION) {
            peer_event_handler(event);
        }
    });
    xpc_connection_resume(service);
    dispatch_main();
    return 0;
}
