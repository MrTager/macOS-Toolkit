#ifndef TOOLKIT_SMC_CORE_H
#define TOOLKIT_SMC_CORE_H
#include <stdbool.h>
#include <stdint.h>
typedef struct { char type[5]; uint8_t size; uint8_t bytes[32]; } ToolkitSMCValue;
bool toolkit_smc_read(const char *key, ToolkitSMCValue *value);
bool toolkit_smc_write(const char *key, const uint8_t *bytes, uint8_t size);
#endif
