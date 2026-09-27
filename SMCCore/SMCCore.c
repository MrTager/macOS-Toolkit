#include "SMCCore.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

typedef struct { uint8_t major, minor, build; uint16_t reserved; uint8_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPower;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPower power;
    SMCKeyInfo keyInfo;
    uint8_t result, status, command;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;
_Static_assert(sizeof(SMCParam) == 80, "Unexpected AppleSMC request layout");

static io_connect_t connection;
static bool connect_smc(void) {
    if (connection) return true;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return false;
    kern_return_t result = IOServiceOpen(service, mach_task_self_, 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS;
}

static uint32_t key_code(const char *key) {
    return (uint32_t)(uint8_t)key[0] << 24 | (uint32_t)(uint8_t)key[1] << 16 |
           (uint32_t)(uint8_t)key[2] << 8 | (uint8_t)key[3];
}

static bool call_smc(SMCParam *input, SMCParam *output) {
    if (!connect_smc()) return false;
    size_t outputSize = sizeof(*output);
    return IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &outputSize) == KERN_SUCCESS && output->result == 0;
}

bool toolkit_smc_read(const char *key, ToolkitSMCValue *value) {
    if (!key || strlen(key) != 4 || !value) return false;
    SMCParam input = {0}, output = {0};
    input.key = key_code(key);
    input.command = 9;
    if (!call_smc(&input, &output) || output.keyInfo.size == 0 || output.keyInfo.size > 32) return false;
    uint32_t size = output.keyInfo.size, type = output.keyInfo.type;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key_code(key);
    input.command = 5;
    input.keyInfo.size = size;
    if (!call_smc(&input, &output)) return false;
    for (int i = 0; i < 4; i++) value->type[i] = (char)(type >> (24 - i * 8));
    value->type[4] = 0;
    value->size = (uint8_t)size;
    memcpy(value->bytes, output.bytes, size);
    return true;
}

bool toolkit_smc_write(const char *key, const uint8_t *bytes, uint8_t size) {
    if (!key || strlen(key) != 4 || !bytes || size == 0 || size > 32) return false;
    ToolkitSMCValue current = {0};
    if (!toolkit_smc_read(key, &current) || current.size != size) return false;
    SMCParam input = {0}, output = {0};
    input.key = key_code(key);
    input.command = 6;
    input.keyInfo.size = size;
    memcpy(input.bytes, bytes, size);
    return call_smc(&input, &output);
}
