#include "emerald_runtime.h"
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

static void empty_containers(void) {
    enum { N = 1024 };
    EmeraldList *lists[N];
    for (int mode = 0; mode < 3; mode++) {
        hyperalloc_flow_init();
        for (int i = 0; i < N; i++) lists[i] = emerald_list_new_typed(mode, 8);
        assert(hyperalloc_flow_allocation_count() == N);
        assert(hyperalloc_flow_allocated_bytes() == N * sizeof(EmeraldList));
        for (int i = 0; i < N; i++) {
            assert(emerald_list_length(lists[i]) == 0);
            emerald_list_clear(lists[i]);
            hyperalloc_flow_root_release(lists[i]);
        }
        assert(hyperalloc_flow_allocation_count() == 0);
        hyperalloc_flow_shutdown();
    }
}

static void clear_and_share(void) {
    hyperalloc_flow_init();
    EmeraldList *first = emerald_list_new();
    EmeraldList *second = emerald_list_new();
    EmeraldString *shared = emerald_string_from_cstr("still alive");
    emerald_list_add(first, shared);
    emerald_list_add(second, shared);
    assert(emerald_list_remove_at(first, 0) == shared);
    emerald_list_clear(first);
    emerald_list_clear(second);
    assert(hyperalloc_flow_allocation_count() == 3);
    assert(emerald_string_length(shared) == 11);
    hyperalloc_flow_bond_release(shared); /* Reference transferred by removeAt. */
    assert(hyperalloc_flow_allocation_count() == 2);
    for (int round = 0; round < 4; round++) {
        for (int i = 0; i < 100; i++) emerald_list_add(first, emerald_string_from_cstr("owned"));
        assert(emerald_list_length(first) == 100);
        emerald_list_clear(first);
        assert(hyperalloc_flow_allocation_count() == 2);
        assert(first->capacity == 0 && first->items == NULL);
    }
    hyperalloc_flow_root_release(first);
    hyperalloc_flow_root_release(second);
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
}

static void inline_and_primitive(void) {
    hyperalloc_flow_init();
    struct Pair { int32_t x, y; } input = {42, 7}, output = {0, 0};
    EmeraldList *list = emerald_list_new_typed(2, sizeof(input));
    assert(hyperalloc_flow_allocation_count() == 1);
    emerald_list_add(list, &input);
    input.x = 9;
    emerald_list_get_into(list, 0, &output);
    assert(output.x == 42 && output.y == 7);
    emerald_list_remove_at_into(list, 0, &output);
    assert(output.x == 42 && list->scratch == NULL);
    emerald_list_clear(list);
    emerald_list_add(list, &input);
    struct Pair *removed = emerald_list_remove_at(list, 0);
    assert(removed->x == 9 && removed->y == 7);
    emerald_list_clear(list);
    assert(removed->x == 9); /* Removal scratch keeps its documented lifetime. */
    hyperalloc_flow_root_release(list);
    list = emerald_list_new_typed(0, sizeof(void *));
    for (uintptr_t i = 0; i < 100; i++) emerald_list_add(list, (void *)i);
    assert(emerald_list_get(list, 42) == (void *)(uintptr_t)42);
    emerald_list_clear(list);
    assert(hyperalloc_flow_allocation_count() == 1);
    emerald_list_add_at(list, 0, (void *)(uintptr_t)7);
    assert(emerald_list_remove_at(list, 0) == (void *)(uintptr_t)7);
    hyperalloc_flow_root_release(list);
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
}

int main(void) {
    empty_containers();
    clear_and_share();
    inline_and_primitive();
    puts("flow-list-memory-ok");
    return 0;
}
