#include "emerald_runtime_internal.h"
#include <string.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <math.h>

static void emerald_number_fail(const char *message) {
    emerald_runtime_flush_stdout();
    fprintf(stderr, "Emerald numeric error: %s\n", message);
    emerald_flow_shutdown();
    exit(1);
}

int64_t emerald_int64_add(int64_t a, int64_t b) {
    int64_t value;
    if (__builtin_add_overflow(a, b, &value)) emerald_number_fail("Int overflow in addition");
    return value;
}

int64_t emerald_int64_sub(int64_t a, int64_t b) {
    int64_t value;
    if (__builtin_sub_overflow(a, b, &value)) emerald_number_fail("Int overflow in subtraction");
    return value;
}

int64_t emerald_int64_mul(int64_t a, int64_t b) {
    int64_t value;
    if (__builtin_mul_overflow(a, b, &value)) emerald_number_fail("Int overflow in multiplication");
    return value;
}

int64_t emerald_int64_div(int64_t a, int64_t b) {
    if (b == 0) emerald_number_fail("division by zero");
    if (a == INT64_MIN && b == -1) emerald_number_fail("Int overflow in division");
    return a / b;
}

int64_t emerald_int64_rem(int64_t a, int64_t b) {
    if (b == 0) emerald_number_fail("remainder by zero");
    if (a == INT64_MIN && b == -1) return 0;
    return a % b;
}

int64_t emerald_int64_neg(int64_t a) {
    if (a == INT64_MIN) emerald_number_fail("Int overflow in negation");
    return -a;
}

int32_t emerald_int64_to_int32_checked(int64_t value) {
    if (value < INT32_MIN || value > INT32_MAX) emerald_number_fail("Int is outside the native 32-bit API range");
    return (int32_t) value;
}

static const char emerald_decimal_pairs[201] =
    "00010203040506070809101112131415161718192021222324252627282930313233343536373839"
    "40414243444546474849505152535455565758596061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";

EmeraldString *emerald_int64_to_string(int64_t value) {
    /* Write digits backwards, two at a time, into a stack buffer; the result
       is then copied once into an exact-size String. */
    char buffer[24];
    char *end = buffer + sizeof(buffer);
    char *start = end;
    uint64_t magnitude = value < 0 ? 0 - (uint64_t) value : (uint64_t) value;

    while (magnitude >= 100) {
        unsigned pair = (unsigned) (magnitude % 100) * 2;
        magnitude /= 100;
        *--start = emerald_decimal_pairs[pair + 1];
        *--start = emerald_decimal_pairs[pair];
    }

    if (magnitude >= 10) {
        unsigned pair = (unsigned) magnitude * 2;
        *--start = emerald_decimal_pairs[pair + 1];
        *--start = emerald_decimal_pairs[pair];
    } else {
        *--start = (char) ('0' + magnitude);
    }

    if (value < 0) {
        *--start = '-';
    }

    return emerald_string_new((const uint8_t *) start, (uint64_t) (end - start));
}

/* Accepts an optional '-' followed by ASCII digits and nothing else: no
   leading or trailing whitespace and no '+', matching the trailing-garbage
   rejection. Uses the String length rather than the NUL terminator. */
int64_t emerald_string_to_int64(EmeraldString *value) {
    if (value == NULL || value->length == 0) emerald_number_fail("invalid Int text");
    const uint8_t *cursor = value->bytes;
    const uint8_t *end = cursor + value->length;
    int negative = *cursor == '-';
    if (negative) cursor++;
    if (cursor == end) emerald_number_fail("invalid Int text");
    uint64_t limit = negative ? (uint64_t) INT64_MAX + 1 : (uint64_t) INT64_MAX;
    uint64_t result = 0;

    for (; cursor < end; cursor++) {
        unsigned digit = (unsigned) *cursor - '0';
        if (digit > 9) emerald_number_fail("invalid Int text");
        if (result > (limit - digit) / 10) emerald_number_fail("Int overflow in conversion");
        result = result * 10 + digit;
    }

    if (negative) {
        return result == 0 ? 0 : -(int64_t) (result - 1) - 1;
    }

    return (int64_t) result;
}

/* Writes count significant digits (trailing zeros dropped) with decimal
   exponent the way %.17g lays them out: exponent notation only below 1e-4 or
   from 1e17 on. Returns the text length. */
static int emerald_float_render(char *text, int negative, const char *digits, int count, int exponent) {
    char *out = text;

    while (count > 1 && digits[count - 1] == '0') {
        count--;
    }

    if (negative) {
        *out++ = '-';
    }

    if (exponent < -4 || exponent >= 17) {
        *out++ = digits[0];

        if (count > 1) {
            *out++ = '.';
            memcpy(out, digits + 1, (size_t) (count - 1));
            out += count - 1;
        }

        *out++ = 'e';
        *out++ = exponent < 0 ? '-' : '+';
        int magnitude = exponent < 0 ? -exponent : exponent;

        if (magnitude >= 100) {
            *out++ = (char) ('0' + magnitude / 100);
        }

        *out++ = (char) ('0' + magnitude / 10 % 10);
        *out++ = (char) ('0' + magnitude % 10);
    } else if (exponent < 0) {
        *out++ = '0';
        *out++ = '.';

        for (int zero = -1; zero > exponent; zero--) {
            *out++ = '0';
        }

        memcpy(out, digits, (size_t) count);
        out += count;
    } else {
        for (int index = 0; index <= exponent; index++) {
            *out++ = index < count ? digits[index] : '0';
        }

        if (count > exponent + 1) {
            *out++ = '.';
            memcpy(out, digits + exponent + 1, (size_t) (count - exponent - 1));
            out += count - exponent - 1;
        }
    }

    *out = 0;
    return (int) (out - text);
}

/* Shortest of 15, 16 or 17 significant digits that reads back as the same
   double. The result equals trying snprintf %.15g, %.16g and %.17g in turn
   with a strtod check (checked against that on millions of random values),
   but needs one %.16e call for the 17 digits; shorter candidates are rounded
   from them and only checked with strtod. */
static int emerald_float_shortest(char *text, double value) {
    char scientific[40];
    snprintf(scientific, sizeof(scientific), "%.16e", value);
    const char *cursor = scientific;
    int negative = *cursor == '-';
    if (negative) cursor++;
    char digits[18];
    digits[0] = cursor[0];
    memcpy(digits + 1, cursor + 2, 16);
    int exponent = atoi(cursor + 19);

    for (int precision = 15; precision < 17; precision++) {
        /* For normal numbers an ulp is 1.1 to 22.2 units of the 17th
           significant digit, so a 15-digit form can only read back as the
           same value when the 17-digit form is within about 11.6 units of
           it, i.e. its last two digits are 00-12 or 88-99. Skip the strtod
           check otherwise. */
        int last_two = (digits[15] - '0') * 10 + (digits[16] - '0');

        if (precision == 15 && last_two > 12 && last_two < 88 && fabs(value) >= DBL_MIN) {
            continue;
        }

        char rounded[18];
        int rounded_exponent = exponent;
        memcpy(rounded, digits, (size_t) precision);
        int tail = precision + 1;

        while (tail < 17 && digits[tail] == '0') {
            tail++;
        }

        if (digits[precision] == '5' && tail == 17) {
            /* The 17-digit form ends in an exact half here, but the double
               itself may lie just below or above it: let printf round the
               exact binary value instead of rounding twice. */
            char exact[40];
            snprintf(exact, sizeof(exact), "%.*e", precision - 1, value);
            const char *mantissa = exact + negative;
            rounded[0] = mantissa[0];
            memcpy(rounded + 1, mantissa + 2, (size_t) (precision - 1));
            rounded_exponent = atoi(mantissa + precision + 2);
        } else if (digits[precision] >= '5') {
            int index = precision - 1;
            while (index >= 0 && rounded[index] == '9') {
                rounded[index--] = '0';
            }
            if (index >= 0) {
                rounded[index]++;
            } else {
                rounded[0] = '1';
                rounded_exponent++;
            }
        }

        if (rounded_exponent >= -4 && rounded_exponent < 17 && rounded_exponent >= precision) {
            continue;
        }

        int length = emerald_float_render(text, negative, rounded, precision, rounded_exponent);

        if (strtod(text, NULL) == value) {
            return length;
        }
    }

    return emerald_float_render(text, negative, digits, 17, exponent);
}

/* 0.1 prints as "0.1" rather than "0.10000000000000001". A candidate whose
   precision would switch %g to exponent notation where %.17g would not is
   skipped, which keeps integral values printed exactly as before (1.0 is
   "1", 1e16 is "10000000000000000", 1e20 is "1e+20"). */
EmeraldString *emerald_float64_to_string(double value) {
    char text[64];
    int written = isfinite(value)
        ? emerald_float_shortest(text, value)
        : snprintf(text, sizeof(text), "%.17g", value);
    return emerald_string_new((const uint8_t *) text, written < 0 ? 0 : (uint64_t) written);
}

int64_t emerald_float64_to_int(double value) {
    if (!isfinite(value) || value < -0x1p63 || value >= 0x1p63) emerald_number_fail("Float is outside the Int range");
    return (int64_t) value;
}

int64_t emerald_string_hash_int64(EmeraldString *text) {
    uint64_t hash = 14695981039346656037ULL;
    if (text != NULL) {
        for (uint64_t index = 0; index < text->length; index++) {
            hash ^= text->bytes[index];
            hash *= 1099511628211ULL;
        }
    }
    return (int64_t) (hash >> 1);
}

/* Allocation-free hashing for scalar and identity keys (HashMap/HashSet).
   Results are non-negative so they can be reduced with a plain remainder. */
int64_t emerald_hash_int64(int64_t value) {
    uint64_t x = (uint64_t) value + 0x9E3779B97F4A7C15ULL;
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9ULL;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EBULL;
    x ^= x >> 31;
    return (int64_t) (x >> 1);
}

/* -0.0 hashes like 0.0 (they compare equal); every NaN hashes alike. */
int64_t emerald_hash_float64(double value) {
    if (value == 0.0) return emerald_hash_int64(0);
    if (value != value) return emerald_hash_int64(INT64_C(0x7FF8000000000000));
    int64_t bits;
    memcpy(&bits, &value, sizeof bits);
    return emerald_hash_int64(bits);
}

int64_t emerald_hash_pointer(const void *value) {
    return emerald_hash_int64((int64_t) (uintptr_t) value);
}

/* Char is a single byte value. */
int32_t emerald_int64_to_char(int64_t value) {
    if (value < 0 || value > 255) emerald_number_fail("Int is outside the Char range");
    return (int32_t) value;
}
