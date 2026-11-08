#if !defined(_WIN32)
#include <sched.h>
#include <sys/mman.h>
#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif
#if !defined(MAP_ANONYMOUS) && defined(__APPLE__)
#define MAP_ANONYMOUS 0x1000
#endif
#if !defined(MAP_ANONYMOUS) && defined(__linux__)
#define MAP_ANONYMOUS 0x20
#endif
#if defined(__linux__) && !defined(MADV_DONTNEED)
/* Strict POSIX mode hides madvise; glibc still exports it. Only Linux
   guarantees that discarded private anonymous pages read back as zero. */
extern int madvise(void *address, size_t length, int advice);
#define MADV_DONTNEED 4
#endif
#if defined(__linux__) && !defined(MADV_NOHUGEPAGE)
#define MADV_NOHUGEPAGE 15
#endif
#endif

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define EMERALD_FLOW_SANITIZED 1
#endif
#endif
#if !defined(EMERALD_FLOW_SANITIZED) && defined(__SANITIZE_ADDRESS__)
#define EMERALD_FLOW_SANITIZED 1
#endif
#ifndef EMERALD_FLOW_SANITIZED
#define EMERALD_FLOW_SANITIZED 0
#endif
#if EMERALD_FLOW_SANITIZED
#include <sanitizer/lsan_interface.h>
#endif

#if defined(__GNUC__) || defined(__clang__)
#define EMERALD_FLOW_LIKELY(condition) __builtin_expect(!!(condition), 1)
#define EMERALD_FLOW_UNLIKELY(condition) __builtin_expect(!!(condition), 0)
#else
#define EMERALD_FLOW_LIKELY(condition) (condition)
#define EMERALD_FLOW_UNLIKELY(condition) (condition)
#endif

typedef struct EmeraldFlowBondEdge EmeraldFlowBondEdge;

typedef struct EmeraldFlowCycleComponent {
    struct EmeraldFlowCycleComponent *next;
    struct EmeraldFlowCycleComponent *previous;
    uint64_t graph_revision;
    uint64_t member_count;
    uint64_t external_count;
} EmeraldFlowCycleComponent;

/* Root allocations carry only their unique ownership tree. Bond/cycle data
   is allocated lazily; cycle scans keep their marks in the header instead. */
typedef struct EmeraldFlowExtended {
    uint64_t bond_count;
    EmeraldFlowBondEdge *first_bond_out;
    EmeraldFlowBondEdge *first_bond_in;
    EmeraldFlowCycleComponent *cycle_component;
    uint32_t cycle_candidate_next;
    uint32_t reserved;
} EmeraldFlowExtended;

/* Every Flow header lives in one reserved address region and refers to other
   headers by 32-bit indices in 16-byte units (index 0 is NULL). Small managed
   payloads follow their header in a size-class slot; large, sanitizer-mode and
   unmanaged blocks use an EmeraldFlowExternal header that points elsewhere. */
typedef struct EmeraldFlowBlock {
    uint32_t parent;
    uint32_t first_child;
    /* Also links pending, release and free lists once a block is detached.
       Children form a singly linked list; removing a child walks from the
       first child, which is O(1) for the newest child. */
    uint32_t next_sibling;
    /* Low EMERALD_FLOW_FLAG_BITS bits: flags. Upper bits: class tag. Flags
       change under the chamber lock; the tag is written once after
       construction and read without it (plain relaxed load/store, no RMW). */
    _Atomic uint32_t meta;
} EmeraldFlowBlock;

typedef struct EmeraldFlowExternal {
    EmeraldFlowBlock block;
    void *memory;
    uint64_t size;
    uint32_t hash_next;
    uint32_t hash_previous;
    uint64_t reserved;
} EmeraldFlowExternal;

#define EMERALD_FLOW_FLAG_BITS 11
#define EMERALD_FLOW_FLAG_MASK ((1u << EMERALD_FLOW_FLAG_BITS) - 1u)
#define EMERALD_FLOW_TAG_LIMIT ((uint32_t) 1 << (32 - EMERALD_FLOW_FLAG_BITS))

#define EMERALD_FLOW_LIVE 0x0001u
#define EMERALD_FLOW_MANAGED 0x0002u
#define EMERALD_FLOW_EXTERNAL 0x0004u
#define EMERALD_FLOW_ATOMIC 0x0008u
#define EMERALD_FLOW_SHARED 0x0010u
#define EMERALD_FLOW_BONDED 0x0020u
#define EMERALD_FLOW_CANDIDATE_QUEUED 0x0040u
#define EMERALD_FLOW_COLLECTING 0x0080u
#define EMERALD_FLOW_SCAN_MARKED 0x0100u
/* The block owns an entry in the extension table. */
#define EMERALD_FLOW_EXTENDED 0x0200u
/* Inline block: the last payload byte of the slot holds capacity - size. */
#define EMERALD_FLOW_SLACK 0x0400u

#define EMERALD_FLOW_HAS(block, flag) ((atomic_load_explicit(&(block)->meta, memory_order_relaxed) & (flag)) != 0)
#define EMERALD_FLOW_SET(block, flag) \
    atomic_store_explicit(&(block)->meta, atomic_load_explicit(&(block)->meta, memory_order_relaxed) | (flag), memory_order_relaxed)
#define EMERALD_FLOW_CLEAR(block, flag) \
    atomic_store_explicit(&(block)->meta, atomic_load_explicit(&(block)->meta, memory_order_relaxed) & ~(uint32_t) (flag), memory_order_relaxed)
#define EMERALD_FLOW_TAG(block) (atomic_load_explicit(&(block)->meta, memory_order_relaxed) >> EMERALD_FLOW_FLAG_BITS)
#define EMERALD_FLOW_SET_TAG(block, tag) \
    atomic_store_explicit(&(block)->meta, \
        (atomic_load_explicit(&(block)->meta, memory_order_relaxed) & EMERALD_FLOW_FLAG_MASK) | ((uint32_t) (tag) << EMERALD_FLOW_FLAG_BITS), \
        memory_order_relaxed)

_Static_assert(sizeof(EmeraldFlowBlock) == 16, "Flow header size");
_Static_assert(sizeof(EmeraldFlowBlock) % 16 == 0, "Flow payload alignment");
_Static_assert(sizeof(EmeraldFlowExternal) == 48, "Flow external header size");
_Static_assert(sizeof(EmeraldFlowExtended) <= 48, "Flow extension size");

struct EmeraldFlowBondEdge {
    struct EmeraldFlowBondEdge *owner_next;
    struct EmeraldFlowBondEdge *owner_previous;
    struct EmeraldFlowBondEdge *child_next;
    struct EmeraldFlowBondEdge *child_previous;
    EmeraldFlowBlock *owner;
    EmeraldFlowBlock *child;
};

typedef struct EmeraldFlowPoolSlot {
    struct EmeraldFlowPoolSlot *next;
    uint64_t site_id;
    uint64_t size;
    void *memory;
} EmeraldFlowPoolSlot;

typedef struct EmeraldFlowShardChunk {
    struct EmeraldFlowShardChunk *next;
    uint64_t capacity;
    uint64_t used;
    uint8_t memory[];
} EmeraldFlowShardChunk;

typedef struct EmeraldFlowShardOwner {
    struct EmeraldFlowShardOwner *next;
    void *memory;
} EmeraldFlowShardOwner;

typedef struct EmeraldFlowShardFrame {
    EmeraldFlowShardChunk *first;
    EmeraldFlowShardChunk *current;
    EmeraldFlowShardOwner *owners;
} EmeraldFlowShardFrame;

typedef struct EmeraldStaticStringNode {
    struct EmeraldStaticStringNode *next;
    struct EmeraldStaticStringNode *bucket_next;
    struct EmeraldStaticStringNode *address_next;
    EmeraldString value;
    uint8_t bytes[];
} EmeraldStaticStringNode;

/* ---------------------------------------------------------------------------
   Region allocator. The region is reserved once and committed on demand; it
   is split into 64 KiB pages and each page serves one slot size. Page
   metadata sits at the start of the region, so any address inside the
   reservation maps to its page in O(1). Released slots go to per-page free
   lists, empty pages are pooled and returned to the OS beyond a small cache.
   ------------------------------------------------------------------------- */
#define EMERALD_FLOW_PAGE_SHIFT 16
#define EMERALD_FLOW_PAGE_SIZE ((uint64_t) 1 << EMERALD_FLOW_PAGE_SHIFT)
#define EMERALD_FLOW_INLINE_LIMIT 1024
#define EMERALD_FLOW_COMMIT_CHUNK ((uint64_t) 4 << 20)
#define EMERALD_FLOW_DIRTY_PAGE_LIMIT 64
#define EMERALD_FLOW_SMALL_HEAP_BYTES ((uint64_t) 4 << 20)
#define EMERALD_FLOW_EXTERNAL_BUCKET_COUNT 65536
#define EMERALD_STATIC_STRING_BUCKET_COUNT 16384

enum {
    EMERALD_FLOW_CLASS_NONE = 0,
    EMERALD_FLOW_CLASS_EXTERNAL = 1,
    EMERALD_FLOW_CLASS_EXTENSION = 2,
    EMERALD_FLOW_CLASS_FIRST_INLINE = 3,
    EMERALD_FLOW_CLASS_COUNT = 27
};

#define EMERALD_FLOW_RECIPROCAL(stride) ((uint32_t) ((((uint64_t) 1 << 32) + (stride) - 1) / (stride)))
#define EMERALD_FLOW_INLINE_STRIDES(X) \
    X(32) X(48) X(64) X(80) X(96) X(112) X(128) X(144) X(160) X(176) X(192) X(208) \
    X(224) X(240) X(256) X(272) X(336) X(400) X(464) X(528) X(656) X(784) X(912) X(1040)
#define EMERALD_FLOW_STRIDE_ENTRY(stride) stride,
#define EMERALD_FLOW_RECIPROCAL_ENTRY(stride) EMERALD_FLOW_RECIPROCAL(stride),

/* Slot sizes include the 16-byte header; inline payload capacities are 16..1024. */
static const uint16_t emerald_flow_class_stride[EMERALD_FLOW_CLASS_COUNT] = {
    0, sizeof(EmeraldFlowExternal), 48, EMERALD_FLOW_INLINE_STRIDES(EMERALD_FLOW_STRIDE_ENTRY)
};
static const uint32_t emerald_flow_class_reciprocal[EMERALD_FLOW_CLASS_COUNT] = {
    0, EMERALD_FLOW_RECIPROCAL(48), EMERALD_FLOW_RECIPROCAL(48), EMERALD_FLOW_INLINE_STRIDES(EMERALD_FLOW_RECIPROCAL_ENTRY)
};

enum {
    EMERALD_FLOW_PAGE_UNUSED = 0,
    EMERALD_FLOW_PAGE_PARTIAL,
    EMERALD_FLOW_PAGE_FULL,
    EMERALD_FLOW_PAGE_POOLED
};

typedef struct EmeraldFlowPage {
    uint32_t free_slot;
    uint32_t bump;
    uint32_t next;
    uint32_t previous;
    uint16_t live;
    uint8_t size_class;
    uint8_t state;
    uint32_t dirty;
} EmeraldFlowPage;

typedef struct EmeraldFlowRegion {
    uint8_t *base;
    EmeraldFlowPage *pages;
    uint64_t reserved_bytes;
    uint64_t committed_bytes;
    uint32_t page_count;
    uint32_t first_page;
    uint32_t next_fresh_page;
    uint32_t pooled_pages;
    uint32_t dirty_pooled_pages;
    uint32_t partial[EMERALD_FLOW_CLASS_COUNT];
} EmeraldFlowRegion;

typedef struct EmeraldFlowChamber {
    EmeraldFlowBlock *bond_cycle_candidates;
    EmeraldFlowCycleComponent *cycle_components;
    uint64_t cycle_graph_revision;
    uint64_t ancestry_revision;
    uint32_t release_pending;
    int release_draining;
    uint64_t allocation_count;
    uint64_t allocated_bytes;
    uint64_t peak_allocation_count;
    uint64_t peak_allocated_bytes;
    uint64_t invalid_release_count;
    uint64_t root_release_count;
    uint64_t root_released_bytes;
    uint64_t root_adoption_count;
    uint64_t root_shared_fallback_count;
    uint64_t bond_allocation_count;
    uint64_t bond_promotion_count;
    uint64_t bond_retain_count;
    uint64_t bond_release_count;
    uint64_t bond_live_count;
    uint64_t bond_cycle_scan_count;
    uint64_t bond_cycle_collection_count;
    uint64_t bond_cycle_collected_count;
    uint64_t bond_cycle_collected_bytes;
    uint64_t debug_allocation_calls;
    /* Diagnostic counters updated outside ownership transactions. */
    _Atomic uint64_t container_owned_adoption_count;
    _Atomic uint64_t container_owned_release_count;
    _Atomic uint64_t container_inline_copy_count;
    _Atomic uint64_t pool_slot_count;
    _Atomic uint64_t pool_reuse_count;
    _Atomic uint64_t shard_chunk_count;
    _Atomic uint64_t shard_reuse_count;
    _Atomic uint64_t shard_reset_count;
    int active;
} EmeraldFlowChamber;

#if defined(_MSC_VER)
#define EMERALD_THREAD_LOCAL __declspec(thread)
#else
#define EMERALD_THREAD_LOCAL _Thread_local
#endif

#define EMERALD_FLOW_SHARD_MAX_DEPTH 64
#define EMERALD_FLOW_SHARD_DEFAULT_CHUNK 4096
#define EMERALD_FLOW_ALIGNMENT 16

static EmeraldFlowChamber emerald_flow_default_chamber = {0};
static EmeraldFlowRegion emerald_flow_region = {0};
/* Region base for lock-free readers; published after the metadata exists. */
static _Atomic uintptr_t emerald_flow_region_published = 0;
static uint32_t emerald_flow_external_buckets[EMERALD_FLOW_EXTERNAL_BUCKET_COUNT] = {0};
static EMERALD_THREAD_LOCAL EmeraldFlowPoolSlot *emerald_flow_pool_slots = NULL;
static EMERALD_THREAD_LOCAL EmeraldFlowShardFrame emerald_flow_shard_frames[EMERALD_FLOW_SHARD_MAX_DEPTH];
static EMERALD_THREAD_LOCAL EmeraldFlowShardChunk *emerald_flow_shard_free_chunks = NULL;
static EMERALD_THREAD_LOCAL uint64_t emerald_flow_shard_depth = 0;
static atomic_int emerald_flow_lock_word = 0;
static EmeraldStaticStringNode *emerald_static_strings = NULL;
/* Module-constant String objects have no Flow header. Only their addresses
   are registered once so ownership diagnostics distinguish them from UAFs. */
static EmeraldString **emerald_static_literal_addresses;
static uint64_t emerald_static_literal_count;
static EmeraldStaticStringNode *emerald_static_string_buckets[EMERALD_STATIC_STRING_BUCKET_COUNT] = {0};
static EmeraldStaticStringNode *emerald_static_string_address_buckets[EMERALD_STATIC_STRING_BUCKET_COUNT] = {0};

static uint64_t emerald_static_string_hash(const char *text, uint64_t length) {
    uint64_t hash = 14695981039346656037ULL;
    uint64_t i = 0;

    while (i < length) {
        hash ^= (uint64_t) (uint8_t) text[i];
        hash *= 1099511628211ULL;
        i += 1;
    }

    return hash;
}

static void emerald_flow_cpu_relax(void) {
#if (defined(__GNUC__) || defined(__clang__)) && (defined(__x86_64__) || defined(__i386__))
    __builtin_ia32_pause();
#elif (defined(__GNUC__) || defined(__clang__)) && (defined(__aarch64__) || defined(__arm__))
    __asm__ __volatile__("yield");
#elif defined(_MSC_VER)
    YieldProcessor();
#endif
}

static void emerald_flow_yield(void) {
#if defined(_WIN32)
    SwitchToThread();
#else
    sched_yield();
#endif
}

static void emerald_flow_lock_contended(void) {
    unsigned int spins = 0;

    for (;;) {
        while (atomic_load_explicit(&emerald_flow_lock_word, memory_order_relaxed) != 0) {
            /* Spin briefly with a CPU hint, then let the holder run. */
            if (spins < 128) {
                emerald_flow_cpu_relax();
                spins += 1;
            } else {
                emerald_flow_yield();
            }
        }

        if (atomic_exchange_explicit(&emerald_flow_lock_word, 1, memory_order_acquire) == 0) {
            return;
        }
    }
}

static void emerald_flow_lock(void) {
    if (EMERALD_FLOW_LIKELY(atomic_exchange_explicit(&emerald_flow_lock_word, 1, memory_order_acquire) == 0)) {
        return;
    }

    emerald_flow_lock_contended();
}

static void emerald_flow_unlock(void) {
    atomic_store_explicit(&emerald_flow_lock_word, 0, memory_order_release);
}

void emerald_flow_fail(uint64_t size) {
    fprintf(stderr, "Emerald Flow allocation failed (%llu bytes)\n", (unsigned long long) size);
    fflush(stdout);
    abort();
}

static int emerald_flow_env_flag(const char *name) {
    const char *value = getenv(name);
    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static int emerald_flow_debug_enabled(void) {
    static int cached = -1;

    if (cached < 0) {
        cached = emerald_flow_env_flag("EMERALD_FLOW_DEBUG");
    }

    return cached;
}

/* Compatibility mode for historical compiler snapshots: keep every released
   allocation alive and disable Pool and Shard storage reuse. Current self-host
   builds use normal deterministic releases; enable this only explicitly while
   diagnosing an old ownership failure. */
static int emerald_flow_bootstrap_leak_enabled(void) {
    static int cached = -1;

    if (cached < 0) {
        cached = emerald_flow_env_flag("EMERALD_FLOW_BOOTSTRAP");
    }

    return cached;
}

static int emerald_uaf_enabled(void) {
    static int cached = -1;

    if (cached < 0) {
        cached = emerald_flow_env_flag("EMERALD_FLOW_UAF_HUNT");
    }

    return cached;
}

/* Payloads live next to their headers unless a sanitizer or the use-after-free
   hunt needs one malloc allocation per payload. EMERALD_FLOW_MALLOC=1 forces
   that mode for external memory tools, EMERALD_FLOW_MALLOC=0 forces slots. */
static int emerald_flow_malloc_payloads(void) {
    static int cached = -1;

    if (cached < 0) {
        const char *value = getenv("EMERALD_FLOW_MALLOC");

        if (value != NULL && value[0] != '\0') {
            cached = strcmp(value, "0") != 0;
        } else {
            cached = EMERALD_FLOW_SANITIZED || emerald_uaf_enabled();
        }
    }

    return cached;
}

static void *emerald_flow_os_reserve(uint64_t bytes) {
#if defined(_WIN32)
    return VirtualAlloc(NULL, (SIZE_T) bytes, MEM_RESERVE, PAGE_NOACCESS);
#elif defined(MAP_ANONYMOUS)
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#if defined(MAP_NORESERVE)
    flags |= MAP_NORESERVE;
#endif
    void *memory = mmap(NULL, (size_t) bytes, PROT_NONE, flags, -1, 0);
    return memory == MAP_FAILED ? NULL : memory;
#else
    int descriptor = open("/dev/zero", O_RDWR);
    if (descriptor < 0) {
        return NULL;
    }
    void *memory = mmap(NULL, (size_t) bytes, PROT_NONE, MAP_PRIVATE, descriptor, 0);
    close(descriptor);
    return memory == MAP_FAILED ? NULL : memory;
#endif
}

static int emerald_flow_os_commit(void *memory, uint64_t bytes) {
#if defined(_WIN32)
    return VirtualAlloc(memory, (SIZE_T) bytes, MEM_COMMIT, PAGE_READWRITE) != NULL;
#else
    return mprotect(memory, (size_t) bytes, PROT_READ | PROT_WRITE) == 0;
#endif
}

/* Drops the physical pages; contents are undefined afterwards, which is fine
   because every slot is cleared when it is handed out. */
static void emerald_flow_os_discard(void *memory, uint64_t bytes) {
#if defined(_WIN32)
    VirtualAlloc(memory, (SIZE_T) bytes, MEM_RESET, PAGE_READWRITE);
#elif defined(__linux__)
    madvise(memory, (size_t) bytes, MADV_DONTNEED);
#else
    posix_madvise(memory, (size_t) bytes, POSIX_MADV_DONTNEED);
#endif
}

static void emerald_flow_region_init_locked(void) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    /* 64 GiB is the most that 32-bit indices in 16-byte units can address.
       Smaller reservations keep Flow usable under address-space limits. */
    uint64_t bytes = (uint64_t) 64 << 30;
    uint8_t *base = NULL;

    while (bytes > (uint64_t) (SIZE_MAX >> 1)) {
        bytes /= 2;
    }

    while (base == NULL && bytes >= ((uint64_t) 256 << 20)) {
        base = (uint8_t *) emerald_flow_os_reserve(bytes);
        if (base == NULL) {
            bytes /= 2;
        }
    }

    if (base == NULL) {
        emerald_flow_fail(bytes);
    }

    uint64_t page_count = bytes >> EMERALD_FLOW_PAGE_SHIFT;
    uint64_t metadata = page_count * sizeof(EmeraldFlowPage);
    metadata = (metadata + EMERALD_FLOW_PAGE_SIZE - 1) & ~(EMERALD_FLOW_PAGE_SIZE - 1);

    if (!emerald_flow_os_commit(base, metadata)) {
        emerald_flow_fail(metadata);
    }

#if defined(__linux__)
    /* Page metadata is touched sparsely and small heaps touch few slot pages;
       transparent huge pages would make each of them 2 MiB resident. Larger
       heaps keep huge pages, which roughly halves their page-fault cost. */
    uint64_t small = metadata + EMERALD_FLOW_SMALL_HEAP_BYTES;
    madvise(base, (size_t) (small < bytes ? small : bytes), MADV_NOHUGEPAGE);
#endif

    region->base = base;
    region->pages = (EmeraldFlowPage *) base;
    region->reserved_bytes = bytes;
    region->committed_bytes = metadata;
    region->page_count = (uint32_t) page_count;
    region->first_page = (uint32_t) (metadata >> EMERALD_FLOW_PAGE_SHIFT);
    region->next_fresh_page = region->first_page;
#if EMERALD_FLOW_SANITIZED
    /* Headers hold the only references to malloc payloads and Bond edges. */
    __lsan_register_root_region(base, (size_t) bytes);
#endif
    atomic_store_explicit(&emerald_flow_region_published, (uintptr_t) base, memory_order_release);
}

static EmeraldFlowBlock *emerald_flow_at(uint32_t index) {
    return index == 0 ? NULL : (EmeraldFlowBlock *) (emerald_flow_region.base + ((uint64_t) index << 4));
}

static uint32_t emerald_flow_index(const void *memory) {
    return memory == NULL ? 0 : (uint32_t) (((const uint8_t *) memory - emerald_flow_region.base) >> 4);
}

static uint8_t *emerald_flow_page_address(uint32_t page) {
    return emerald_flow_region.base + ((uint64_t) page << EMERALD_FLOW_PAGE_SHIFT);
}

static void emerald_flow_page_unlink_locked(uint32_t page_number) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    EmeraldFlowPage *page = &region->pages[page_number];

    if (page->previous != 0) {
        region->pages[page->previous].next = page->next;
    } else {
        region->partial[page->size_class] = page->next;
    }

    if (page->next != 0) {
        region->pages[page->next].previous = page->previous;
    }

    page->next = 0;
    page->previous = 0;
}

static void emerald_flow_page_link_partial_locked(uint32_t page_number) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    EmeraldFlowPage *page = &region->pages[page_number];
    uint32_t head = region->partial[page->size_class];

    page->previous = 0;
    page->next = head;
    if (head != 0) {
        region->pages[head].previous = page_number;
    }
    region->partial[page->size_class] = page_number;
    page->state = EMERALD_FLOW_PAGE_PARTIAL;
}

static void emerald_flow_page_take_locked(unsigned int size_class) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    uint32_t page_number = region->pooled_pages;

    if (page_number != 0) {
        region->pooled_pages = region->pages[page_number].next;
        if (region->pages[page_number].dirty) {
            region->dirty_pooled_pages -= 1;
        }
    } else {
        if (region->next_fresh_page >= region->page_count) {
            emerald_flow_fail(region->reserved_bytes);
        }

        page_number = region->next_fresh_page++;
        uint64_t end = (uint64_t) region->next_fresh_page << EMERALD_FLOW_PAGE_SHIFT;

        if (end > region->committed_bytes) {
            uint64_t target = (end + EMERALD_FLOW_COMMIT_CHUNK - 1) & ~(EMERALD_FLOW_COMMIT_CHUNK - 1);
            if (target > region->reserved_bytes) {
                target = region->reserved_bytes;
            }
            if (!emerald_flow_os_commit(region->base + region->committed_bytes, target - region->committed_bytes)) {
                emerald_flow_fail(target - region->committed_bytes);
            }
            region->committed_bytes = target;
        }
    }

    EmeraldFlowPage *page = &region->pages[page_number];
    page->free_slot = 0;
    page->bump = 0;
    page->live = 0;
    page->dirty = 1;
    page->size_class = (uint8_t) size_class;
    emerald_flow_page_link_partial_locked(page_number);
}

/* Returns an uninitialised slot of the given class. */
static void *emerald_flow_slot_take_locked(unsigned int size_class) {
    EmeraldFlowRegion *region = &emerald_flow_region;

    if (EMERALD_FLOW_UNLIKELY(region->base == NULL)) {
        emerald_flow_region_init_locked();
    }

    if (region->partial[size_class] == 0) {
        emerald_flow_page_take_locked(size_class);
    }

    uint32_t page_number = region->partial[size_class];
    EmeraldFlowPage *page = &region->pages[page_number];
    uint32_t stride = emerald_flow_class_stride[size_class];
    uint8_t *slot;

    if (page->free_slot != 0) {
        slot = (uint8_t *) emerald_flow_at(page->free_slot);
        memcpy(&page->free_slot, slot, sizeof(uint32_t));
    } else {
        slot = emerald_flow_page_address(page_number) + page->bump;
        page->bump += stride;
    }

    page->live += 1;

    if (page->free_slot == 0 && page->bump + stride > EMERALD_FLOW_PAGE_SIZE) {
        emerald_flow_page_unlink_locked(page_number);
        page->state = EMERALD_FLOW_PAGE_FULL;
    }

    return slot;
}

static void emerald_flow_slot_give_locked(void *slot) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    uint64_t offset = (uint64_t) ((uint8_t *) slot - region->base);
    uint32_t page_number = (uint32_t) (offset >> EMERALD_FLOW_PAGE_SHIFT);
    EmeraldFlowPage *page = &region->pages[page_number];

    memcpy(slot, &page->free_slot, sizeof(uint32_t));
    page->free_slot = (uint32_t) (offset >> 4);
    page->live -= 1;

    if (page->live == 0) {
        if (page->state == EMERALD_FLOW_PAGE_PARTIAL) {
            emerald_flow_page_unlink_locked(page_number);
        }

        /* Lookups reject pooled pages before reading any slot. */
        page->size_class = EMERALD_FLOW_CLASS_NONE;
        page->free_slot = 0;
        page->bump = 0;
        page->state = EMERALD_FLOW_PAGE_POOLED;

        if (region->dirty_pooled_pages >= EMERALD_FLOW_DIRTY_PAGE_LIMIT) {
            emerald_flow_os_discard(emerald_flow_page_address(page_number), EMERALD_FLOW_PAGE_SIZE);
            page->dirty = 0;
        } else {
            region->dirty_pooled_pages += 1;
        }

        page->next = region->pooled_pages;
        region->pooled_pages = page_number;
    } else if (page->state == EMERALD_FLOW_PAGE_FULL) {
        emerald_flow_page_link_partial_locked(page_number);
    }
}

/* Maps a payload address to its inline header. Only the page class and the
   immutable stride tables are read, both stable while the payload is live, so
   this also serves lock-free callers holding a live object. */
static EmeraldFlowBlock *emerald_flow_inline_slot(uintptr_t base, const void *memory, uint64_t reserved_bytes) {
    uint64_t offset = (uint64_t) ((uintptr_t) memory - base);

    if (offset >= reserved_bytes) {
        return NULL;
    }

    const EmeraldFlowPage *page = &((const EmeraldFlowPage *) base)[offset >> EMERALD_FLOW_PAGE_SHIFT];
    unsigned int size_class = page->size_class;

    if (size_class < EMERALD_FLOW_CLASS_FIRST_INLINE) {
        return NULL;
    }

    uint32_t within = (uint32_t) (offset & (EMERALD_FLOW_PAGE_SIZE - 1));
    if (within < sizeof(EmeraldFlowBlock) || ((within - sizeof(EmeraldFlowBlock)) & 15) != 0) {
        return NULL;
    }

    uint32_t start = within - (uint32_t) sizeof(EmeraldFlowBlock);
    uint32_t slot = (uint32_t) (((uint64_t) start * emerald_flow_class_reciprocal[size_class]) >> 32);

    if (slot * emerald_flow_class_stride[size_class] != start) {
        return NULL;
    }

    return (EmeraldFlowBlock *) ((uint8_t *) memory - sizeof(EmeraldFlowBlock));
}

static EmeraldFlowBlock *emerald_flow_inline_block_locked(const void *memory) {
    EmeraldFlowRegion *region = &emerald_flow_region;
    EmeraldFlowBlock *block = emerald_flow_inline_slot((uintptr_t) region->base, memory, region->reserved_bytes);

    if (block == NULL) {
        return NULL;
    }

    /* Under the lock the slot must also be handed out and still live. */
    uint64_t offset = (uint64_t) ((uint8_t *) block - region->base);
    const EmeraldFlowPage *page = &region->pages[offset >> EMERALD_FLOW_PAGE_SHIFT];

    if ((offset & (EMERALD_FLOW_PAGE_SIZE - 1)) >= page->bump || !EMERALD_FLOW_HAS(block, EMERALD_FLOW_LIVE)) {
        return NULL;
    }

    return block;
}

static EmeraldFlowBlock *emerald_flow_inline_block_unlocked(const void *memory) {
    uintptr_t base = atomic_load_explicit(&emerald_flow_region_published, memory_order_acquire);

    if (base == 0) {
        return NULL;
    }

    return emerald_flow_inline_slot(base, memory, emerald_flow_region.reserved_bytes);
}

/* Open-addressing map from a block index to a 32-bit value (linear probing,
   backward-shift deletion). Key 0 marks an empty entry because index 0 is
   NULL. Used under the chamber lock only. */
typedef struct EmeraldFlowMapEntry {
    uint32_t key;
    uint32_t value;
} EmeraldFlowMapEntry;

typedef struct EmeraldFlowMap {
    EmeraldFlowMapEntry *entries;
    uint32_t mask;
    uint32_t count;
} EmeraldFlowMap;

static inline uint32_t emerald_flow_map_hash(uint32_t key) {
    uint32_t hash = key * 2654435761u;
    return hash ^ (hash >> 15);
}

static uint32_t emerald_flow_map_get(const EmeraldFlowMap *map, uint32_t key) {
    if (map->count == 0) {
        return 0;
    }
    for (uint32_t i = emerald_flow_map_hash(key) & map->mask;; i = (i + 1) & map->mask) {
        if (map->entries[i].key == key) return map->entries[i].value;
        if (map->entries[i].key == 0) return 0;
    }
}

static void emerald_flow_map_put_raw(EmeraldFlowMap *map, uint32_t key, uint32_t value) {
    uint32_t i = emerald_flow_map_hash(key) & map->mask;
    while (map->entries[i].key != 0 && map->entries[i].key != key) {
        i = (i + 1) & map->mask;
    }
    if (map->entries[i].key == 0) map->count += 1;
    map->entries[i].key = key;
    map->entries[i].value = value;
}

static void emerald_flow_map_reserve(EmeraldFlowMap *map, uint64_t wanted) {
    if (map->entries != NULL && wanted * 2 <= (uint64_t) map->mask + 1) {
        return;
    }
    uint64_t capacity = map->entries == NULL ? 64 : (uint64_t) map->mask + 1;
    while (capacity < wanted * 2) capacity *= 2;
    if (capacity > ((uint64_t) 1 << 31)) emerald_flow_fail(capacity * sizeof(EmeraldFlowMapEntry));
    EmeraldFlowMapEntry *entries = (EmeraldFlowMapEntry *) calloc((size_t) capacity, sizeof(*entries));
    if (entries == NULL) emerald_flow_fail(capacity * sizeof(*entries));
    EmeraldFlowMap grown = { entries, (uint32_t) (capacity - 1), 0 };
    if (map->entries != NULL) {
        for (uint64_t i = 0; i <= map->mask; i++) {
            if (map->entries[i].key != 0) emerald_flow_map_put_raw(&grown, map->entries[i].key, map->entries[i].value);
        }
        free(map->entries);
    }
    *map = grown;
}

static void emerald_flow_map_put(EmeraldFlowMap *map, uint32_t key, uint32_t value) {
    emerald_flow_map_reserve(map, (uint64_t) map->count + 1);
    emerald_flow_map_put_raw(map, key, value);
}

static void emerald_flow_map_remove(EmeraldFlowMap *map, uint32_t key) {
    if (map->count == 0) return;
    uint32_t i = emerald_flow_map_hash(key) & map->mask;
    while (map->entries[i].key != key) {
        if (map->entries[i].key == 0) return;
        i = (i + 1) & map->mask;
    }
    for (uint32_t j = i;;) {
        j = (j + 1) & map->mask;
        if (map->entries[j].key == 0) break;
        uint32_t home = emerald_flow_map_hash(map->entries[j].key) & map->mask;
        if (((j - home) & map->mask) >= ((j - i) & map->mask)) {
            map->entries[i] = map->entries[j];
            i = j;
        }
    }
    map->entries[i].key = 0;
    map->count -= 1;
}

static void emerald_flow_map_free(EmeraldFlowMap *map) {
    free(map->entries);
    map->entries = NULL;
    map->mask = 0;
    map->count = 0;
}

/* Block index -> extension slot index. Only blocks with the EXTENDED flag
   have an entry, so plain objects never touch the table. */
static EmeraldFlowMap emerald_flow_extended_map;

static uint64_t emerald_flow_block_size(EmeraldFlowBlock *block) {
    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTERNAL)) {
        return ((EmeraldFlowExternal *) block)->size;
    }
    uint64_t offset = (uint64_t) ((uint8_t *) block - emerald_flow_region.base);
    unsigned int size_class = emerald_flow_region.pages[offset >> EMERALD_FLOW_PAGE_SHIFT].size_class;
    uint64_t stride = emerald_flow_class_stride[size_class];
    uint64_t size = stride - sizeof(EmeraldFlowBlock);
    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_SLACK)) {
        size -= ((const uint8_t *) block)[stride - 1];
    }
    return size;
}

static const EmeraldFlowExtended *emerald_flow_extended_read(EmeraldFlowBlock *block) {
    static const EmeraldFlowExtended empty = {0};
    if (!EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTENDED)) {
        return &empty;
    }
    return (const EmeraldFlowExtended *) emerald_flow_at(emerald_flow_map_get(&emerald_flow_extended_map, emerald_flow_index(block)));
}

/* Called with the chamber lock held. The immutable empty metadata above must
   never be written, so all mutation explicitly goes through this accessor. */
static EmeraldFlowExtended *emerald_flow_extended_write(EmeraldFlowBlock *block) {
    uint32_t key = emerald_flow_index(block);
    if (!EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTENDED)) {
        EmeraldFlowExtended *extended = (EmeraldFlowExtended *) emerald_flow_slot_take_locked(EMERALD_FLOW_CLASS_EXTENSION);
        memset(extended, 0, sizeof(*extended));
        emerald_flow_map_put(&emerald_flow_extended_map, key, emerald_flow_index(extended));
        EMERALD_FLOW_SET(block, EMERALD_FLOW_EXTENDED);
    }
    return (EmeraldFlowExtended *) emerald_flow_at(emerald_flow_map_get(&emerald_flow_extended_map, key));
}

/* Gives the extension back to its slot class (lock held). */
static void emerald_flow_extended_release_locked(EmeraldFlowBlock *block) {
    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTENDED)) {
        uint32_t key = emerald_flow_index(block);
        emerald_flow_slot_give_locked(emerald_flow_at(emerald_flow_map_get(&emerald_flow_extended_map, key)));
        emerald_flow_map_remove(&emerald_flow_extended_map, key);
        EMERALD_FLOW_CLEAR(block, EMERALD_FLOW_EXTENDED);
    }
}

static uint64_t emerald_flow_external_bucket_index(const void *memory) {
    uint64_t value = (uint64_t) (uintptr_t) memory;
    value >>= 4;
    value *= 0x9E3779B97F4A7C15ULL;
    return (value >> 48) & (uint64_t) (EMERALD_FLOW_EXTERNAL_BUCKET_COUNT - 1);
}

static EmeraldFlowExternal *emerald_flow_external_at(uint32_t index) {
    return (EmeraldFlowExternal *) emerald_flow_at(index);
}

static void emerald_flow_external_insert_locked(EmeraldFlowExternal *external) {
    uint32_t *bucket = &emerald_flow_external_buckets[emerald_flow_external_bucket_index(external->memory)];
    uint32_t index = emerald_flow_index(external);

    external->hash_previous = 0;
    external->hash_next = *bucket;
    if (*bucket != 0) {
        emerald_flow_external_at(*bucket)->hash_previous = index;
    }
    *bucket = index;
}

static void emerald_flow_external_remove_locked(EmeraldFlowExternal *external) {
    if (external->hash_previous != 0) {
        emerald_flow_external_at(external->hash_previous)->hash_next = external->hash_next;
    } else {
        emerald_flow_external_buckets[emerald_flow_external_bucket_index(external->memory)] = external->hash_next;
    }

    if (external->hash_next != 0) {
        emerald_flow_external_at(external->hash_next)->hash_previous = external->hash_previous;
    }

    external->hash_next = 0;
    external->hash_previous = 0;
}

/* Registers a header for memory Flow does not own (stack objects, Pool and
   Shard owners) or for a malloc payload when managed is set. */
static EmeraldFlowBlock *emerald_flow_external_new_locked(void *memory, uint64_t size, int managed) {
    EmeraldFlowExternal *external = (EmeraldFlowExternal *) emerald_flow_slot_take_locked(EMERALD_FLOW_CLASS_EXTERNAL);
    memset(external, 0, sizeof(*external));
    external->memory = memory;
    external->size = size;
    atomic_store_explicit(&external->block.meta, EMERALD_FLOW_LIVE | EMERALD_FLOW_EXTERNAL | (managed ? EMERALD_FLOW_MANAGED : 0u), memory_order_relaxed);
    emerald_flow_external_insert_locked(external);
    return &external->block;
}

static EmeraldFlowBlock *emerald_flow_find_block_locked(void *memory);
static int emerald_static_string_contains_locked(void *memory);
static void emerald_flow_bond_release_locked(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list);
static void emerald_flow_bond_collect_cycles_locked(EmeraldFlowBlock **release_list);
static void emerald_flow_unlock_and_free(EmeraldFlowBlock *release_list);
static void emerald_flow_detach_from_parent_locked(EmeraldFlowBlock *block);
static void emerald_flow_bond_add_edge_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock *child);
static void emerald_flow_cycle_graph_changed_locked(void);

void emerald_flow_init(void) {
    emerald_flow_lock();
    emerald_flow_default_chamber.active = 1;
    emerald_flow_unlock();
}

/* Process exit reclaims memory far faster than per-object frees. Tear the heap
   down explicitly only when someone inspects it: debug reports, sanitizers,
   the use-after-free hunt or malloc payload mode for external memory tools. */
static int emerald_flow_full_shutdown_enabled(void) {
    return EMERALD_FLOW_SANITIZED || emerald_flow_debug_enabled() || emerald_uaf_enabled() ||
        emerald_flow_malloc_payloads();
}

/* Called with the lock held: frees every live block's malloc-side data, then
   drops all region pages at once and resets the allocator to empty. */
static void emerald_flow_region_teardown_locked(void) {
    EmeraldFlowRegion *region = &emerald_flow_region;

    if (region->base == NULL) {
        return;
    }

    for (uint32_t page_number = region->first_page; page_number < region->next_fresh_page; page_number++) {
        EmeraldFlowPage *page = &region->pages[page_number];
        unsigned int size_class = page->size_class;

        if (size_class != EMERALD_FLOW_CLASS_EXTERNAL && size_class < EMERALD_FLOW_CLASS_FIRST_INLINE) {
            continue;
        }

        uint8_t *slot = emerald_flow_page_address(page_number);
        uint8_t *end = slot + page->bump;

        for (; slot < end; slot += emerald_flow_class_stride[size_class]) {
            EmeraldFlowBlock *block = (EmeraldFlowBlock *) slot;

            if (!EMERALD_FLOW_HAS(block, EMERALD_FLOW_LIVE)) {
                continue;
            }

            // Each edge occurs in exactly one owner's outgoing list. Shutdown
            // needs no duplicate global edge registry or per-owner edge count.
            EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_out;
            while (edge != NULL) {
                EmeraldFlowBondEdge *next_edge = edge->owner_next;
                free(edge);
                edge = next_edge;
            }

            if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTERNAL) && EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED)) {
                free(((EmeraldFlowExternal *) block)->memory);
            }
        }
    }

    uint32_t used_pages = region->next_fresh_page - region->first_page;
    if (used_pages > 0) {
        emerald_flow_os_discard(emerald_flow_page_address(region->first_page), (uint64_t) used_pages << EMERALD_FLOW_PAGE_SHIFT);
        memset(&region->pages[region->first_page], 0, sizeof(EmeraldFlowPage) * (size_t) used_pages);
    }

    region->next_fresh_page = region->first_page;
    region->pooled_pages = 0;
    region->dirty_pooled_pages = 0;
    memset(region->partial, 0, sizeof(region->partial));
    memset(emerald_flow_external_buckets, 0, sizeof(emerald_flow_external_buckets));
    emerald_flow_map_free(&emerald_flow_extended_map);
}

void emerald_flow_shutdown(void) {
    emerald_flow_thread_shutdown();

    int full = emerald_flow_full_shutdown_enabled();
    EmeraldFlowCycleComponent *components = NULL;
    EmeraldStaticStringNode *static_string = NULL;

    emerald_flow_lock();
    EmeraldFlowChamber *chamber = &emerald_flow_default_chamber;
    uint64_t live_allocations = chamber->allocation_count;
    uint64_t live_bytes = chamber->allocated_bytes;
    uint64_t live_bonds = chamber->bond_live_count;
    uint64_t peak_allocations = chamber->peak_allocation_count;
    uint64_t peak_bytes = chamber->peak_allocated_bytes;
    uint64_t invalid_releases = chamber->invalid_release_count;

    if (full) {
        emerald_flow_region_teardown_locked();
        components = chamber->cycle_components;
        chamber->cycle_components = NULL;
        static_string = emerald_static_strings;
        emerald_static_strings = NULL;
        free(emerald_static_literal_addresses);
        emerald_static_literal_addresses = NULL;
        emerald_static_literal_count = 0;
        memset(emerald_static_string_buckets, 0, sizeof(emerald_static_string_buckets));
        memset(emerald_static_string_address_buckets, 0, sizeof(emerald_static_string_address_buckets));
        chamber->cycle_graph_revision = 0;
        /* Region indices are reused from now on; cached ancestry is stale. */
        chamber->ancestry_revision += 1;
    }

    chamber->bond_cycle_candidates = NULL;
    chamber->allocation_count = 0;
    chamber->allocated_bytes = 0;
    chamber->peak_allocation_count = 0;
    chamber->peak_allocated_bytes = 0;
    chamber->invalid_release_count = 0;
    chamber->container_owned_adoption_count = 0;
    chamber->container_owned_release_count = 0;
    chamber->container_inline_copy_count = 0;
    chamber->pool_slot_count = 0;
    chamber->pool_reuse_count = 0;
    chamber->shard_chunk_count = 0;
    chamber->shard_reuse_count = 0;
    chamber->shard_reset_count = 0;
    chamber->root_release_count = 0;
    chamber->root_released_bytes = 0;
    chamber->root_adoption_count = 0;
    chamber->root_shared_fallback_count = 0;
    chamber->bond_allocation_count = 0;
    chamber->bond_promotion_count = 0;
    chamber->bond_retain_count = 0;
    chamber->bond_release_count = 0;
    chamber->bond_live_count = 0;
    chamber->bond_cycle_scan_count = 0;
    chamber->bond_cycle_collection_count = 0;
    chamber->bond_cycle_collected_count = 0;
    chamber->bond_cycle_collected_bytes = 0;
    chamber->active = 0;
    emerald_flow_unlock();

    if (emerald_flow_debug_enabled() && (live_allocations > 0 || live_bonds > 0 || invalid_releases > 0)) {
        fprintf(stderr, "Emerald Flow debug: live=%llu bytes=%llu bonds=%llu peak=%llu/%llu invalid-releases=%llu\n",
            (unsigned long long) live_allocations,
            (unsigned long long) live_bytes,
            (unsigned long long) live_bonds,
            (unsigned long long) peak_allocations,
            (unsigned long long) peak_bytes,
            (unsigned long long) invalid_releases);
    }

    while (components != NULL) {
        EmeraldFlowCycleComponent *next = components->next;
        free(components);
        components = next;
    }

    while (static_string != NULL) {
        EmeraldStaticStringNode *next = static_string->next;
        free(static_string);
        static_string = next;
    }
}

static int emerald_flow_inline_size(uint64_t size) {
    return size <= EMERALD_FLOW_INLINE_LIMIT && !emerald_flow_malloc_payloads();
}

static unsigned int emerald_flow_inline_class(uint64_t size) {
    unsigned int granules = (unsigned int) ((size + 15) >> 4);

    if (granules <= 16) {
        return EMERALD_FLOW_CLASS_FIRST_INLINE + (granules == 0 ? 0 : granules - 1);
    }

    unsigned int size_class = EMERALD_FLOW_CLASS_FIRST_INLINE + 16;
    while (emerald_flow_class_stride[size_class] - sizeof(EmeraldFlowBlock) < size) {
        size_class += 1;
    }
    return size_class;
}

static void *emerald_flow_checked_alloc(uint64_t size, int atomic, int bonded) {
    if (size == 0) {
        size = 8;
    }

    if (size > (uint64_t) SIZE_MAX) {
        emerald_flow_fail(size);
    }

    int inline_payload = emerald_flow_inline_size(size);
    void *external_memory = NULL;

    if (!inline_payload) {
        external_memory = calloc(1, (size_t) size);
        if (external_memory == NULL) emerald_flow_fail(size);
    }

    emerald_flow_lock();
    EmeraldFlowChamber *chamber = &emerald_flow_default_chamber;
    EmeraldFlowBlock *block;
    void *memory;
    uint8_t *slack_byte = NULL;
    uint8_t slack_value = 0;

    if (inline_payload) {
        block = (EmeraldFlowBlock *) emerald_flow_slot_take_locked(emerald_flow_inline_class(size));
        memset(block, 0, sizeof(*block));
        uint32_t stride = emerald_flow_class_stride[emerald_flow_inline_class(size)];
        uint32_t slack = stride - (uint32_t) sizeof(EmeraldFlowBlock) - (uint32_t) size;
        atomic_store_explicit(&block->meta, EMERALD_FLOW_LIVE | EMERALD_FLOW_MANAGED | (slack != 0 ? EMERALD_FLOW_SLACK : 0u), memory_order_relaxed);
        slack_byte = slack != 0 ? (uint8_t *) block + stride - 1 : NULL;
        slack_value = (uint8_t) slack;
        memory = block + 1;
    } else {
        block = emerald_flow_external_new_locked(external_memory, size, 1);
        memory = external_memory;
    }

    if (atomic) {
        EMERALD_FLOW_SET(block, EMERALD_FLOW_ATOMIC);
    }

    if (bonded) {
        EMERALD_FLOW_SET(block, EMERALD_FLOW_BONDED);
        emerald_flow_extended_write(block)->bond_count = 1;
        chamber->bond_allocation_count += 1;
        chamber->bond_live_count += 1;
    }

    chamber->active = 1;
    chamber->allocation_count += 1;
    chamber->allocated_bytes += size;

    if (chamber->allocation_count > chamber->peak_allocation_count) {
        chamber->peak_allocation_count = chamber->allocation_count;
    }

    if (chamber->allocated_bytes > chamber->peak_allocated_bytes) {
        chamber->peak_allocated_bytes = chamber->allocated_bytes;
    }

    if (EMERALD_FLOW_UNLIKELY(emerald_flow_debug_enabled())) {
        chamber->debug_allocation_calls += 1;

        if (chamber->debug_allocation_calls % 200000 == 0) {
            fprintf(stderr, "[flow-alloc-debug] calls=%llu live=%llu peak=%llu live_bytes=%llu size=%llu\n",
                (unsigned long long) chamber->debug_allocation_calls,
                (unsigned long long) chamber->allocation_count,
                (unsigned long long) chamber->peak_allocation_count,
                (unsigned long long) chamber->allocated_bytes,
                (unsigned long long) size);
        }
    }

    emerald_flow_unlock();

    if (inline_payload) {
        /* Recycled slots hold old data; only this thread knows the slot yet. */
        memset(memory, 0, (size_t) size);
        if (slack_byte != NULL) {
            *slack_byte = slack_value;
        }
    }

    return memory;
}

void *emerald_flow_alloc(uint64_t size) {
    return emerald_flow_checked_alloc(size, 0, 0);
}

void *emerald_flow_alloc_atomic(uint64_t size) {
    return emerald_flow_checked_alloc(size, 1, 0);
}

void *emerald_flow_bond_alloc(uint64_t size) {
    /* Bootstrap mode keeps every allocation alive until process exit, so
       bond bookkeeping is pure overhead; skip it entirely. */
    return emerald_flow_checked_alloc(size, 0, !emerald_flow_bootstrap_leak_enabled());
}

void *emerald_flow_bond_promote(void *memory) {
    if (memory == NULL) {
        return NULL;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return memory;
    }

    emerald_flow_lock();
    EmeraldFlowBlock *block = emerald_flow_find_block_locked(memory);

    if (block != NULL && !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
        EmeraldFlowBlock *previous_owner = emerald_flow_at(block->parent);
        emerald_flow_detach_from_parent_locked(block);
        emerald_flow_cycle_graph_changed_locked();
        EMERALD_FLOW_SET(block, EMERALD_FLOW_BONDED);
        emerald_flow_extended_write(block)->bond_count = 1;
        EMERALD_FLOW_CLEAR(block, EMERALD_FLOW_SHARED);
        emerald_flow_default_chamber.bond_promotion_count += 1;
        emerald_flow_default_chamber.bond_live_count += 1;
        /* Preserve the old owner's reference separately from the new scope
           reference. Bond objects must not remain in the unique Root tree. */
        if (previous_owner != NULL) {
            emerald_flow_bond_add_edge_locked(previous_owner, block);
        }
    }

    emerald_flow_unlock();
    return memory;
}

void emerald_flow_bond_retain(void *memory) {
    if (memory == NULL) {
        return;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return;
    }

    emerald_flow_lock();
    EmeraldFlowBlock *block = emerald_flow_find_block_locked(memory);

    if (block != NULL && EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
        emerald_flow_extended_write(block)->bond_count += 1;
        EmeraldFlowCycleComponent *component = emerald_flow_extended_read(block)->cycle_component;
        if (component != NULL && component->graph_revision == emerald_flow_default_chamber.cycle_graph_revision) {
            component->external_count += 1;
        }
        emerald_flow_default_chamber.bond_retain_count += 1;
    }

    emerald_flow_unlock();
}

void emerald_flow_bond_release(void *memory) {
    if (memory == NULL) {
        return;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return;
    }

    EmeraldFlowBlock *release_list = NULL;
    emerald_flow_lock();
    uint64_t bond_release_count_before = emerald_flow_default_chamber.bond_release_count;
    EmeraldFlowBlock *block = emerald_flow_find_block_locked(memory);

    if (block == NULL || !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
        emerald_flow_default_chamber.invalid_release_count += 1;
    } else {
        emerald_flow_bond_release_locked(block, &release_list);
    }
    /* Only a successful retain-count decrement can make a cycle unreachable.
       The candidate-local collector starts from that decremented Bond; an
       invalid/no-op release must not pay for a graph traversal. */
    if (emerald_flow_default_chamber.bond_release_count != bond_release_count_before) {
        emerald_flow_bond_collect_cycles_locked(&release_list);
    }
    emerald_flow_unlock_and_free(release_list);
}

uint64_t emerald_flow_bond_allocation_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_allocation_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_promotion_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_promotion_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_retain_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_retain_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_release_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_release_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_live_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_live_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_cycle_scan_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_cycle_scan_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_cycle_collection_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_cycle_collection_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_cycle_collected_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_cycle_collected_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_bond_cycle_collected_bytes(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.bond_cycle_collected_bytes;
    emerald_flow_unlock();
    return value;
}

static EmeraldFlowBlock *emerald_flow_find_block_locked(void *memory) {
    EmeraldFlowBlock *block = emerald_flow_inline_block_locked(memory);

    if (block != NULL) {
        return block;
    }

    uint32_t index = emerald_flow_external_buckets[emerald_flow_external_bucket_index(memory)];

    while (index != 0) {
        EmeraldFlowExternal *external = emerald_flow_external_at(index);

        if (external->memory == memory) {
            return &external->block;
        }

        index = external->hash_next;
    }

    return NULL;
}
