#ifndef GMV_SCANNER_UTILS_H
#define GMV_SCANNER_UTILS_H

#include <ctype.h>
#include <stddef.h>
#include <string.h>

/* These bits are the public settings.types values used by www/main.js. */
enum {
    GMVCode128 = 1, GMVCode39 = 2, GMVCode93 = 4, GMVCodabar = 8,
    GMVDataMatrix = 16, GMVEAN13 = 32, GMVEAN8 = 64, GMVITF = 128,
    GMVQR = 256, GMVUPCA = 512, GMVUPCE = 1024, GMVPDF417 = 2048,
    GMVAztec = 4096, GMVAllFormats = 8191
};

static inline unsigned long GMVEffectiveFormats(unsigned long formats) {
    if (formats == 0) return GMVCode39 | GMVDataMatrix; /* scanVIN */
    if (formats == 1234) return GMVAllFormats; /* legacy default sentinel */
    return formats;
}

static inline int GMVVINValue(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    switch (c) {
        case 'A': case 'J': return 1;
        case 'B': case 'K': case 'S': return 2;
        case 'C': case 'L': case 'T': return 3;
        case 'D': case 'M': case 'U': return 4;
        case 'E': case 'N': case 'V': return 5;
        case 'F': case 'W': return 6;
        case 'G': case 'P': case 'X': return 7;
        case 'H': case 'Y': return 8;
        case 'R': case 'Z': return 9;
        default: return -1;
    }
}

/* Normalize the legacy VIN scan (strip delimiters/I/O/Q, take 17 characters)
   and validate the ISO 3779 check digit. Output is always NUL-terminated. */
static inline int GMVNormalizeVIN(const char *input, char output[18]) {
    static const int weights[17] = {8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2};
    size_t length = 0;
    output[0] = '\0';
    if (!input) return 0;
    for (const unsigned char *p = (const unsigned char *)input; *p && length < 17; ++p) {
        unsigned char c = (unsigned char)toupper(*p);
        if (GMVVINValue(c) >= 0) output[length++] = (char)c;
    }
    output[length] = '\0';
    if (length != 17) return 0;
    int sum = 0;
    for (size_t i = 0; i < 17; ++i) sum += GMVVINValue((unsigned char)output[i]) * weights[i];
    int remainder = sum % 11;
    char expected = remainder == 10 ? 'X' : (char)('0' + remainder);
    return output[8] == expected;
}

#endif
