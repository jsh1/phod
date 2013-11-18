#ifndef MD5_H
#define MD5_H

#include <stdint.h>

typedef struct {
    uint32_t buf[4];
    uint32_t bits[2];
    uint8_t in[64];
} MD5Context;

void MD5Init(MD5Context *context);
void MD5Update(MD5Context *context, uint8_t const *buf, uint32_t len);
void MD5Final(uint8_t digest[16], MD5Context *context);
void MD5Transform(uint32_t buf[4], const uint8_t in[64]);

#endif /* !MD5_H */
