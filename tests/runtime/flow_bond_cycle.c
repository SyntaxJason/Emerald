#include "emerald_runtime.h"

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

static int original_regressions(void) {
    hyperalloc_flow_init();

    void *left = hyperalloc_flow_bond_alloc(8);
    void *right = hyperalloc_flow_bond_alloc(8);
    hyperalloc_flow_root_replace(left, NULL, right);
    hyperalloc_flow_root_replace(right, NULL, left);
    hyperalloc_flow_bond_release(left);

    if (hyperalloc_flow_bond_live_count() != 2) {
        return 1;
    }

    hyperalloc_flow_bond_release(right);

    if (hyperalloc_flow_bond_live_count() != 0) {
        return 2;
    }

    if (hyperalloc_flow_bond_cycle_collection_count() != 1) {
        return 3;
    }

    if (hyperalloc_flow_bond_cycle_collected_count() != 2) {
        return 4;
    }

    if (hyperalloc_flow_bond_cycle_collected_bytes() != 16) {
        return 5;
    }

    uint8_t *owner = (uint8_t *) hyperalloc_flow_alloc(8);
    uint8_t *shared_child = (uint8_t *) hyperalloc_flow_alloc(8);
    hyperalloc_flow_root_adopt(owner, shared_child);
    hyperalloc_flow_root_adopt(owner, shared_child);
    hyperalloc_flow_root_replace(owner, shared_child, NULL);

    /* Replacing one of two same-owner fields must leave the other lifetime
       edge intact. ASan covers the write; the counters cover final release. */
    shared_child[0] = 42;

    if (hyperalloc_flow_allocation_count() != 2) {
        return 6;
    }

    hyperalloc_flow_root_release(owner);

    if (hyperalloc_flow_allocation_count() != 0) {
        return 7;
    }

    hyperalloc_flow_shutdown();
    return 0;
}


#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: %s\n", __func__, __LINE__, #condition); \
        return 1; \
    } \
} while (0)

static int promotion_lifetimes(void) {
    for (int order = 0; order < 2; order++) {
        hyperalloc_flow_init();
        void *owner = hyperalloc_flow_alloc(8);
        uint8_t *child = hyperalloc_flow_alloc(8);
        hyperalloc_flow_root_adopt(owner, child);
        hyperalloc_flow_bond_promote(child);
        hyperalloc_flow_bond_promote(child); /* Promotion is idempotent. */
        if (order == 0) {
            hyperalloc_flow_root_release(owner);
            child[0] = 42;
            CHECK(hyperalloc_flow_allocation_count() == 1);
            hyperalloc_flow_bond_release(child);
        } else {
            hyperalloc_flow_bond_release(child);
            child[0] = 42;
            CHECK(hyperalloc_flow_allocation_count() == 2);
            hyperalloc_flow_root_release(owner);
        }
        CHECK(hyperalloc_flow_allocation_count() == 0);
        CHECK(hyperalloc_flow_bond_live_count() == 0);
        hyperalloc_flow_shutdown();
    }

    hyperalloc_flow_init();
    void *first = hyperalloc_flow_alloc(8);
    void *second = hyperalloc_flow_alloc(8);
    uint8_t *child = hyperalloc_flow_alloc(8);
    hyperalloc_flow_root_adopt(first, child);
    hyperalloc_flow_bond_promote(child);
    hyperalloc_flow_root_adopt(second, child);
    hyperalloc_flow_bond_release(child);
    hyperalloc_flow_root_release(first);
    child[0] = 42;
    CHECK(hyperalloc_flow_allocation_count() == 2);
    /* Detach transfers the second owner's reference to this scope. */
    CHECK(hyperalloc_flow_root_detach(second, child) == child);
    hyperalloc_flow_root_release(second);
    child[0] = 43;
    hyperalloc_flow_bond_release(child);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
    return 0;
}

static int mixed_cycles(void) {
    for (int with_middle_bond = 0; with_middle_bond < 2; with_middle_bond++) {
        hyperalloc_flow_init();
        void *a = hyperalloc_flow_bond_alloc(8);
        void *b = hyperalloc_flow_alloc(8);
        hyperalloc_flow_root_adopt(a, b);
        if (with_middle_bond) {
            void *c = hyperalloc_flow_bond_alloc(8);
            hyperalloc_flow_root_adopt(b, c);
            hyperalloc_flow_root_adopt(c, a);
            hyperalloc_flow_bond_release(a);
            CHECK(hyperalloc_flow_allocation_count() == 3);
            hyperalloc_flow_bond_release(c);
        } else {
            /* A Bond back-reference to a Root ancestor is a counted edge. */
            hyperalloc_flow_root_adopt(b, a);
            hyperalloc_flow_bond_release(a);
        }
        CHECK(hyperalloc_flow_allocation_count() == 0);
        CHECK(hyperalloc_flow_allocated_bytes() == 0);
        CHECK(hyperalloc_flow_bond_live_count() == 0);
        hyperalloc_flow_shutdown();
    }

    hyperalloc_flow_init();
    void *a = hyperalloc_flow_bond_alloc(8);
    void *b = hyperalloc_flow_alloc(8);
    void *c = hyperalloc_flow_bond_alloc(8);
    uint8_t *outside = hyperalloc_flow_bond_alloc(8);
    hyperalloc_flow_root_adopt(a, b);
    hyperalloc_flow_root_adopt(b, c);
    hyperalloc_flow_root_adopt(c, a);
    hyperalloc_flow_root_adopt(a, outside);
    hyperalloc_flow_bond_release(a);
    hyperalloc_flow_bond_release(c);
    outside[0] = 42; /* An outgoing edge must not collect an externally held node. */
    CHECK(hyperalloc_flow_allocation_count() == 1);
    CHECK(hyperalloc_flow_bond_live_count() == 1);
    hyperalloc_flow_bond_release(outside);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    hyperalloc_flow_shutdown();

    hyperalloc_flow_init();
    void *owner = hyperalloc_flow_alloc(8);
    a = hyperalloc_flow_bond_alloc(8);
    b = hyperalloc_flow_alloc(8);
    c = hyperalloc_flow_bond_alloc(8);
    hyperalloc_flow_root_adopt(a, b);
    hyperalloc_flow_root_adopt(b, c);
    hyperalloc_flow_root_adopt(c, a);
    hyperalloc_flow_root_adopt(owner, a);
    hyperalloc_flow_bond_release(a);
    hyperalloc_flow_bond_release(c);
    CHECK(hyperalloc_flow_allocation_count() == 4);
    hyperalloc_flow_root_release(owner);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_bond_live_count() == 0);
    hyperalloc_flow_shutdown();
    return 0;
}

static int cached_components(void) {
    enum { N = 128 };
    void *nodes[N];
    void *roots[N];
    for (int operation = 0; operation < 5; operation++) {
        hyperalloc_flow_init();
        for (int i = 0; i < N; i++) {
            nodes[i] = hyperalloc_flow_bond_alloc(8);
            /* Root leaves exercise mixed traversal without joining the SCC. */
            roots[i] = hyperalloc_flow_alloc(8);
            hyperalloc_flow_root_adopt(nodes[i], roots[i]);
        }
        for (int i = 0; i < N; i++) {
            hyperalloc_flow_root_adopt(operation == 4 ? roots[i] : nodes[i], nodes[(i + 1) % N]);
        }
        hyperalloc_flow_bond_release(nodes[0]);
        if (operation == 0 || operation == 4) {
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
            /* Count graph traversals instead of asserting noisy wall-clock time. */
            CHECK(hyperalloc_flow_bond_cycle_scan_count() <= 3);
        } else if (operation == 1) {
            hyperalloc_flow_bond_retain(nodes[0]);
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
            CHECK(hyperalloc_flow_allocation_count() == N * 2);
            ((uint8_t *)nodes[0])[0] = 42;
            hyperalloc_flow_bond_release(nodes[0]);
        } else if (operation == 2) {
            void *owner = hyperalloc_flow_alloc(8);
            hyperalloc_flow_root_adopt(owner, nodes[0]); /* Invalidates the cached topology. */
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
            CHECK(hyperalloc_flow_allocation_count() == N * 2 + 1);
            hyperalloc_flow_root_detach(owner, nodes[0]);
            hyperalloc_flow_root_release(owner);
            CHECK(hyperalloc_flow_allocation_count() == N * 2);
            hyperalloc_flow_bond_release(nodes[0]);
        } else {
            hyperalloc_flow_root_replace(nodes[0], nodes[1], NULL); /* Break the cached ring. */
            for (int i = 1; i < N; i++) hyperalloc_flow_bond_release(nodes[i]);
        }
        CHECK(hyperalloc_flow_allocation_count() == 0);
        CHECK(hyperalloc_flow_bond_live_count() == 0);
        CHECK(hyperalloc_flow_invalid_release_count() == 0);
        hyperalloc_flow_shutdown();
    }
    return 0;
}

static int debug_object(void) {
    hyperalloc_flow_init();
    uint64_t *object = hyperalloc_flow_alloc(16);
    object[0] = 3;
    object[1] = 1; /* Data, not a String pointer; also run with FLOW_DEBUG=1. */
    hyperalloc_flow_root_release(object);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    hyperalloc_flow_shutdown();
    return 0;
}

enum { GRAPH_N = 96 };

static uint32_t graph_random(uint32_t *seed) {
    *seed = *seed * 1664525u + 1013904223u;
    return *seed;
}

static int check_graph(void **nodes, const uint8_t edges[GRAPH_N][GRAPH_N], const int *refs) {
    uint8_t reachable[GRAPH_N] = {0};
    int queue[GRAPH_N];
    int start = 0;
    int end = 0;
    for (int i = 0; i < GRAPH_N; i++) {
        if (refs[i] > 0) {
            reachable[i] = 1;
            queue[end++] = i;
        }
    }
    while (start < end) {
        int owner = queue[start++];
        for (int child = 0; child < GRAPH_N; child++) {
            if (edges[owner][child] && !reachable[child]) {
                reachable[child] = 1;
                queue[end++] = child;
            }
        }
    }
    CHECK(hyperalloc_flow_allocation_count() == (uint64_t)end * 2);
    CHECK(hyperalloc_flow_bond_live_count() == (uint64_t)end);
    for (int i = 0; i < GRAPH_N; i++) {
        if (reachable[i]) ((uint8_t *)nodes[i])[0] = 42;
    }
    return 0;
}

static int graph_reachability(void) {
    /* An independent reachability oracle checks both leaks and premature frees
       after external releases, retain, and changes to the ownership graph. */
    for (uint32_t trial = 1; trial <= 12; trial++) {
        hyperalloc_flow_init();
        uint32_t seed = trial;
        void *nodes[GRAPH_N];
        uint8_t edges[GRAPH_N][GRAPH_N] = {{0}};
        int refs[GRAPH_N];
        int order[GRAPH_N];
        for (int i = 0; i < GRAPH_N; i++) {
            nodes[i] = hyperalloc_flow_bond_alloc(8);
            hyperalloc_flow_root_adopt(nodes[i], hyperalloc_flow_alloc(8));
            refs[i] = 1;
            order[i] = i;
        }
        for (int i = 0; i < GRAPH_N; i++) {
            for (int degree = 0; degree < 3; degree++) {
                int child = (int)(graph_random(&seed) % GRAPH_N);
                if (child != i) {
                    hyperalloc_flow_root_adopt(nodes[i], nodes[child]);
                    edges[i][child]++;
                }
            }
        }
        for (int i = GRAPH_N - 1; i > 0; i--) {
            int other = (int)(graph_random(&seed) % (uint32_t)(i + 1));
            int previous = order[i];
            order[i] = order[other];
            order[other] = previous;
        }
        int retained = order[GRAPH_N - 1];
        for (int step = 0; step < GRAPH_N; step++) {
            if (step == 1) {
                hyperalloc_flow_bond_retain(nodes[retained]);
                refs[retained]++;
            }
            if (step % 11 == 5 && step + 1 < GRAPH_N) {
                int owner = order[step];
                int child = order[step + 1];
                hyperalloc_flow_root_adopt(nodes[owner], nodes[child]);
                edges[owner][child]++;
                CHECK(check_graph(nodes, edges, refs) == 0);
                hyperalloc_flow_root_replace(nodes[owner], nodes[child], NULL);
                edges[owner][child]--;
                CHECK(check_graph(nodes, edges, refs) == 0);
            }
            int node = order[step];
            hyperalloc_flow_bond_release(nodes[node]);
            refs[node]--;
            CHECK(check_graph(nodes, edges, refs) == 0);
        }
        hyperalloc_flow_bond_release(nodes[retained]);
        refs[retained]--;
        CHECK(check_graph(nodes, edges, refs) == 0);
        CHECK(hyperalloc_flow_invalid_release_count() == 0);
        hyperalloc_flow_shutdown();
    }
    return 0;
}

int main(void) {
    CHECK(original_regressions() == 0);
    CHECK(promotion_lifetimes() == 0);
    CHECK(mixed_cycles() == 0);
    CHECK(cached_components() == 0);
    CHECK(debug_object() == 0);
    CHECK(graph_reachability() == 0);
    puts("flow-bond-cycle-ok");
    return 0;
}
