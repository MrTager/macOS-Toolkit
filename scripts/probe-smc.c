#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

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

int main(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 1;
    io_connect_t conn = 0;
    kern_return_t openResult = IOServiceOpen(service, mach_task_self_, 0, &conn);
    IOObjectRelease(service);
    printf("size=%zu open=0x%x\n", sizeof(SMCParam), openResult);
    if (openResult != KERN_SUCCESS) return 1;
    const char *keys[] = {"FNum", "F0Ac", "F0Mn", "F0Mx", "F0Md", "F0Tg", "F0ID", "F1Ac", "F1Mn", "F1Mx", "F1Md", "F1Tg", "F1ID", "FS! ", "TC0P"};
    for (size_t i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
        SMCParam in = {0}, out = {0};
        size_t size = sizeof(out);
        uint32_t key = ((uint32_t)keys[i][0] << 24) | ((uint32_t)keys[i][1] << 16) | ((uint32_t)keys[i][2] << 8) | (uint32_t)keys[i][3];
        in.key = key;
        in.command = 9;
        kern_return_t result = IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &size);
        printf("%s info=0x%x size=%u type=%08x\n", keys[i], result, out.keyInfo.size, out.keyInfo.type);
        if (result != KERN_SUCCESS || !out.keyInfo.size || out.keyInfo.size > 32) continue;
        uint32_t keySize = out.keyInfo.size;
        in = (SMCParam){0}; out = (SMCParam){0}; size = sizeof(out);
        in.key = key;
        in.command = 5;
        in.keyInfo.size = keySize;
        result = IOConnectCallStructMethod(conn, 2, &in, sizeof(in), &out, &size);
        printf("  data=0x%x %02x %02x %02x %02x\n", result, out.bytes[0], out.bytes[1], out.bytes[2], out.bytes[3]);
    }
    IOServiceClose(conn);
}
