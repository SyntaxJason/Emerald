#include "runtime/emerald_runtime.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
static const unsigned char bytes[] = {'a', 0, 'b', 0};
static const EmeraldString literal = {3, (uint8_t *) bytes};
int main(void) {
    hyperalloc_flow_init();
    EmeraldString *addresses[] = {(EmeraldString *) &literal};
    hyperalloc_flow_register_static_strings(addresses, 1);
    hyperalloc_flow_root_release(addresses[0]);
    assert(emerald_string_length(addresses[0]) == 3);
    EmeraldList *scalars = emerald_list_new_typed(0, 8);
    EmeraldList *inline_values = emerald_list_new_typed(2, 16);
    EmeraldList *references = emerald_list_new();
    for (intptr_t i = 0; i < 10000; i++) {
        emerald_list_add(scalars, (void *) i);
        int64_t pair[2] = {i, i + 1};
        emerald_list_add(inline_values, pair);
        int64_t *owned = hyperalloc_flow_alloc(8);
        *owned = i;
        emerald_list_add(references, owned);
    }
    for (int i = 0; i < 10000; i++) {
        int64_t pair[2];
        emerald_list_get_into(inline_values, i, pair);
        assert((intptr_t) emerald_list_get(scalars, i) == i);
        assert(pair[0] == i && pair[1] == i + 1);
        assert(*(int64_t *) emerald_list_get(references, i) == i);
    }
    hyperalloc_flow_root_release(scalars);
    hyperalloc_flow_root_release(inline_values);
    hyperalloc_flow_root_release(references);
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
    puts("resize-static-literals-ok");
}
