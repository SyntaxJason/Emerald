#include "emerald_runtime_internal.h"

static EmeraldString *emerald_string_alloc_contiguous(uint64_t length) {
    if (length > INT32_MAX || length > UINT64_MAX - sizeof(EmeraldString) - 1) {
        emerald_flow_fail(length);
    }

    EmeraldString *value = (EmeraldString *) emerald_alloc(sizeof(EmeraldString) + length + 1);
    value->length = length;
    value->bytes = (uint8_t *) (value + 1);
    value->bytes[length] = 0;
    return value;
}

EmeraldString *emerald_runtime_string_alloc(uint64_t length) {
    return emerald_string_alloc_contiguous(length);
}

/* Returns the first occurrence of needle in haystack, or NULL. memchr (which
   libc vectorises) skips to candidate positions for the first needle byte, so
   most of the haystack is never compared byte by byte. memmem is not used
   because it is a GNU/BSD extension. */
static const uint8_t *emerald_bytes_find(const uint8_t *haystack, uint64_t haystack_length, const uint8_t *needle, uint64_t needle_length) {
    if (needle_length == 0) {
        return haystack;
    }

    if (needle_length > haystack_length) {
        return NULL;
    }

    const uint8_t *cursor = haystack;
    const uint8_t *last = haystack + (haystack_length - needle_length);

    while (cursor <= last) {
        const uint8_t *hit = (const uint8_t *) memchr(cursor, needle[0], (size_t) (last - cursor) + 1);

        if (hit == NULL) {
            return NULL;
        }

        if (needle_length == 1 || memcmp(hit + 1, needle + 1, (size_t) (needle_length - 1)) == 0) {
            return hit;
        }

        cursor = hit + 1;
    }

    return NULL;
}

EmeraldString *emerald_string_new(const uint8_t *bytes, uint64_t length) {
    EmeraldString *value = emerald_string_alloc_contiguous(length);

    if (bytes != NULL && length > 0) {
        memcpy(value->bytes, bytes, (size_t) length);
    }

    return value;
}

EmeraldString *emerald_string_from_cstr(const char *text) {
    if (text == NULL) {
        return emerald_string_new((const uint8_t *) "", 0);
    }

    return emerald_string_new((const uint8_t *) text, (uint64_t) strlen(text));
}


EmeraldString *emerald_string_concat(EmeraldString *left, EmeraldString *right) {
    if (left == NULL) {
        left = emerald_static_string_from_cstr("");
    }

    if (right == NULL) {
        right = emerald_static_string_from_cstr("");
    }

    if (left->length > UINT64_MAX - right->length) {
        emerald_flow_fail(UINT64_MAX);
    }

    uint64_t length = left->length + right->length;
    EmeraldString *value = emerald_string_alloc_contiguous(length);

    if (left->length > 0) {
        memcpy(value->bytes, left->bytes, (size_t) left->length);
    }

    if (right->length > 0) {
        memcpy(value->bytes + left->length, right->bytes, (size_t) right->length);
    }

    return value;
}

int32_t emerald_string_equals(EmeraldString *left, EmeraldString *right) {
    if (left == right) {
        return 1;
    }

    if (left == NULL || right == NULL) {
        return 0;
    }

    if (left->length != right->length) {
        return 0;
    }

    if (left->length == 0) {
        return 1;
    }

    return memcmp(left->bytes, right->bytes, (size_t) left->length) == 0 ? 1 : 0;
}

int32_t emerald_string_length(EmeraldString *value) {
    if (value == NULL) {
        return 0;
    }

    return (int32_t) value->length;
}

int32_t emerald_string_starts_with(EmeraldString *value, EmeraldString *prefix) {
    if (value == NULL || prefix == NULL) {
        return 0;
    }

    if (prefix->length > value->length) {
        return 0;
    }

    if (prefix->length == 0) {
        return 1;
    }

    return memcmp(value->bytes, prefix->bytes, (size_t) prefix->length) == 0 ? 1 : 0;
}

int32_t emerald_string_ends_with(EmeraldString *value, EmeraldString *suffix) {
    if (value == NULL || suffix == NULL) {
        return 0;
    }

    if (suffix->length > value->length) {
        return 0;
    }

    if (suffix->length == 0) {
        return 1;
    }

    uint64_t offset = value->length - suffix->length;
    return memcmp(value->bytes + offset, suffix->bytes, (size_t) suffix->length) == 0 ? 1 : 0;
}

int32_t emerald_string_contains(EmeraldString *value, EmeraldString *needle) {
    if (value == NULL || needle == NULL) {
        return 0;
    }

    if (needle->length == 0) {
        return 1;
    }

    return emerald_bytes_find(value->bytes, value->length, needle->bytes, needle->length) != NULL ? 1 : 0;
}

EmeraldString *emerald_string_replace(EmeraldString *value, EmeraldString *needle, EmeraldString *replacement) {
    if (value == NULL) {
        value = emerald_static_string_from_cstr("");
    }

    if (needle == NULL || needle->length == 0 || needle->length > value->length) {
        return emerald_string_new(value->bytes, value->length);
    }

    if (replacement == NULL) {
        replacement = emerald_static_string_from_cstr("");
    }

    const uint8_t *end = value->bytes + value->length;
    const uint8_t *cursor = value->bytes;
    const uint8_t *match;
    uint64_t matches = 0;

    while ((match = emerald_bytes_find(cursor, (uint64_t) (end - cursor), needle->bytes, needle->length)) != NULL) {
        matches++;
        cursor = match + needle->length;
    }

    if (matches == 0) {
        return emerald_string_new(value->bytes, value->length);
    }

    uint64_t result_length = value->length;

    if (replacement->length >= needle->length) {
        uint64_t growth = replacement->length - needle->length;

        if (growth > 0 && matches > (UINT64_MAX - result_length) / growth) {
            emerald_flow_fail(UINT64_MAX);
        }

        result_length += matches * growth;
    } else {
        result_length -= matches * (needle->length - replacement->length);
    }

    EmeraldString *result = emerald_string_alloc_contiguous(result_length);
    uint8_t *target = result->bytes;
    cursor = value->bytes;

    /* Copy the unchanged run before each match in one memcpy. */
    while ((match = emerald_bytes_find(cursor, (uint64_t) (end - cursor), needle->bytes, needle->length)) != NULL) {
        size_t run = (size_t) (match - cursor);

        if (run > 0) {
            memcpy(target, cursor, run);
            target += run;
        }

        if (replacement->length > 0) {
            memcpy(target, replacement->bytes, (size_t) replacement->length);
            target += replacement->length;
        }

        cursor = match + needle->length;
    }

    if (cursor < end) {
        memcpy(target, cursor, (size_t) (end - cursor));
    }

    return result;
}

EmeraldString *emerald_string_substring(EmeraldString *value, int32_t start, int32_t end) {
    if (value == NULL) {
        return emerald_string_from_cstr("");
    }

    uint64_t safe_start = start < 0 ? 0 : (uint64_t) start;
    uint64_t safe_end = end < 0 ? 0 : (uint64_t) end;

    if (safe_end < safe_start) {
        safe_end = safe_start;
    }

    if (safe_start > value->length) {
        safe_start = value->length;
    }

    if (safe_end > value->length) {
        safe_end = value->length;
    }

    return emerald_string_new(value->bytes + safe_start, safe_end - safe_start);
}

int32_t emerald_string_index_of(EmeraldString *value, EmeraldString *needle) {
    if (value == NULL || needle == NULL) {
        return -1;
    }

    if (needle->length == 0) {
        return 0;
    }

    const uint8_t *match = emerald_bytes_find(value->bytes, value->length, needle->bytes, needle->length);

    if (match == NULL) {
        return -1;
    }

    uint64_t index = (uint64_t) (match - value->bytes);
    return index > INT32_MAX ? INT32_MAX : (int32_t) index;
}

EmeraldList *emerald_string_split(EmeraldString *value, EmeraldString *delimiter) {
    if (value == NULL) {
        value = emerald_static_string_from_cstr("");
    }

    if (delimiter == NULL) {
        delimiter = emerald_static_string_from_cstr("");
    }

    EmeraldList *result = emerald_list_new_typed(EMERALD_LIST_REFERENCE, sizeof(void *));

    if (delimiter->length == 0) {
        uint64_t index = 0;

        while (index < value->length) {
            EmeraldString *part = emerald_string_new(value->bytes + index, 1);
            emerald_list_add(result, part);
            index++;
        }

        if (value->length == 0) {
            emerald_list_add(result, emerald_string_from_cstr(""));
        }

        return result;
    }

    const uint8_t *end = value->bytes + value->length;
    const uint8_t *start = value->bytes;
    const uint8_t *match;

    while ((match = emerald_bytes_find(start, (uint64_t) (end - start), delimiter->bytes, delimiter->length)) != NULL) {
        emerald_list_add(result, emerald_string_new(start, (uint64_t) (match - start)));
        start = match + delimiter->length;
    }

    emerald_list_add(result, emerald_string_new(start, (uint64_t) (end - start)));
    return result;
}

EmeraldString *emerald_string_trim(EmeraldString *value) {
    if (value == NULL || value->length == 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t start = 0;
    uint64_t end = value->length;

    while (start < end && isspace((unsigned char) value->bytes[start])) {
        start++;
    }

    while (end > start && isspace((unsigned char) value->bytes[end - 1])) {
        end--;
    }

    return emerald_string_new(value->bytes + start, end - start);
}

EmeraldString *emerald_string_to_lower(EmeraldString *value) {
    if (value == NULL) {
        return emerald_string_from_cstr("");
    }

    EmeraldString *result = emerald_string_new(NULL, value->length);
    uint64_t index = 0;

    while (index < value->length) {
        result->bytes[index] = (uint8_t) tolower((unsigned char) value->bytes[index]);
        index++;
    }

    return result;
}

EmeraldString *emerald_string_to_upper(EmeraldString *value) {
    if (value == NULL) {
        return emerald_string_from_cstr("");
    }

    EmeraldString *result = emerald_string_new(NULL, value->length);
    uint64_t index = 0;

    while (index < value->length) {
        result->bytes[index] = (uint8_t) toupper((unsigned char) value->bytes[index]);
        index++;
    }

    return result;
}

int32_t emerald_string_to_int(EmeraldString *value) {
    if (value == NULL || value->length == 0) {
        return 0;
    }

    errno = 0;
    char *end = NULL;
    long parsed = strtol((const char *) value->bytes, &end, 10);

    if (end == (char *) value->bytes) {
        return 0;
    }

    if (errno == ERANGE || parsed > INT32_MAX) {
        return INT32_MAX;
    }

    if (parsed < INT32_MIN) {
        return INT32_MIN;
    }

    return (int32_t) parsed;
}

int32_t emerald_string_char_at(EmeraldString *value, int32_t index) {
    if (value == NULL || index < 0 || (uint64_t) index >= value->length) {
        return 0;
    }

    return (int32_t) value->bytes[index];
}

EmeraldString *emerald_char_to_string(int32_t value) {
    uint8_t byte = (uint8_t) value;
    return emerald_string_new(&byte, 1);
}

int32_t emerald_char_is_digit(int32_t value) {
    return isdigit((unsigned char) value) ? 1 : 0;
}

int32_t emerald_char_is_letter(int32_t value) {
    return isalpha((unsigned char) value) ? 1 : 0;
}

int32_t emerald_char_is_whitespace(int32_t value) {
    return isspace((unsigned char) value) ? 1 : 0;
}

EmeraldString *emerald_int_to_string(int32_t value) {
    return emerald_int64_to_string((int64_t) value);
}

/* Index of the last occurrence of needle in value, or -1. An empty needle
   matches at the end. */
int64_t emerald_string_last_index_of(EmeraldString *value, EmeraldString *needle) {
    if (value == NULL || needle == NULL || needle->length > value->length) {
        return -1;
    }

    uint64_t index = value->length - needle->length + 1;

    while (index > 0) {
        index--;

        if (needle->length == 0 || memcmp(value->bytes + index, needle->bytes, (size_t) needle->length) == 0) {
            return (int64_t) index;
        }
    }

    return -1;
}

EmeraldString *emerald_string_repeat(EmeraldString *value, int64_t count) {
    /* A non-positive count yields the empty String. */
    if (value == NULL || value->length == 0 || count <= 0) {
        return emerald_string_from_cstr("");
    }

    if ((uint64_t) count > UINT64_MAX / value->length) {
        emerald_flow_fail(UINT64_MAX);
    }

    EmeraldString *result = emerald_string_alloc_contiguous(value->length * (uint64_t) count);
    uint64_t offset = 0;

    for (int64_t index = 0; index < count; index++) {
        memcpy(result->bytes + offset, value->bytes, (size_t) value->length);
        offset += value->length;
    }

    return result;
}

EmeraldString *emerald_string_trim_start(EmeraldString *value) {
    if (value == NULL || value->length == 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t start = 0;

    while (start < value->length && isspace((unsigned char) value->bytes[start])) {
        start++;
    }

    return emerald_string_new(value->bytes + start, value->length - start);
}

EmeraldString *emerald_string_trim_end(EmeraldString *value) {
    if (value == NULL || value->length == 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t end = value->length;

    while (end > 0 && isspace((unsigned char) value->bytes[end - 1])) {
        end--;
    }

    return emerald_string_new(value->bytes, end);
}

int32_t emerald_string_is_blank(EmeraldString *value) {
    if (value == NULL) {
        return 1;
    }

    for (uint64_t index = 0; index < value->length; index++) {
        if (!isspace((unsigned char) value->bytes[index])) {
            return 0;
        }
    }

    return 1;
}

/* Byte-wise lexicographic comparison: -1, 0 or 1. */
int64_t emerald_string_compare(EmeraldString *left, EmeraldString *right) {
    uint64_t left_length = left == NULL ? 0 : left->length;
    uint64_t right_length = right == NULL ? 0 : right->length;
    uint64_t shared = left_length < right_length ? left_length : right_length;
    int order = shared == 0 ? 0 : memcmp(left->bytes, right->bytes, (size_t) shared);

    if (order != 0) {
        return order < 0 ? -1 : 1;
    }

    if (left_length == right_length) {
        return 0;
    }

    return left_length < right_length ? -1 : 1;
}

/* Concatenates a List<String> with a separator between elements. */
EmeraldString *emerald_string_join(EmeraldList *parts, EmeraldString *separator) {
    int32_t count = parts == NULL ? 0 : emerald_list_length(parts);
    uint64_t separator_length = separator == NULL ? 0 : separator->length;

    if (count <= 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t total = separator_length * (uint64_t) (count - 1);

    for (int32_t index = 0; index < count; index++) {
        EmeraldString *part = (EmeraldString *) emerald_list_get(parts, index);
        uint64_t part_length = part == NULL ? 0 : part->length;

        if (part_length > UINT64_MAX - total) {
            emerald_flow_fail(UINT64_MAX);
        }

        total += part_length;
    }

    EmeraldString *result = emerald_string_alloc_contiguous(total);
    uint64_t offset = 0;

    for (int32_t index = 0; index < count; index++) {
        EmeraldString *part = (EmeraldString *) emerald_list_get(parts, index);

        if (index > 0 && separator_length > 0) {
            memcpy(result->bytes + offset, separator->bytes, (size_t) separator_length);
            offset += separator_length;
        }

        if (part != NULL && part->length > 0) {
            memcpy(result->bytes + offset, part->bytes, (size_t) part->length);
            offset += part->length;
        }
    }

    return result;
}
