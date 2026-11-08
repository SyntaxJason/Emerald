void *emerald_flow_pool_acquire(uint64_t site_id, uint64_t size) {
    if (size == 0) {
        size = 8;
    }

    EmeraldFlowPoolSlot *slot = emerald_flow_pool_slots;

    if (emerald_flow_bootstrap_leak_enabled()) {
        slot = NULL;
    }

    while (slot != NULL) {
        if (slot->site_id == site_id) {
            if (slot->size < size) {
                emerald_flow_owner_reset(slot->memory);
                emerald_flow_root_release(slot->memory);
                slot->memory = emerald_flow_checked_alloc(size, 0, 0);
                slot->size = size;
            } else {
                emerald_flow_owner_reset(slot->memory);
            }

            memset(slot->memory, 0, (size_t) slot->size);
            atomic_fetch_add_explicit(&emerald_flow_default_chamber.pool_reuse_count, 1, memory_order_relaxed);
            return slot->memory;
        }

        slot = slot->next;
    }

    slot = (EmeraldFlowPoolSlot *) emerald_flow_checked_alloc(sizeof(EmeraldFlowPoolSlot), 1, 0);
    slot->site_id = site_id;
    slot->size = size;
    slot->memory = emerald_flow_checked_alloc(size, 0, 0);
    slot->next = emerald_flow_pool_slots;
    emerald_flow_pool_slots = slot;

    atomic_fetch_add_explicit(&emerald_flow_default_chamber.pool_slot_count, 1, memory_order_relaxed);
    return slot->memory;
}

uint64_t emerald_flow_pool_slot_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.pool_slot_count, memory_order_relaxed);
}

uint64_t emerald_flow_pool_reuse_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.pool_reuse_count, memory_order_relaxed);
}

static uint64_t emerald_flow_align(uint64_t value, uint64_t alignment) {
    uint64_t remainder = value % alignment;

    if (remainder == 0) {
        return value;
    }

    return value + alignment - remainder;
}

static EmeraldFlowShardChunk *emerald_flow_shard_take_chunk(uint64_t minimum_capacity) {
    EmeraldFlowShardChunk *previous = NULL;
    EmeraldFlowShardChunk *chunk = emerald_flow_shard_free_chunks;

    while (chunk != NULL) {
        if (chunk->capacity >= minimum_capacity) {
            if (previous == NULL) {
                emerald_flow_shard_free_chunks = chunk->next;
            } else {
                previous->next = chunk->next;
            }

            chunk->next = NULL;
            chunk->used = 0;
            atomic_fetch_add_explicit(&emerald_flow_default_chamber.shard_reuse_count, 1, memory_order_relaxed);
            return chunk;
        }

        previous = chunk;
        chunk = chunk->next;
    }

    uint64_t capacity = minimum_capacity;
    if (capacity < EMERALD_FLOW_SHARD_DEFAULT_CHUNK) {
        capacity = EMERALD_FLOW_SHARD_DEFAULT_CHUNK;
    }

    if (capacity > (uint64_t) SIZE_MAX - sizeof(EmeraldFlowShardChunk)) {
        emerald_flow_fail(capacity);
    }

    chunk = (EmeraldFlowShardChunk *) malloc(sizeof(EmeraldFlowShardChunk) + (size_t) capacity);
    if (chunk == NULL) {
        emerald_flow_fail(capacity);
    }

    chunk->next = NULL;
    chunk->capacity = capacity;
    chunk->used = 0;
    atomic_fetch_add_explicit(&emerald_flow_default_chamber.shard_chunk_count, 1, memory_order_relaxed);
    return chunk;
}

uint64_t emerald_flow_shard_begin(void) {
    if (emerald_flow_shard_depth >= EMERALD_FLOW_SHARD_MAX_DEPTH) {
        fprintf(stderr, "Emerald Flow Shard nesting exceeded %d levels\n", EMERALD_FLOW_SHARD_MAX_DEPTH);
        fflush(stdout);
        abort();
    }

    uint64_t token = emerald_flow_shard_depth;
    EmeraldFlowShardFrame *frame = &emerald_flow_shard_frames[emerald_flow_shard_depth];
    frame->first = NULL;
    frame->current = NULL;
    frame->owners = NULL;
    emerald_flow_shard_depth += 1;
    return token;
}

void *emerald_flow_shard_alloc(uint64_t size) {
    if (emerald_flow_shard_depth == 0) {
        fprintf(stderr, "Emerald Flow Shard allocation without active Shard scope\n");
        fflush(stdout);
        abort();
    }

    if (size == 0) {
        size = 8;
    }

    if (size > (uint64_t) SIZE_MAX || size > UINT64_MAX - (EMERALD_FLOW_ALIGNMENT - 1)) {
        emerald_flow_fail(size);
    }

    uint64_t aligned_size = emerald_flow_align(size, EMERALD_FLOW_ALIGNMENT);
    EmeraldFlowShardFrame *frame = &emerald_flow_shard_frames[emerald_flow_shard_depth - 1];
    EmeraldFlowShardChunk *chunk = frame->current;

    if (chunk == NULL || aligned_size > chunk->capacity - chunk->used) {
        EmeraldFlowShardChunk *next = emerald_flow_shard_take_chunk(aligned_size);

        if (frame->first == NULL) {
            frame->first = next;
        } else {
            frame->current->next = next;
        }

        frame->current = next;
        chunk = next;
    }

    void *memory = chunk->memory + chunk->used;
    memset(memory, 0, (size_t) aligned_size);
    chunk->used += aligned_size;
    return memory;
}

void emerald_flow_shard_register_owner(void *owner) {
    if (owner == NULL) {
        return;
    }

    if (emerald_flow_shard_depth == 0) {
        fprintf(stderr, "Emerald Flow Shard owner without active Shard scope\n");
        fflush(stdout);
        abort();
    }

    EmeraldFlowShardOwner *entry = (EmeraldFlowShardOwner *) malloc(sizeof(EmeraldFlowShardOwner));
    if (entry == NULL) {
        emerald_flow_fail(sizeof(EmeraldFlowShardOwner));
    }

    emerald_flow_owner_enter(owner);
    EmeraldFlowShardFrame *frame = &emerald_flow_shard_frames[emerald_flow_shard_depth - 1];
    entry->memory = owner;
    entry->next = frame->owners;
    frame->owners = entry;
}

void emerald_flow_shard_end(uint64_t token) {
    if (emerald_flow_shard_depth == 0 || token + 1 != emerald_flow_shard_depth) {
        fprintf(stderr, "Emerald Flow Shard scope ended out of order\n");
        fflush(stdout);
        abort();
    }

    EmeraldFlowShardFrame *frame = &emerald_flow_shard_frames[token];
    EmeraldFlowShardOwner *owner = frame->owners;

    while (owner != NULL) {
        EmeraldFlowShardOwner *next = owner->next;
        emerald_flow_owner_leave(owner->memory);
        free(owner);
        owner = next;
    }

    frame->owners = NULL;
    EmeraldFlowShardChunk *chunk = frame->first;

    while (chunk != NULL) {
        EmeraldFlowShardChunk *next = chunk->next;

        if (emerald_flow_bootstrap_leak_enabled()) {
            chunk = next;
            continue;
        }

        chunk->used = 0;
        chunk->next = emerald_flow_shard_free_chunks;
        emerald_flow_shard_free_chunks = chunk;
        chunk = next;
    }

    frame->first = NULL;
    frame->current = NULL;
    emerald_flow_shard_depth = token;

    atomic_fetch_add_explicit(&emerald_flow_default_chamber.shard_reset_count, 1, memory_order_relaxed);
}

uint64_t emerald_flow_shard_chunk_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.shard_chunk_count, memory_order_relaxed);
}

uint64_t emerald_flow_shard_reuse_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.shard_reuse_count, memory_order_relaxed);
}

uint64_t emerald_flow_shard_reset_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.shard_reset_count, memory_order_relaxed);
}

void emerald_flow_thread_shutdown(void) {
    while (emerald_flow_shard_depth > 0) {
        emerald_flow_shard_end(emerald_flow_shard_depth - 1);
    }

    EmeraldFlowShardChunk *chunk = emerald_flow_shard_free_chunks;
    emerald_flow_shard_free_chunks = NULL;

    while (chunk != NULL) {
        EmeraldFlowShardChunk *next = chunk->next;
        free(chunk);
        chunk = next;
    }

    EmeraldFlowPoolSlot *slot = emerald_flow_pool_slots;
    emerald_flow_pool_slots = NULL;

    while (slot != NULL) {
        EmeraldFlowPoolSlot *next = slot->next;
        emerald_flow_owner_reset(slot->memory);
        emerald_flow_root_release(slot->memory);
        emerald_flow_root_release(slot);
        slot = next;
    }
}

uint64_t emerald_flow_peak_allocation_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.peak_allocation_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_peak_allocated_bytes(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.peak_allocated_bytes;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_invalid_release_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.invalid_release_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_container_owned_adoption_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.container_owned_adoption_count, memory_order_relaxed);
}

uint64_t emerald_flow_container_owned_release_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.container_owned_release_count, memory_order_relaxed);
}

void emerald_flow_note_container_owned_adoption(void) {
    atomic_fetch_add_explicit(&emerald_flow_default_chamber.container_owned_adoption_count, 1, memory_order_relaxed);
}

void emerald_flow_note_container_owned_release(void) {
    atomic_fetch_add_explicit(&emerald_flow_default_chamber.container_owned_release_count, 1, memory_order_relaxed);
}

void emerald_flow_note_container_inline_copy(void) {
    atomic_fetch_add_explicit(&emerald_flow_default_chamber.container_inline_copy_count, 1, memory_order_relaxed);
}

uint64_t emerald_flow_container_inline_copy_count(void) {
    return atomic_load_explicit(&emerald_flow_default_chamber.container_inline_copy_count, memory_order_relaxed);
}

uint64_t emerald_flow_allocation_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.allocation_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_allocated_bytes(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.allocated_bytes;
    emerald_flow_unlock();
    return value;
}

void *emerald_alloc(uint64_t size) {
    return emerald_flow_alloc(size);
}

void *emerald_alloc_atomic(uint64_t size) {
    return emerald_flow_alloc_atomic(size);
}


EmeraldString *emerald_static_string_from_cstr(const char *text) {
    if (text == NULL) {
        text = "";
    }

    uint64_t length = (uint64_t) strlen(text);
    uint64_t bucket_index = emerald_static_string_hash(text, length) % EMERALD_STATIC_STRING_BUCKET_COUNT;
    emerald_flow_lock();
    EmeraldStaticStringNode *node = emerald_static_string_buckets[bucket_index];

    while (node != NULL) {
        if (node->value.length == length && memcmp(node->value.bytes, text, (size_t) length) == 0) {
            EmeraldString *value = &node->value;
            emerald_flow_unlock();
            return value;
        }

        node = node->bucket_next;
    }

    if (length > (uint64_t) SIZE_MAX - sizeof(EmeraldStaticStringNode) - 1) {
        emerald_flow_unlock();
        emerald_flow_fail(length);
    }

    uint64_t allocation_size = sizeof(EmeraldStaticStringNode) + length + 1;
    node = (EmeraldStaticStringNode *) malloc((size_t) allocation_size);
    if (node == NULL) {
        emerald_flow_unlock();
        emerald_flow_fail(allocation_size);
    }

    if (length > 0) {
        memcpy(node->bytes, text, (size_t) length);
    }

    node->bytes[length] = 0;
    node->value.length = length;
    node->value.bytes = node->bytes;
    node->next = emerald_static_strings;
    emerald_static_strings = node;
    node->bucket_next = emerald_static_string_buckets[bucket_index];
    emerald_static_string_buckets[bucket_index] = node;
    /* Releases identify interned values by address in O(1). */
    uint64_t address_bucket = emerald_static_string_address_bucket(&node->value);
    node->address_next = emerald_static_string_address_buckets[address_bucket];
    emerald_static_string_address_buckets[address_bucket] = node;
    EmeraldString *value = &node->value;
    emerald_flow_unlock();
    return value;
}

static int emerald_static_literal_compare(const void *left, const void *right) {
    uintptr_t a = (uintptr_t) *(EmeraldString *const *) left;
    uintptr_t b = (uintptr_t) *(EmeraldString *const *) right;
    return (a > b) - (a < b);
}

void emerald_flow_register_static_strings(EmeraldString *const *values, uint64_t count) {
    if (count == 0) return;
    emerald_flow_lock();
    if (count > SIZE_MAX / sizeof(*values) - emerald_static_literal_count) {
        emerald_flow_unlock();
        emerald_flow_fail(count);
    }
    uint64_t total = emerald_static_literal_count + count;
    EmeraldString **addresses = realloc(emerald_static_literal_addresses, (size_t) total * sizeof(*values));
    if (addresses == NULL) { emerald_flow_unlock(); emerald_flow_fail(total); }
    memcpy(addresses + emerald_static_literal_count, values, (size_t) count * sizeof(*values));
    emerald_static_literal_addresses = addresses;
    emerald_static_literal_count = total;
    qsort(addresses, (size_t) total, sizeof(*addresses), emerald_static_literal_compare);
    emerald_flow_unlock();
}

/* Internal buffer growth only: unique atomic payloads contain no object
   identity or borrowed reference elements. An external header is stable even
   if realloc moves its payload, so ownership indices need no rewriting. */
void *emerald_flow_resize_atomic_owned(void *owner_memory, void *memory, uint64_t size) {
    if (size == 0 || size > SIZE_MAX) emerald_flow_fail(size);
    emerald_flow_lock();
    EmeraldFlowBlock *block = memory == NULL ? NULL : emerald_flow_find_block_locked(memory);
    uint64_t previous_size = block == NULL ? 0 : emerald_flow_block_size(block);
    EmeraldFlowBlock *owner = emerald_flow_find_block_locked(owner_memory);
    if (block != NULL && owner != NULL &&
        block->parent == emerald_flow_index(owner) && block->first_child == 0 &&
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTERNAL) &&
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED) &&
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_ATOMIC) &&
        !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED | EMERALD_FLOW_SHARED | EMERALD_FLOW_EXTENDED) &&
        !emerald_flow_bootstrap_leak_enabled()) {
        EmeraldFlowExternal *external = (EmeraldFlowExternal *) block;
        emerald_flow_external_remove_locked(external);
        void *grown = realloc(memory, (size_t) size);
        if (grown == NULL) { emerald_flow_unlock(); emerald_flow_fail(size); }
        if (size > previous_size) memset((uint8_t *) grown + previous_size, 0, (size_t) (size - previous_size));
        external->memory = grown;
        external->size = size;
        emerald_flow_external_insert_locked(external);
        EmeraldFlowChamber *chamber = &emerald_flow_default_chamber;
        chamber->allocated_bytes = chamber->allocated_bytes - previous_size + size;
        if (chamber->allocated_bytes > chamber->peak_allocated_bytes) chamber->peak_allocated_bytes = chamber->allocated_bytes;
        emerald_flow_unlock();
        return grown;
    }
    emerald_flow_unlock();
    void *grown = emerald_flow_alloc_atomic(size);
    if (memory != NULL) memcpy(grown, memory, (size_t) (previous_size < size ? previous_size : size));
    emerald_flow_root_replace(owner_memory, memory, grown);
    return grown;
}
