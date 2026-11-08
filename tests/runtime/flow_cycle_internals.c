/* Exercise counter wrap and shutdown through the public lifetime operations.
   The single-TU include is only needed to force otherwise unreachable counters. */
#include "../../runtime/src/hyperalloc_flow.c"
#include <assert.h>
#include <stddef.h>

static void allocation_alignment(void) {
    hyperalloc_flow_init();
    for (uint64_t size = 0; size <= 128; size++) {
        unsigned char *memory = hyperalloc_flow_alloc(size);
        assert((uintptr_t) memory % _Alignof(max_align_t) == 0);
        uint64_t actual_size = size == 0 ? 8 : size;
        for (uint64_t i = 0; i < actual_size; i++) assert(memory[i] == 0);
        memset(memory, 42, (size_t) actual_size);
        hyperalloc_flow_owner_enter(memory);
        hyperalloc_flow_root_release(memory);
    }
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
}

int main(void) {
    allocation_alignment();
    enum { N = 128 };
    void *nodes[N];
    for (int mode = 0; mode < 3; mode++) {
        hyperalloc_flow_init();
        for (int i = 0; i < N; i++) nodes[i] = hyperalloc_flow_bond_alloc(8);
        for (int i = 0; i < N; i++) hyperalloc_flow_root_adopt(nodes[i], nodes[(i + 1) % N]);
        hyperalloc_flow_bond_release(nodes[0]);
        if (mode == 0) {
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
            assert(hyperalloc_flow_allocation_count() == 0);
            assert(hyperalloc_flow_default_chamber.cycle_components == NULL);
        } else if (mode == 1) {
            hyperalloc_flow_default_chamber.cycle_graph_revision = UINT64_MAX;
            void *owner = hyperalloc_flow_alloc(8);
            hyperalloc_flow_root_adopt(owner, nodes[0]);
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
            assert(hyperalloc_flow_allocation_count() == N + 1);
            hyperalloc_flow_root_release(owner);
            assert(hyperalloc_flow_allocation_count() == 0);
        }
        /* mode 2 leaves a cached live component for shutdown to free. */
        hyperalloc_flow_shutdown();
    }
    printf("Flow metadata: block=%zu edge=%zu component=%zu bytes\n",
        sizeof(HyperAllocFlowBlock), sizeof(HyperAllocFlowBondEdge), sizeof(HyperAllocFlowCycleComponent));
    puts("flow-cycle-internals-ok");
    return 0;
}
