#include "emerald_runtime_internal.h"

static uint64_t emerald_list_stride(EmeraldList *list) {
    if (list->element_mode == EMERALD_LIST_INLINE) {
        return list->element_size;
    }

    return sizeof(void *);
}

static uint8_t *emerald_list_data(EmeraldList *list) {
    return (uint8_t *) list->items;
}

static void *emerald_list_slot(EmeraldList *list, uint64_t index) {
    return emerald_list_data(list) + index * emerald_list_stride(list);
}

/* get/set/removeAt outside [0, length) is a program error. It used to return
   NULL/0 or do nothing, which surfaced later as a wrong value or a crash far
   from the cause; panic at the faulting call instead. */
static void emerald_list_index_fail(const char *operation, int32_t index, uint64_t length) {
    emerald_runtime_flush_stdout();
    fprintf(stderr, "Emerald panic: List.%s index %d out of bounds for length %llu\n",
        operation, (int) index, (unsigned long long) length);
    emerald_flow_shutdown();
    abort();
}

static void emerald_list_check_index(EmeraldList *list, int32_t index, const char *operation) {
    if (index < 0 || (uint64_t) index >= list->length) {
        emerald_list_index_fail(operation, index, list->length);
    }
}

static void emerald_list_ensure(EmeraldList *list, uint64_t capacity) {
    /* The compatibility runtime index ABI remains i32. Refuse growth before
       length could silently wrap; the existing u64 header layout is unchanged. */
    if (capacity > INT32_MAX) emerald_flow_fail(capacity);
    if (list->capacity >= capacity) {
        return;
    }

    uint64_t next = list->capacity < 4 ? 4 : list->capacity;

    while (next < capacity) {
        if (next > UINT64_MAX / 2) {
            emerald_flow_fail(next);
        }

        next *= 2;
    }

    uint64_t stride = emerald_list_stride(list);
    if (stride == 0 || next > UINT64_MAX / stride) {
        emerald_flow_fail(next);
    }

    uint64_t bytes = next * stride;
    list->items = (void **) emerald_flow_resize_atomic_owned(list, list->items, bytes);
    list->capacity = next;
}

EmeraldList *emerald_list_new_typed(int32_t element_mode, uint64_t element_size) {
    if (element_mode < EMERALD_LIST_PRIMITIVE || element_mode > EMERALD_LIST_INLINE) {
        element_mode = EMERALD_LIST_REFERENCE;
    }

    if (element_mode != EMERALD_LIST_INLINE) {
        element_size = sizeof(void *);
    } else if (element_size == 0) {
        element_size = 1;
    }

    EmeraldList *list = (EmeraldList *) emerald_alloc(sizeof(EmeraldList));
    list->length = 0;
    list->capacity = 0;
    list->items = NULL;
    list->scratch = NULL;
    list->element_size = element_size;
    list->element_mode = element_mode;
    /* Empty containers own no backing allocation. Inline removal scratch is
       likewise created only when a caller actually requests that ABI. */

    return list;
}

EmeraldList *emerald_list_new(void) {
    return emerald_list_new_typed(EMERALD_LIST_REFERENCE, sizeof(void *));
}

int32_t emerald_list_length(EmeraldList *list) {
    return list == NULL ? 0 : (int32_t) list->length;
}

void emerald_list_add(EmeraldList *list, void *value) {
    if (list == NULL) {
        return;
    }

    emerald_list_ensure(list, list->length + 1);

    if (list->element_mode == EMERALD_LIST_INLINE) {
        if (value != NULL) {
            memcpy(emerald_list_slot(list, list->length), value, (size_t) list->element_size);
        } else {
            memset(emerald_list_slot(list, list->length), 0, (size_t) list->element_size);
        }

        emerald_flow_note_container_inline_copy();
    } else {
        list->items[list->length] = value;

        if (list->element_mode == EMERALD_LIST_REFERENCE && value != NULL) {
            emerald_flow_root_adopt(list, value);
            emerald_flow_note_container_owned_adoption();
        }
    }

    list->length += 1;
}

void *emerald_list_get(EmeraldList *list, int32_t index) {
    if (list == NULL) {
        return NULL;
    }

    emerald_list_check_index(list, index, "get");

    if (list->element_mode == EMERALD_LIST_INLINE) {
        return emerald_list_slot(list, (uint64_t) index);
    }

    return list->items[index];
}

void emerald_list_get_into(EmeraldList *list, int32_t index, void *output) {
    if (output == NULL) {
        return;
    }

    if (list == NULL || list->element_mode != EMERALD_LIST_INLINE) {
        return;
    }

    emerald_list_check_index(list, index, "get");
    memcpy(output, emerald_list_slot(list, (uint64_t) index), (size_t) list->element_size);
    emerald_flow_note_container_inline_copy();
}

void emerald_list_set(EmeraldList *list, int32_t index, void *value) {
    if (list == NULL) {
        return;
    }

    emerald_list_check_index(list, index, "set");

    if (list->element_mode == EMERALD_LIST_INLINE) {
        if (value != NULL) {
            memcpy(emerald_list_slot(list, (uint64_t) index), value, (size_t) list->element_size);
        } else {
            memset(emerald_list_slot(list, (uint64_t) index), 0, (size_t) list->element_size);
        }

        emerald_flow_note_container_inline_copy();
        return;
    }

    void *previous = list->items[index];
    list->items[index] = value;

    if (list->element_mode == EMERALD_LIST_REFERENCE) {
        emerald_flow_root_replace(list, previous, value);
        if (previous != NULL) {
            emerald_flow_note_container_owned_release();
        }

        if (value != NULL) {
            emerald_flow_note_container_owned_adoption();
        }
    }
}

void emerald_list_add_at(EmeraldList *list, int32_t index, void *value) {
    if (list == NULL) {
        return;
    }

    if (index < 0) {
        index = 0;
    }
    if ((uint64_t) index > list->length) {
        index = (int32_t) list->length;
    }

    emerald_list_ensure(list, list->length + 1);
    uint64_t stride = emerald_list_stride(list);
    uint8_t *target = (uint8_t *) emerald_list_slot(list, (uint64_t) index);
    memmove(target + stride, target, (size_t) ((list->length - (uint64_t) index) * stride));

    if (list->element_mode == EMERALD_LIST_INLINE) {
        if (value != NULL) {
            memcpy(target, value, (size_t) stride);
        } else {
            memset(target, 0, (size_t) stride);
        }
        emerald_flow_note_container_inline_copy();
    } else {
        list->items[index] = value;
        if (list->element_mode == EMERALD_LIST_REFERENCE && value != NULL) {
            emerald_flow_root_adopt(list, value);
            emerald_flow_note_container_owned_adoption();
        }
    }

    list->length += 1;
}

int32_t emerald_list_index_of(EmeraldList *list, void *value) {
    if (list == NULL) {
        return -1;
    }

    uint64_t index = 0;
    while (index < list->length) {
        int equal = list->element_mode == EMERALD_LIST_INLINE
            ? value != NULL && memcmp(emerald_list_slot(list, index), value, (size_t) list->element_size) == 0
            : list->items[index] == value;
        if (equal) {
            return (int32_t) index;
        }
        index += 1;
    }

    return -1;
}

void *emerald_list_remove_at(EmeraldList *list, int32_t index) {
    if (list == NULL) {
        return NULL;
    }

    emerald_list_check_index(list, index, "removeAt");

    uint64_t current = (uint64_t) index;
    uint64_t stride = emerald_list_stride(list);
    void *value = NULL;

    if (list->element_mode == EMERALD_LIST_INLINE) {
        if (list->scratch == NULL) {
            list->scratch = emerald_alloc_atomic(list->element_size);
            emerald_flow_root_adopt(list, list->scratch);
        }
        memcpy(list->scratch, emerald_list_slot(list, current), (size_t) list->element_size);
        value = list->scratch;
    } else {
        value = list->items[current];
        if (list->element_mode == EMERALD_LIST_REFERENCE && value != NULL) {
            emerald_flow_root_detach(list, value);
        }
    }

    uint8_t *target = (uint8_t *) emerald_list_slot(list, current);
    memmove(target, target + stride, (size_t) ((list->length - current - 1) * stride));
    list->length -= 1;
    memset(emerald_list_slot(list, list->length), 0, (size_t) stride);
    return value;
}

void emerald_list_remove_at_into(EmeraldList *list, int32_t index, void *output) {
    if (output == NULL) {
        return;
    }

    if (list == NULL || list->element_mode != EMERALD_LIST_INLINE) {
        return;
    }

    emerald_list_check_index(list, index, "removeAt");
    uint64_t current = (uint64_t) index;
    uint64_t stride = emerald_list_stride(list);
    memcpy(output, emerald_list_slot(list, current), (size_t) stride);
    uint8_t *target = (uint8_t *) emerald_list_slot(list, current);
    memmove(target, target + stride, (size_t) ((list->length - current - 1) * stride));
    list->length -= 1;
    memset(emerald_list_slot(list, list->length), 0, (size_t) stride);
    emerald_flow_note_container_inline_copy();
}

/* String lists need value equality: Crystal-based stages compare strings by
   content, so pointer identity here would diverge between bootstrap stages. */
int32_t emerald_list_index_of_string(EmeraldList *list, EmeraldString *value) {
    if (list == NULL || list->element_mode == EMERALD_LIST_INLINE) {
        return emerald_list_index_of(list, value);
    }

    uint64_t index = 0;
    while (index < list->length) {
        EmeraldString *item = (EmeraldString *) list->items[index];
        int equal = item == value || (item != NULL && value != NULL && emerald_string_equals(item, value));
        if (equal) {
            return (int32_t) index;
        }
        index += 1;
    }

    return -1;
}

int32_t emerald_list_remove_string(EmeraldList *list, EmeraldString *value) {
    int32_t index = emerald_list_index_of_string(list, value);
    if (index < 0) {
        return 0;
    }

    void *removed = emerald_list_remove_at(list, index);
    if (list->element_mode == EMERALD_LIST_REFERENCE && removed != NULL) {
        emerald_flow_root_release(removed);
        emerald_flow_note_container_owned_release();
    }

    return 1;
}

int32_t emerald_list_remove(EmeraldList *list, void *value) {
    int32_t index = emerald_list_index_of(list, value);
    if (index < 0) {
        return 0;
    }

    void *removed = emerald_list_remove_at(list, index);
    if (list->element_mode == EMERALD_LIST_REFERENCE && removed != NULL) {
        emerald_flow_root_release(removed);
        emerald_flow_note_container_owned_release();
    }

    return 1;
}

void emerald_list_clear(EmeraldList *list) {
    if (list == NULL) {
        return;
    }

    if (list->element_mode == EMERALD_LIST_REFERENCE) {
        uint64_t index = 0;
        while (index < list->length) {
            void *value = list->items[index];
            if (value != NULL) {
                emerald_flow_root_replace(list, value, NULL);
                emerald_flow_note_container_owned_release();
            }
            index += 1;
        }
    }

    list->length = 0;
    void **previous = list->items;
    list->items = NULL;
    list->capacity = 0;
    emerald_flow_root_replace(list, previous, NULL);
}
