/* Flow allocator and deep-ownership regressions. The single-TU include gives
   access to region statistics; every check also holds in malloc payload mode
   (HYPERALLOC_FLOW_MALLOC=1, the sanitizer default). */
#include "../../runtime/src/hyperalloc_flow.c"
#include <assert.h>
#include <time.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: %s\n", __func__, __LINE__, #condition); \
        exit(1); \
    } \
} while (0)

static double now_seconds(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return (double) value.tv_sec + (double) value.tv_nsec / 1e9;
}

static uint64_t live_slots(unsigned int size_class) {
    uint64_t live = 0;
    hyperalloc_flow_lock();
    for (uint32_t page = hyperalloc_flow_region.first_page; page < hyperalloc_flow_region.next_fresh_page; page++) {
        if (hyperalloc_flow_region.pages[page].size_class == size_class) {
            live += hyperalloc_flow_region.pages[page].live;
        }
    }
    hyperalloc_flow_unlock();
    return live;
}

/* Builds head -> ... -> tail by tail appends, the shape compiled code emits
   for `tail.next = node; tail = node`. Release used to recurse per level and
   adoption walked the whole chain per append. */
static void deep_root_chain(int release_kind) {
    enum { N = 1000000 };
    hyperalloc_flow_init();
    void *head = hyperalloc_flow_alloc(16);
    void *tail = head;
    for (int i = 1; i < N; i++) {
        void *node = hyperalloc_flow_alloc(16);
        hyperalloc_flow_root_replace(tail, NULL, node);
        tail = node;
    }
    CHECK(hyperalloc_flow_allocation_count() == N);
    if (release_kind == 0) {
        hyperalloc_flow_root_release(head);
    } else {
        /* A stack owner leaving scope releases the same chain. */
        uint64_t owner[2] = {0, 0};
        hyperalloc_flow_owner_enter(owner);
        hyperalloc_flow_root_adopt(owner, head);
        hyperalloc_flow_owner_leave(owner);
    }
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_allocated_bytes() == 0);
    CHECK(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
}

/* A chain of Bond nodes that each hold the next by a counted edge releases
   through the Bond cascade instead of the Root tree. */
static void deep_bond_cascade(void) {
    enum { N = 300000 };
    hyperalloc_flow_init();
    void *head = hyperalloc_flow_bond_alloc(8);
    void *previous = head;
    for (int i = 1; i < N; i++) {
        void *node = hyperalloc_flow_bond_alloc(8);
        hyperalloc_flow_root_adopt(previous, node);
        hyperalloc_flow_bond_release(node); /* Only the edge keeps it alive. */
        previous = node;
    }
    CHECK(hyperalloc_flow_allocation_count() == N);
    hyperalloc_flow_bond_release(head);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_bond_live_count() == 0);
    hyperalloc_flow_shutdown();
}

/* Cycle victims own a deep Root chain: collection must not recurse either. */
static void deep_chain_under_cycle(void) {
    enum { N = 300000 };
    hyperalloc_flow_init();
    void *a = hyperalloc_flow_bond_alloc(8);
    void *b = hyperalloc_flow_bond_alloc(8);
    hyperalloc_flow_root_adopt(a, b);
    hyperalloc_flow_root_adopt(b, a);
    void *tail = a;
    for (int i = 0; i < N; i++) {
        void *node = hyperalloc_flow_alloc(8);
        hyperalloc_flow_root_adopt(tail, node);
        tail = node;
    }
    hyperalloc_flow_bond_release(a);
    CHECK(hyperalloc_flow_allocation_count() == N + 2);
    hyperalloc_flow_bond_release(b);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_bond_cycle_collected_count() == N + 2);
    hyperalloc_flow_shutdown();
}

/* Tail appends must be linear: 4x the nodes may not take ~16x the time. */
static void linear_tail_appends(void) {
    double elapsed[2];
    int sizes[2] = {50000, 200000};
    for (int run = 0; run < 2; run++) {
        hyperalloc_flow_init();
        double start = now_seconds();
        void *head = hyperalloc_flow_alloc(16);
        void *tail = head;
        for (int i = 1; i < sizes[run]; i++) {
            void *node = hyperalloc_flow_alloc(16);
            hyperalloc_flow_root_replace(tail, NULL, node);
            tail = node;
        }
        /* Non-leaf adoption below a deep owner uses the cached tree top. */
        for (int i = 0; i < 1000; i++) {
            void *subtree = hyperalloc_flow_alloc(16);
            hyperalloc_flow_root_adopt(subtree, hyperalloc_flow_alloc(16));
            hyperalloc_flow_root_adopt(tail, subtree);
        }
        elapsed[run] = now_seconds() - start;
        hyperalloc_flow_root_release(head);
        CHECK(hyperalloc_flow_allocation_count() == 0);
        hyperalloc_flow_shutdown();
    }
    fprintf(stderr, "tail appends: 50k %.3fs, 200k %.3fs\n", elapsed[0], elapsed[1]);
    CHECK(elapsed[1] < elapsed[0] * 10 + 0.05);
}

/* Releasing temporary Bond references held by owners deep inside a Root
   chain asks whether each owner is rooted; that must not walk the chain. */
static void rooted_owner_checks(void) {
    enum { N = 100000 };
    hyperalloc_flow_init();
    void *shared = hyperalloc_flow_bond_alloc(16);
    hyperalloc_flow_root_adopt(shared, hyperalloc_flow_alloc(8)); /* Not a leaf. */
    void *head = hyperalloc_flow_alloc(16);
    void *tail = head;
    for (int i = 1; i < N; i++) {
        void *node = hyperalloc_flow_alloc(16);
        hyperalloc_flow_root_adopt(tail, node);
        tail = node;
        if (i % 64 == 0) {
            hyperalloc_flow_root_adopt(node, shared);
        }
    }
    hyperalloc_flow_bond_release(shared); /* Only the counted edges remain. */
    double start = now_seconds();
    for (int i = 0; i < 20000; i++) {
        hyperalloc_flow_bond_retain(shared);
        hyperalloc_flow_bond_release(shared);
    }
    double elapsed = now_seconds() - start;
    fprintf(stderr, "rooted owner checks: %.3fs\n", elapsed);
    CHECK(elapsed < 2.0);
    CHECK(hyperalloc_flow_allocation_count() == N + 2);
    hyperalloc_flow_root_release(head);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_bond_live_count() == 0);
    hyperalloc_flow_shutdown();
}

/* A cycle scan over many Root children must not leave an extension behind
   on each visited node. */
static void scan_without_extensions(void) {
    enum { N = 50000 };
    hyperalloc_flow_init();
    void *bond = hyperalloc_flow_bond_alloc(8);
    void *b2 = hyperalloc_flow_bond_alloc(8);
    void *b3 = hyperalloc_flow_bond_alloc(8);
    for (int i = 0; i < N; i++) {
        hyperalloc_flow_root_adopt(bond, hyperalloc_flow_alloc(8));
    }
    /* bond -> b2 -> b3 -> bond; only b2 keeps a scope reference. */
    hyperalloc_flow_root_adopt(bond, b2);
    hyperalloc_flow_root_adopt(b2, b3);
    hyperalloc_flow_root_adopt(b3, bond);
    hyperalloc_flow_bond_release(b3);
    uint64_t scans = hyperalloc_flow_bond_cycle_scan_count();
    hyperalloc_flow_bond_release(bond); /* Scans the whole closure, no victims. */
    CHECK(hyperalloc_flow_bond_cycle_scan_count() > scans);
    CHECK(hyperalloc_flow_allocation_count() == N + 3);
    if (hyperalloc_flow_region.base != NULL) {
        CHECK(live_slots(HYPERALLOC_FLOW_CLASS_EXTENSION) <= 3);
    }
    hyperalloc_flow_bond_release(b2);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    CHECK(hyperalloc_flow_bond_live_count() == 0);
    if (hyperalloc_flow_region.base != NULL) {
        CHECK(live_slots(HYPERALLOC_FLOW_CLASS_EXTENSION) == 0);
    }
    hyperalloc_flow_shutdown();
}

static uint32_t next_random(uint32_t *seed) {
    *seed = *seed * 1664525u + 1013904223u;
    return *seed >> 8;
}

enum { ORACLE_N = 2048 };

typedef struct OracleNode {
    uint8_t *memory;
    uint64_t size;
    int parent;   /* Root owner index or -1 */
    int scope;    /* the test still holds the Root reference */
    uint8_t pattern;
} OracleNode;

static OracleNode oracle[ORACLE_N];

static int oracle_is_ancestor(int ancestor, int node) {
    for (int current = node; current >= 0; current = oracle[current].parent) {
        if (current == ancestor) return 1;
    }
    return 0;
}

static void oracle_release(int index) {
    /* Freeing a node frees its whole Root subtree. */
    for (int i = 0; i < ORACLE_N; i++) {
        if (oracle[i].memory != NULL && i != index && oracle_is_ancestor(index, i)) {
            oracle[i].memory = NULL;
        }
    }
    oracle[index].memory = NULL;
}

static uint64_t random_size(uint32_t *seed) {
    uint32_t kind = next_random(seed) % 16;
    if (kind == 0) return 0;
    if (kind < 10) return 1 + next_random(seed) % 64;
    if (kind < 15) return 65 + next_random(seed) % 1100;
    return 1024 + next_random(seed) % 9000;
}

/* Random allocation, adoption, replacement and release against an oracle of
   the Root forest; payload patterns catch slot reuse or overlap. */
static void random_oracle(void) {
    for (uint32_t trial = 1; trial <= 6; trial++) {
        hyperalloc_flow_init();
        memset(oracle, 0, sizeof(oracle));
        uint32_t seed = trial * 7919u;
        uint64_t live = 0;
        uint64_t bytes = 0;
        for (int step = 0; step < 60000; step++) {
            int index = (int) (next_random(&seed) % ORACLE_N);
            OracleNode *node = &oracle[index];
            uint32_t action = next_random(&seed) % 8;
            if (node->memory == NULL) {
                uint64_t size = random_size(&seed);
                node->memory = (uint8_t *) hyperalloc_flow_alloc(size);
                node->size = size == 0 ? 8 : size;
                for (uint64_t i = 0; i < node->size; i++) CHECK(node->memory[i] == 0);
                CHECK(((uintptr_t) node->memory & 15) == 0);
                node->pattern = (uint8_t) (next_random(&seed) | 1);
                memset(node->memory, node->pattern, (size_t) node->size);
                node->parent = -1;
                node->scope = 1;
                if (next_random(&seed) % 3 == 0) {
                    emerald_object_set_class(node->memory, (int32_t) (index + 1));
                }
                continue;
            }
            int other = (int) (next_random(&seed) % ORACLE_N);
            OracleNode *target = &oracle[other];
            if (action < 3 && target->memory != NULL && other != index && target->scope && target->parent < 0 &&
                !oracle_is_ancestor(other, index)) {
                /* index adopts other: a scope-held unowned Root moves under it. */
                hyperalloc_flow_root_adopt(node->memory, target->memory);
                target->parent = index;
                target->scope = 0;
            } else if (action == 3 && target->memory != NULL && target->parent == index) {
                hyperalloc_flow_root_replace(node->memory, target->memory, NULL);
                oracle_release(other);
            } else if (action == 4 && target->memory != NULL && target->parent == index) {
                hyperalloc_flow_root_detach(node->memory, target->memory);
                target->parent = -1;
                target->scope = 1;
            } else if (action >= 5 && node->scope && node->parent < 0) {
                hyperalloc_flow_root_release(node->memory);
                oracle_release(index);
            }
        }
        live = 0;
        bytes = 0;
        for (int i = 0; i < ORACLE_N; i++) {
            if (oracle[i].memory == NULL) continue;
            live += 1;
            bytes += oracle[i].size;
            for (uint64_t b = 0; b < oracle[i].size; b++) CHECK(oracle[i].memory[b] == oracle[i].pattern);
        }
        CHECK(hyperalloc_flow_allocation_count() == live);
        CHECK(hyperalloc_flow_allocated_bytes() == bytes);
        CHECK(hyperalloc_flow_invalid_release_count() == 0);
        for (int i = 0; i < ORACLE_N; i++) {
            if (oracle[i].memory != NULL && oracle[i].scope && oracle[i].parent < 0) {
                hyperalloc_flow_root_release(oracle[i].memory);
                oracle_release(i);
            }
        }
        CHECK(hyperalloc_flow_allocation_count() == 0);
        hyperalloc_flow_shutdown();
    }
}

/* Interior, stack and static pointers are never mistaken for Flow blocks. */
static void pointer_identity(void) {
    hyperalloc_flow_init();
    uint8_t *small = hyperalloc_flow_alloc(64);
    uint8_t *large = hyperalloc_flow_alloc(5000);
    uint64_t stack_object[4] = {0};

    emerald_object_set_class(small, 7);
    emerald_object_set_class(large, 8);
    emerald_object_set_class(stack_object, 9);
    CHECK(emerald_object_class(small) == 7);
    CHECK(emerald_object_class(large) == 8);
    CHECK(emerald_object_class(stack_object) == 9);
    CHECK(emerald_object_class(small + 16) == 0);
    CHECK(emerald_object_class(small - 16) == 0);

    /* An interior pointer becomes its own unmanaged owner. */
    hyperalloc_flow_owner_enter(small + 16);
    void *child = hyperalloc_flow_alloc(8);
    hyperalloc_flow_root_adopt(small + 16, child);
    hyperalloc_flow_owner_leave(small + 16);
    CHECK(hyperalloc_flow_allocation_count() == 2);

    hyperalloc_flow_root_release(small + 16);
    CHECK(hyperalloc_flow_invalid_release_count() == 1);

    /* Interned literals are recognised in O(1) and never freed. */
    EmeraldString *literal = emerald_static_string_from_cstr("flow allocator literal");
    for (int i = 0; i < 4096; i++) {
        char text[32];
        snprintf(text, sizeof(text), "literal-%d", i);
        emerald_static_string_from_cstr(text);
    }
    hyperalloc_flow_root_release(literal);
    CHECK(hyperalloc_flow_invalid_release_count() == 1);
    CHECK(emerald_static_string_from_cstr("flow allocator literal") == literal);

    hyperalloc_flow_owner_leave(stack_object);
    hyperalloc_flow_root_release(small);
    hyperalloc_flow_root_release(large);
    CHECK(emerald_object_class(stack_object) == 0);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    hyperalloc_flow_shutdown();
}

/* Empty pages return to a pool; beyond a small cache their memory goes back
   to the OS, and later allocations reuse the pooled pages. */
static void pages_return(void) {
    enum { N = 400000 };
    hyperalloc_flow_init();
    void *owner = hyperalloc_flow_alloc(8);
    for (int i = 0; i < N; i++) {
        hyperalloc_flow_root_adopt(owner, hyperalloc_flow_alloc(16));
    }
    if (hyperalloc_flow_region.base == NULL || hyperalloc_flow_malloc_payloads()) {
        hyperalloc_flow_root_release(owner);
        hyperalloc_flow_shutdown();
        return;
    }
    uint32_t used = hyperalloc_flow_region.next_fresh_page;
    hyperalloc_flow_root_release(owner);
    CHECK(hyperalloc_flow_region.dirty_pooled_pages <= HYPERALLOC_FLOW_DIRTY_PAGE_LIMIT);
    CHECK(live_slots(HYPERALLOC_FLOW_CLASS_FIRST_INLINE) == 0);
    owner = hyperalloc_flow_alloc(8);
    for (int i = 0; i < N; i++) {
        hyperalloc_flow_root_adopt(owner, hyperalloc_flow_alloc(16));
    }
    CHECK(hyperalloc_flow_region.next_fresh_page == used);
    hyperalloc_flow_root_release(owner);
    CHECK(hyperalloc_flow_allocation_count() == 0);
    hyperalloc_flow_shutdown();
}

int main(void) {
    deep_root_chain(0);
    deep_root_chain(1);
    deep_bond_cascade();
    deep_chain_under_cycle();
    linear_tail_appends();
    rooted_owner_checks();
    scan_without_extensions();
    random_oracle();
    pointer_identity();
    pages_return();
    printf("Flow allocator: header=%zu external=%zu extension=%zu payload-mode=%s\n",
        sizeof(HyperAllocFlowBlock), sizeof(HyperAllocFlowExternal), sizeof(HyperAllocFlowExtended),
        hyperalloc_flow_malloc_payloads() ? "malloc" : "slots");
    puts("flow-allocator-ok");
    return 0;
}
