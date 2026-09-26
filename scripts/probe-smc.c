#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    UInt8 data[32];
    UInt32 dataType;
    UInt8 dataSize;
} SMCKeyData_t;

typedef struct {
    UInt32 key;
    UInt8 vers;
    UInt8 data8;
    SMCKeyData_t keyInfo;
    UInt8 result;
    UInt8 status;
    UInt8 data8_2;
    UInt32 data32;
    UInt8 bytes[32];
} SMCParamStruct;

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_DATA 5

io_connect_t conn;

UInt32 keyFromStr(const char *s) {
    UInt32 v = 0;
    for (int i = 0; i < 4; i++) v = (v << 8) | (UInt8)s[i];
    return v;
}

int readSMC(const char *keyStr, char *typeName, UInt8 *outBytes, int *outSize) {
    SMCParamStruct input;
    SMCParamStruct output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    size_t outCount = sizeof(SMCParamStruct);

    input.key = keyFromStr(keyStr);
    input.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC,
        &input, sizeof(SMCParamStruct), &output, &outCount);
    if (kr != KERN_SUCCESS) return 0;

    SMCKeyData_t info = output.keyInfo;
    UInt32 type = info.dataType;
    typeName[0] = (type >> 24) & 0xFF;
    typeName[1] = (type >> 16) & 0xFF;
    typeName[2] = (type >> 8) & 0xFF;
    typeName[3] = type & 0xFF;
    typeName[4] = 0;
    int size = info.dataSize;

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    outCount = sizeof(SMCParamStruct);
    input.key = keyFromStr(keyStr);
    input.data8 = SMC_CMD_READ_DATA;
    input.keyInfo.dataSize = (UInt8)size;
    kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC,
        &input, sizeof(SMCParamStruct), &output, &outCount);
    if (kr != KERN_SUCCESS) return 0;
    memcpy(outBytes, output.bytes, 32);
    *outSize = size;
    return 1;
}

double decode(const char *typeName, const UInt8 *b) {
    if (strcmp(typeName, "sp78") == 0) {
        int16_t raw = (int16_t)((b[0] << 8) | b[1]);
        return raw / 256.0;
    }
    if (strcmp(typeName, "fpe2") == 0) {
        return ((b[0] << 8) | b[1]) / 4.0;
    }
    if (strcmp(typeName, "ui8 ") == 0 || strcmp(typeName, "ui8") == 0) return b[0];
    if (strcmp(typeName, "ui16") == 0) return (b[0] << 8) | b[1];
    if (strcmp(typeName, "flag") == 0) return b[0];
    if (strcmp(typeName, "flt ") == 0) {
        float f;
        memcpy(&f, b, 4);
        return f;
    }
    return 0;
}

int main() {
    printf("sizeof(SMCParamStruct) = %zu\n", sizeof(SMCParamStruct));

    io_iterator_t iter;
    io_object_t device;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iter) != KERN_SUCCESS) {
        printf("找不到 AppleSMC\n");
        return 1;
    }
    device = IOIteratorNext(iter);
    IOObjectRelease(iter);
    if (!device) { printf("无设备\n"); return 1; }
    if (IOServiceOpen(device, mach_task_self_, 0, &conn) != KERN_SUCCESS) {
        printf("打开失败\n");
        return 1;
    }
    IOObjectRelease(device);

    const char *temps[][2] = {
        {"TC0P","CPU 近端"},{"TC0C","CPU 核心"},{"TC0D","CPU 二极管"},{"TC0E","CPU 封装"},
        {"TC0H","CPU 散热器"},{"TC0J","CPU 结点"},{"TCAD","CPU 相邻"},
        {"TC1C","核心2"},{"TC2C","核心3"},{"TC3C","核心4"},{"TC4C","核心5"},
        {"TC5C","核心6"},{"TC6C","核心7"},{"TC7C","核心8"},{"TC8C","核心9"},
        {"TG0P","GPU 近端"},{"TG0D","GPU 二极管"},{"TG0H","GPU 散热器"},
        {"Tp01","CPU PECI"},{"Th1H","热管1"},{"Th2H","热管2"},
        {"TM0P","内存近端"},{"TM0S","内存槽1"},{"TM8P","内存槽2"},{"TM9P","内存槽3"},
        {"TA0P","环境"},{"TB1T","电池1"},{"TB2T","电池2"},{"TB0T","电池"},
        {"TW0P","无线网卡"},{"TMCD","主板"},{"Ts0S","内存prox"},{"TL0P","雷电"}
    };

    printf("=== 温度 ===\n");
    char typeName[8];
    UInt8 bytes[32];
    int size = 0;
    for (size_t i = 0; i < sizeof(temps)/sizeof(temps[0]); i++) {
        if (readSMC(temps[i][0], typeName, bytes, &size)) {
            double v = decode(typeName, bytes);
            if (v > 0 && v < 120) printf("%s  %-10s %s  %6.1f ℃\n", temps[i][0], temps[i][1], typeName, v);
        }
    }

    printf("=== 功耗 ===\n");
    const char *pwrs[] = {"PCPG","PCPL","PCPT","PCPF","PSTR","PGTR"};
    for (int i = 0; i < 6; i++) {
        if (readSMC(pwrs[i], typeName, bytes, &size)) {
            double v = decode(typeName, bytes);
            if (v > 0) printf("%s  %s  %6.2f\n", pwrs[i], typeName, v);
        }
    }

    printf("=== 风扇 ===\n");
    const char *fans[] = {"F0Ac","F0Mn","F0Mx","F0Lf","F0Af","F0St","F0ID","F1Ac","F1Mn","F1Mx","F1Lf","F2Ac"};
    for (int i = 0; i < 12; i++) {
        if (readSMC(fans[i], typeName, bytes, &size)) {
            double v = decode(typeName, bytes);
            printf("%s  %s  [", fans[i], typeName);
            for (int j = 0; j < 6 && j < size; j++) printf("%02x ", bytes[j]);
            printf("]  %8.1f\n", v);
        } else {
            printf("%s  读取失败\n", fans[i]);
        }
    }

    IOServiceClose(conn);
    return 0;
}
