#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <xpc/xpc.h>
#include "SMCCore.h"

static unsigned int controlled_fans;
static time_t last_heartbeat;

static void restore_controlled_fans(void) {
    const uint8_t automatic = 0;
    for (int i = 0; i < 10; i++) {
        if (!(controlled_fans & (1u << i))) continue;
        char key[5] = {'F', (char)('0' + i), 'M', 'd', 0};
        toolkit_smc_write(key, &automatic, 1);
    }
    controlled_fans = 0;
}

static bool allowed_fan_key(const char *key, size_t size) {
    if (!key || strlen(key) != 4 || key[0] != 'F' || key[1] < '0' || key[1] > '9') return false;
    if (key[2] == 'M' && key[3] == 'd') return size == 1;
    if (key[2] == 'T' && key[3] == 'g') return size == 4;
    return false;
}

static xpc_object_t handle_write(xpc_object_t request) {
    xpc_object_t reply = xpc_dictionary_create_reply(request);
    const char *key = xpc_dictionary_get_string(request, "key");
    size_t size = 0;
    const uint8_t *bytes = xpc_dictionary_get_data(request, "data", &size);
    bool ok = bytes && allowed_fan_key(key, size);
    if (ok && key[2] == 'M') ok = bytes[0] <= 1;
    if (ok && key[2] == 'T') {
        ToolkitSMCValue lower = {0}, upper = {0};
        char bound[5] = {'F', key[1], 'M', 'n', 0};
        ok = toolkit_smc_read(bound, &lower);
        bound[3] = 'x';
        ok = ok && toolkit_smc_read(bound, &upper);
        if (ok && strcmp(lower.type, "flt ") == 0 && strcmp(upper.type, "flt ") == 0) {
            float target, minimum, maximum;
            memcpy(&target, bytes, 4);
            memcpy(&minimum, lower.bytes, 4);
            memcpy(&maximum, upper.bytes, 4);
            ok = target >= minimum && target <= maximum;
        } else ok = false;
    }
    if (ok) ok = toolkit_smc_write(key, bytes, (uint8_t)size);
    if (ok) {
        last_heartbeat = time(NULL);
        if (key[2] == 'M') {
            if (bytes[0]) controlled_fans |= 1u << (key[1] - '0');
            else controlled_fans &= ~(1u << (key[1] - '0'));
        }
    }
    xpc_dictionary_set_int64(reply, "ok", ok ? 1 : 0);
    return reply;
}

static void peer_event_handler(xpc_connection_t peer) {
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        if (xpc_get_type(event) != XPC_TYPE_DICTIONARY) return;
        const char *version = xpc_dictionary_get_string(event, "version");
        const char *action = xpc_dictionary_get_string(event, "action");
        if (!version || strcmp(version, "1") || !action) return;
        xpc_object_t reply = NULL;
        if (!strcmp(action, "write")) reply = handle_write(event);
        if (!strcmp(action, "ping")) {
            last_heartbeat = time(NULL);
            reply = xpc_dictionary_create_reply(event);
            xpc_dictionary_set_int64(reply, "ok", 1);
        }
        if (reply) { xpc_connection_send_message(peer, reply); xpc_release(reply); }
    });
    xpc_connection_resume(peer);
}

int main(void) {
    openlog("local.toolkit.smchelper", LOG_PID, LOG_DAEMON);
    xpc_connection_t listener = xpc_connection_create_mach_service("local.toolkit.smchelper", dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!listener) return 1;
    xpc_connection_set_event_handler(listener, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_CONNECTION) peer_event_handler(event);
    });
    xpc_connection_resume(listener);
    dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(watchdog, ^{
        if (controlled_fans && time(NULL) - last_heartbeat > 15) restore_controlled_fans();
    });
    dispatch_resume(watchdog);
    dispatch_main();
}
