#include "emerald_runtime.h"

#include <stdint.h>
#include <stdio.h>

/* hyperalloc_flow_share_borrowed turns a caller's unparented Root into a counted
   reference before a callee hands it to a short-lived owner, such as a stack
   Local that releases its children on scope exit. */

static int unparented_root_survives_short_owner(void) {
    hyperalloc_flow_init();

    uint8_t *data = (uint8_t *) hyperalloc_flow_alloc(8);
    uint64_t context[2] = {0, 0};
    hyperalloc_flow_share_borrowed(data);
    hyperalloc_flow_owner_enter(context);
    hyperalloc_flow_root_adopt(context, data);
    hyperalloc_flow_owner_leave(context);

    /* The Local's death only drops its edge; ASan checks the write. */
    data[0] = 7;

    if (hyperalloc_flow_allocation_count() != 1 || hyperalloc_flow_bond_live_count() != 1) {
        return 1;
    }

    /* The caller's scope release now drops the last count. */
    hyperalloc_flow_root_release(data);

    if (hyperalloc_flow_allocation_count() != 0 || hyperalloc_flow_invalid_release_count() != 0) {
        return 2;
    }

    hyperalloc_flow_shutdown();
    return 0;
}

static int long_lived_adopter_keeps_shared_value(void) {
    hyperalloc_flow_init();

    void *registry = hyperalloc_flow_alloc(8);
    uint8_t *data = (uint8_t *) hyperalloc_flow_alloc(8);
    hyperalloc_flow_share_borrowed(data);
    hyperalloc_flow_root_adopt(registry, data);
    hyperalloc_flow_root_release(data);
    data[0] = 3;

    if (hyperalloc_flow_allocation_count() != 2) {
        return 11;
    }

    hyperalloc_flow_root_release(registry);

    if (hyperalloc_flow_allocation_count() != 0) {
        return 12;
    }

    hyperalloc_flow_shutdown();
    return 0;
}

static int owned_bonded_and_foreign_values_are_untouched(void) {
    hyperalloc_flow_init();

    /* A child of another owner keeps its unique parent edge; a later
       adoption promotes it with one edge per owner as before. */
    void *parent = hyperalloc_flow_alloc(8);
    void *child = hyperalloc_flow_alloc(8);
    hyperalloc_flow_root_adopt(parent, child);
    hyperalloc_flow_share_borrowed(child);

    if (hyperalloc_flow_bond_live_count() != 0) {
        return 21;
    }

    /* Sharing twice, or sharing a Bond, keeps a single counted reference. */
    void *bond = hyperalloc_flow_bond_alloc(8);
    hyperalloc_flow_share_borrowed(bond);
    hyperalloc_flow_share_borrowed(bond);
    void *shared = hyperalloc_flow_alloc(8);
    hyperalloc_flow_share_borrowed(shared);
    hyperalloc_flow_share_borrowed(shared);
    hyperalloc_flow_bond_release(bond);
    hyperalloc_flow_root_release(shared);

    /* Memory Flow does not manage is ignored without an invalid release. */
    uint64_t foreign = 0;
    hyperalloc_flow_share_borrowed(&foreign);
    hyperalloc_flow_share_borrowed(NULL);
    hyperalloc_flow_root_release(parent);

    if (hyperalloc_flow_allocation_count() != 0 || hyperalloc_flow_bond_live_count() != 0 || hyperalloc_flow_invalid_release_count() != 0) {
        return 22;
    }

    hyperalloc_flow_shutdown();
    return 0;
}

int main(void) {
    int result = unparented_root_survives_short_owner();

    if (result == 0) {
        result = long_lived_adopter_keeps_shared_value();
    }

    if (result == 0) {
        result = owned_bonded_and_foreign_values_are_untouched();
    }

    if (result != 0) {
        fprintf(stderr, "flow share-borrowed test failed: %d\n", result);
        return result;
    }

    printf("flow-share-borrowed-ok\n");
    return 0;
}
