static void emerald_flow_cycle_component_drop_locked(EmeraldFlowBlock *block) {
    EmeraldFlowCycleComponent *component = emerald_flow_extended_read(block)->cycle_component;
    if (component != NULL) {
        emerald_flow_extended_write(block)->cycle_component = NULL;
        component->member_count -= 1;
        if (component->member_count == 0) {
            if (component->previous != NULL) {
                component->previous->next = component->next;
            } else {
                emerald_flow_default_chamber.cycle_components = component->next;
            }
            if (component->next != NULL) {
                component->next->previous = component->previous;
            }
            free(component);
        }
    }
}

static void emerald_flow_cycle_graph_changed_locked(void) {
    emerald_flow_default_chamber.cycle_graph_revision += 1;
    if (emerald_flow_default_chamber.cycle_graph_revision == 0) {
        /* Live components are listed, so wraparound needs no heap walk. */
        for (EmeraldFlowCycleComponent *component = emerald_flow_default_chamber.cycle_components;
             component != NULL; component = component->next) {
            component->graph_revision = 0;
        }
        emerald_flow_default_chamber.cycle_graph_revision = 1;
    }
}

/* ---------------------------------------------------------------------------
   Root-tree top cache. Ownership checks need the top-most Root ancestor of a
   block; deep chains (linked lists, parser stacks) would make every walk
   O(depth). Walks leave checkpoints mapping a node to its top. A checkpoint is
   used only while its top is still parentless, which covers linking a subtree
   under a new owner. Detaching a live block with descendants moves the
   ancestry_revision; detaching a leaf or removing a block only forgets that
   block's own checkpoint, because no other node's path passes through it.
   ------------------------------------------------------------------------- */
#define EMERALD_FLOW_TOP_CACHE_BITS 14
#define EMERALD_FLOW_TOP_CHECKPOINT_STRIDE 16

typedef struct EmeraldFlowTopEntry {
    uint32_t node;
    uint32_t top;
    uint64_t revision;
} EmeraldFlowTopEntry;

static EmeraldFlowTopEntry emerald_flow_top_cache[1u << EMERALD_FLOW_TOP_CACHE_BITS];

static EmeraldFlowTopEntry *emerald_flow_top_entry(uint32_t node) {
    return &emerald_flow_top_cache[(node * 2654435761u) >> (32 - EMERALD_FLOW_TOP_CACHE_BITS)];
}

static void emerald_flow_top_forget_locked(EmeraldFlowBlock *block) {
    uint32_t index = emerald_flow_index(block);
    EmeraldFlowTopEntry *entry = emerald_flow_top_entry(index);
    if (entry->node == index) {
        entry->node = 0;
    }
}

static EmeraldFlowBlock *emerald_flow_root_top_locked(EmeraldFlowBlock *start) {
    uint64_t revision = emerald_flow_default_chamber.ancestry_revision;
    EmeraldFlowBlock *current = start;
    uint64_t steps = 0;

    while (current->parent != 0) {
        uint32_t index = emerald_flow_index(current);
        EmeraldFlowTopEntry *entry = emerald_flow_top_entry(index);

        if (entry->node == index && entry->revision == revision) {
            EmeraldFlowBlock *top = emerald_flow_at(entry->top);
            if (top->parent == 0) {
                current = top;
                break;
            }
        }

        current = emerald_flow_at(current->parent);
        steps += 1;
    }

    if (steps >= EMERALD_FLOW_TOP_CHECKPOINT_STRIDE) {
        /* Revisit the walked prefix once and leave periodic checkpoints. */
        uint32_t top = emerald_flow_index(current);
        EmeraldFlowBlock *node = start;
        uint64_t walked = 0;

        while (walked < steps) {
            if (walked % EMERALD_FLOW_TOP_CHECKPOINT_STRIDE == 0) {
                EmeraldFlowTopEntry *entry = emerald_flow_top_entry(emerald_flow_index(node));
                entry->node = emerald_flow_index(node);
                entry->top = top;
                entry->revision = revision;
            }
            node = emerald_flow_at(node->parent);
            walked += 1;
        }
    }

    return current;
}

static void emerald_flow_link_child_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock *child) {
    if (owner == NULL || child == NULL) {
        return;
    }

    emerald_flow_cycle_graph_changed_locked();
    uint32_t child_index = emerald_flow_index(child);
    child->parent = emerald_flow_index(owner);
    child->next_sibling = owner->first_child;
    owner->first_child = child_index;
}

static void emerald_flow_unlink_from_parent_locked(EmeraldFlowBlock *block) {
    if (block == NULL || block->parent == 0) {
        return;
    }

    emerald_flow_cycle_graph_changed_locked();
    EmeraldFlowBlock *parent = emerald_flow_at(block->parent);
    uint32_t index = emerald_flow_index(block);
    uint32_t next = block->next_sibling;
    uint32_t *cursor = &parent->first_child;

    /* Newest children sit at the head, so the common unlink is O(1). */
    while (*cursor != 0) {
        if (*cursor == index) {
            *cursor = next;
            break;
        }

        cursor = &emerald_flow_at(*cursor)->next_sibling;
    }

    block->parent = 0;
    block->next_sibling = 0;
}

/* Detaches a block that stays alive, so its subtree gets a new top. */
static void emerald_flow_detach_from_parent_locked(EmeraldFlowBlock *block) {
    if (block == NULL || block->parent == 0) {
        return;
    }

    if (block->first_child != 0) {
        emerald_flow_default_chamber.ancestry_revision += 1;
    } else {
        emerald_flow_top_forget_locked(block);
    }

    emerald_flow_unlink_from_parent_locked(block);
}

/* Unregisters a block: lookups fail from here on, while its slot stays
   untouched until the transaction's release list is freed. */
static void emerald_flow_remove_block_locked(EmeraldFlowBlock *block) {
    emerald_flow_cycle_graph_changed_locked();
    emerald_flow_cycle_component_drop_locked(block);
    emerald_flow_top_forget_locked(block);
    EMERALD_FLOW_CLEAR(block, EMERALD_FLOW_LIVE);

    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTERNAL)) {
        emerald_flow_external_remove_locked((EmeraldFlowExternal *) block);
    }
}

static void emerald_flow_release_list_push(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list) {
    block->next_sibling = emerald_flow_index(*release_list);
    *release_list = block;
}

static void emerald_flow_collect_release_locked(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list);

static void emerald_flow_bond_queue_cycle_candidate_locked(EmeraldFlowBlock *block) {
    if (block == NULL || !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED) || emerald_flow_extended_read(block)->bond_count == 0 ||
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_COLLECTING) || EMERALD_FLOW_HAS(block, EMERALD_FLOW_CANDIDATE_QUEUED)) {
        return;
    }

    EMERALD_FLOW_SET(block, EMERALD_FLOW_CANDIDATE_QUEUED);
    emerald_flow_extended_write(block)->cycle_candidate_next = emerald_flow_index(emerald_flow_default_chamber.bond_cycle_candidates);
    emerald_flow_default_chamber.bond_cycle_candidates = block;
}

static void emerald_flow_bond_release_locked(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list) {
    if (block == NULL || !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED) || emerald_flow_extended_read(block)->bond_count == 0 ||
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_COLLECTING)) {
        return;
    }

    emerald_flow_extended_write(block)->bond_count -= 1;
    EmeraldFlowCycleComponent *component = emerald_flow_extended_read(block)->cycle_component;
    int cached = component != NULL &&
        component->graph_revision == emerald_flow_default_chamber.cycle_graph_revision;
    if (cached && component->external_count > 0) {
        component->external_count -= 1;
    }
    emerald_flow_default_chamber.bond_release_count += 1;

    if (emerald_flow_extended_read(block)->bond_count == 0) {
        if (emerald_flow_default_chamber.bond_live_count > 0) {
            emerald_flow_default_chamber.bond_live_count -= 1;
        }

        emerald_flow_collect_release_locked(block, release_list);
    } else if (!cached || component->external_count == 0) {
        emerald_flow_bond_queue_cycle_candidate_locked(block);
    }
}

static void emerald_flow_bond_add_edge_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock *child) {
    EmeraldFlowBondEdge *edge = (EmeraldFlowBondEdge *) malloc(sizeof(EmeraldFlowBondEdge));
    if (edge == NULL) {
        emerald_flow_fail(sizeof(EmeraldFlowBondEdge));
    }

    emerald_flow_cycle_graph_changed_locked();
    edge->owner = owner;
    edge->child = child;
    edge->owner_previous = NULL;
    edge->owner_next = emerald_flow_extended_read(owner)->first_bond_out;

    if (edge->owner_next != NULL) {
        edge->owner_next->owner_previous = edge;
    }

    emerald_flow_extended_write(owner)->first_bond_out = edge;
    edge->child_previous = NULL;
    edge->child_next = emerald_flow_extended_read(child)->first_bond_in;

    if (edge->child_next != NULL) {
        edge->child_next->child_previous = edge;
    }

    emerald_flow_extended_write(child)->first_bond_in = edge;
    emerald_flow_extended_write(child)->bond_count += 1;
    emerald_flow_default_chamber.bond_retain_count += 1;
}

static void emerald_flow_bond_unlink_edge_locked(EmeraldFlowBondEdge *edge) {
    if (edge == NULL) {
        return;
    }

    emerald_flow_cycle_graph_changed_locked();
    EmeraldFlowBlock *owner = edge->owner;
    EmeraldFlowBlock *child = edge->child;

    if (edge->owner_previous != NULL) {
        edge->owner_previous->owner_next = edge->owner_next;
    } else if (owner != NULL && emerald_flow_extended_read(owner)->first_bond_out == edge) {
        emerald_flow_extended_write(owner)->first_bond_out = edge->owner_next;
    }

    if (edge->owner_next != NULL) {
        edge->owner_next->owner_previous = edge->owner_previous;
    }

    if (edge->child_previous != NULL) {
        edge->child_previous->child_next = edge->child_next;
    } else if (child != NULL && emerald_flow_extended_read(child)->first_bond_in == edge) {
        emerald_flow_extended_write(child)->first_bond_in = edge->child_next;
    }

    if (edge->child_next != NULL) {
        edge->child_next->child_previous = edge->child_previous;
    }

    edge->owner_next = NULL;
    edge->owner_previous = NULL;
    edge->child_next = NULL;
    edge->child_previous = NULL;
}

static int emerald_flow_bond_remove_edge_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock *child, EmeraldFlowBlock **release_list) {
    EmeraldFlowBondEdge *edge = emerald_flow_extended_read(owner)->first_bond_out;

    while (edge != NULL) {
        if (edge->child == child) {
            emerald_flow_bond_unlink_edge_locked(edge);
            free(edge);
            emerald_flow_bond_release_locked(child, release_list);
            return 1;
        }

        edge = edge->owner_next;
    }

    return 0;
}

static void emerald_flow_bond_release_owner_edges_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock **release_list) {
    if (emerald_flow_extended_read(owner)->first_bond_out == NULL) {
        return;
    }

    EmeraldFlowBondEdge *matched = NULL;

    while (emerald_flow_extended_read(owner)->first_bond_out != NULL) {
        EmeraldFlowBondEdge *edge = emerald_flow_extended_read(owner)->first_bond_out;
        emerald_flow_bond_unlink_edge_locked(edge);
        edge->owner_next = matched;
        matched = edge;
    }

    /* Release only after detaching every edge: the release cascade mutates
       the global edge lists and would invalidate this iteration. */
    while (matched != NULL) {
        EmeraldFlowBondEdge *edge = matched;
        matched = edge->owner_next;
        emerald_flow_bond_release_locked(edge->child, release_list);
        free(edge);
    }
}

static void emerald_flow_bond_remove_incoming_edges_locked(EmeraldFlowBlock *child) {
    while (emerald_flow_extended_read(child)->first_bond_in != NULL) {
        EmeraldFlowBondEdge *edge = emerald_flow_extended_read(child)->first_bond_in;
        emerald_flow_bond_unlink_edge_locked(edge);
        free(edge);
    }
}

static void emerald_flow_note_block_released_locked(EmeraldFlowBlock *block) {
    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED)) {
        uint64_t size = emerald_flow_block_size(block);

        if (emerald_flow_default_chamber.allocation_count > 0) {
            emerald_flow_default_chamber.allocation_count -= 1;
        }

        if (emerald_flow_default_chamber.allocated_bytes >= size) {
            emerald_flow_default_chamber.allocated_bytes -= size;
        } else {
            emerald_flow_default_chamber.allocated_bytes = 0;
        }

        emerald_flow_default_chamber.root_release_count += 1;
        emerald_flow_default_chamber.root_released_bytes += size;
    }
}

/* Releases a block and everything it uniquely owns. Ownership chains can be
   arbitrarily deep, and Bond cascades re-enter this function, so the work is
   an explicit stack threaded through next_sibling of detached blocks: nested
   calls only push, and the outermost call drains. A block is marked when it
   is pushed so the same metadata node is never linked into release_list
   twice. Cycle victims use the same flag and are collected by their own pass. */
static void emerald_flow_collect_release_locked(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list) {
    EmeraldFlowChamber *chamber = &emerald_flow_default_chamber;

    if (block == NULL || EMERALD_FLOW_HAS(block, EMERALD_FLOW_COLLECTING)) {
        return;
    }

    EMERALD_FLOW_SET(block, EMERALD_FLOW_COLLECTING);
    /* The whole subtree is released and each member forgets its own top
       checkpoint on removal, so cached ancestry elsewhere stays valid. */
    emerald_flow_unlink_from_parent_locked(block);
    block->next_sibling = chamber->release_pending;
    chamber->release_pending = emerald_flow_index(block);

    if (chamber->release_draining) {
        return;
    }

    chamber->release_draining = 1;

    while (chamber->release_pending != 0) {
        EmeraldFlowBlock *current = emerald_flow_at(chamber->release_pending);
        chamber->release_pending = current->next_sibling;
        current->next_sibling = 0;

        emerald_flow_bond_release_owner_edges_locked(current, release_list);
        /* A metadata block must never leave dangling references in the Bond
           edge graph. Normally its incoming count has already reached zero;
           this also makes overlapping owner/Bond release cascades robust. */
        if (EMERALD_FLOW_HAS(current, EMERALD_FLOW_BONDED)) {
            emerald_flow_bond_remove_incoming_edges_locked(current);
        }

        uint32_t child_index = current->first_child;
        current->first_child = 0;

        while (child_index != 0) {
            EmeraldFlowBlock *child = emerald_flow_at(child_index);
            child_index = child->next_sibling;
            child->parent = 0;
            child->next_sibling = 0;

            if (!EMERALD_FLOW_HAS(child, EMERALD_FLOW_COLLECTING)) {
                EMERALD_FLOW_SET(child, EMERALD_FLOW_COLLECTING);
                child->next_sibling = chamber->release_pending;
                chamber->release_pending = emerald_flow_index(child);
            }
        }

        emerald_flow_remove_block_locked(current);
        emerald_flow_note_block_released_locked(current);
        emerald_flow_release_list_push(current, release_list);
    }

    chamber->release_draining = 0;
}

static void emerald_flow_collect_cycle_block_locked(EmeraldFlowBlock *block, EmeraldFlowBlock **release_list) {
    uint32_t child_index = block->first_child;
    block->first_child = 0;

    while (child_index != 0) {
        EmeraldFlowBlock *child = emerald_flow_at(child_index);
        child_index = child->next_sibling;
        child->parent = 0;
        child->next_sibling = 0;
        emerald_flow_collect_release_locked(child, release_list);
    }

    emerald_flow_unlink_from_parent_locked(block);
    emerald_flow_remove_block_locked(block);
    emerald_flow_note_block_released_locked(block);

    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED)) {
        emerald_flow_default_chamber.bond_cycle_collected_bytes += emerald_flow_block_size(block);
    }

    if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED) && emerald_flow_default_chamber.bond_live_count > 0) {
        emerald_flow_default_chamber.bond_live_count -= 1;
    }

    emerald_flow_default_chamber.bond_cycle_collected_count += 1;
    emerald_flow_release_list_push(block, release_list);
}

/* Scan marks are the SCAN_MARKED flag plus an entry in a scan-local table
   (block index -> scan index), both cleared when the scan ends. */
static EmeraldFlowMap emerald_flow_scan_map;

static void emerald_flow_scan_map_put(uint32_t key, uint32_t value) {
    emerald_flow_map_put(&emerald_flow_scan_map, key, value);
}

static uint32_t emerald_flow_scan_index(EmeraldFlowBlock *block) {
    return emerald_flow_map_get(&emerald_flow_scan_map, emerald_flow_index(block));
}

static void emerald_flow_scan_map_clear(EmeraldFlowBlock **blocks, uint64_t count) {
    for (uint64_t index = 0; index < count; index++) {
        emerald_flow_map_remove(&emerald_flow_scan_map, emerald_flow_index(blocks[index]));
    }
    if (emerald_flow_scan_map.entries != NULL && emerald_flow_scan_map.mask > 4095) {
        emerald_flow_map_free(&emerald_flow_scan_map);
    }
}
static int emerald_flow_cycle_marked(EmeraldFlowBlock *block) {
    return block != NULL && EMERALD_FLOW_HAS(block, EMERALD_FLOW_SCAN_MARKED);
}

/* A Root child contributes one implicit ownership reference. Bond edges
   contribute counted references. Both kinds must participate in trial deletion. */
static void emerald_flow_cycle_append_locked(
    EmeraldFlowBlock *block,
    EmeraldFlowBlock ***blocks,
    uint64_t *count,
    uint64_t *capacity
) {
    if (block == NULL || !EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED) || EMERALD_FLOW_HAS(block, EMERALD_FLOW_COLLECTING) ||
        EMERALD_FLOW_HAS(block, EMERALD_FLOW_SCAN_MARKED)) {
        return;
    }

    if (*count == *capacity) {
        if (*capacity > (uint64_t) SIZE_MAX / (2 * sizeof(EmeraldFlowBlock *))) {
            emerald_flow_fail(*capacity * sizeof(EmeraldFlowBlock *));
        }
        *capacity *= 2;
        EmeraldFlowBlock **grown = (EmeraldFlowBlock **) realloc(
            *blocks, sizeof(EmeraldFlowBlock *) * (size_t) *capacity
        );
        if (grown == NULL) {
            emerald_flow_fail(*capacity * sizeof(EmeraldFlowBlock *));
        }
        *blocks = grown;
    }

    EMERALD_FLOW_SET(block, EMERALD_FLOW_SCAN_MARKED);
    emerald_flow_scan_map_put(emerald_flow_index(block), (uint32_t) *count);
    (*blocks)[(*count)++] = block;
}

static void emerald_flow_cycle_cache_component_locked(
    EmeraldFlowBlock **blocks,
    uint64_t count,
    uint8_t *members,
    uint64_t *queue
) {
    /* Small graphs are cheaper to scan directly. Large immutable strongly
       connected groups share one external-reference count until an edge changes. */
    if (count < 64) {
        return;
    }
    memset(members, 0, (size_t) count);
    uint64_t start = 0;
    uint64_t end = 1;
    members[0] = 1;
    queue[0] = 0;

    /* The forward closure is already known. Its reverse closure from the
       candidate is exactly the candidate's strongly connected component. */
    while (start < end) {
        EmeraldFlowBlock *block = blocks[queue[start++]];
        EmeraldFlowBlock *parent = emerald_flow_at(block->parent);
        if (emerald_flow_cycle_marked(parent) && !members[emerald_flow_scan_index(parent)]) {
            members[emerald_flow_scan_index(parent)] = 1;
            queue[end++] = emerald_flow_scan_index(parent);
        }
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_in;
             edge != NULL; edge = edge->child_next) {
            EmeraldFlowBlock *owner = edge->owner;
            if (emerald_flow_cycle_marked(owner) && !members[emerald_flow_scan_index(owner)]) {
                members[emerald_flow_scan_index(owner)] = 1;
                queue[end++] = emerald_flow_scan_index(owner);
            }
        }
    }
    if (end < 64) {
        return;
    }

    uint64_t external_count = 0;
    uint64_t bonded_members = 0;
    for (uint64_t index = 0; index < end; index++) {
        EmeraldFlowBlock *block = blocks[queue[index]];
        if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
            external_count += emerald_flow_extended_read(block)->bond_count;
            bonded_members += 1;
        } else {
            external_count += 1;
        }
        EmeraldFlowBlock *parent = emerald_flow_at(block->parent);
        if (emerald_flow_cycle_marked(parent) && members[emerald_flow_scan_index(parent)]) {
            external_count -= 1;
        }
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_in;
             edge != NULL; edge = edge->child_next) {
            if (emerald_flow_cycle_marked(edge->owner) && members[emerald_flow_scan_index(edge->owner)]) {
                external_count -= 1;
            }
        }
    }

    EmeraldFlowCycleComponent *component = (EmeraldFlowCycleComponent *) malloc(sizeof(*component));
    if (component == NULL) {
        emerald_flow_fail(sizeof(*component));
    }
    component->graph_revision = emerald_flow_default_chamber.cycle_graph_revision;
    /* Only Bond members consult the cache (retain, release, candidate scan),
       so plain Root members do not need an extension just to point at it. */
    component->member_count = bonded_members;
    component->external_count = external_count;
    component->previous = NULL;
    component->next = emerald_flow_default_chamber.cycle_components;
    if (component->next != NULL) {
        component->next->previous = component;
    }
    emerald_flow_default_chamber.cycle_components = component;
    for (uint64_t index = 0; index < end; index++) {
        EmeraldFlowBlock *block = blocks[queue[index]];
        if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
            emerald_flow_cycle_component_drop_locked(block);
            emerald_flow_extended_write(block)->cycle_component = component;
        }
    }
}

static int emerald_flow_cycle_owner_is_rooted_locked(EmeraldFlowBlock *owner) {
    if (owner == NULL || EMERALD_FLOW_HAS(owner, EMERALD_FLOW_COLLECTING)) {
        return 0;
    }

    /* Bond blocks never stay in the Root tree, so the walk up the unique
       parents ends at the first Bond or at a parentless Root. */
    EmeraldFlowBlock *top = emerald_flow_root_top_locked(owner);

    if (EMERALD_FLOW_HAS(top, EMERALD_FLOW_COLLECTING)) {
        return 0;
    }

    if (EMERALD_FLOW_HAS(top, EMERALD_FLOW_BONDED)) {
        uint64_t incoming = 0;
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(top)->first_bond_in;
             edge != NULL && incoming < emerald_flow_extended_read(top)->bond_count; edge = edge->child_next) {
            incoming += 1;
        }
        return emerald_flow_extended_read(top)->bond_count > incoming;
    }

    return 1; /* A live unique Root or registered stack owner. */
}

static void emerald_flow_bond_collect_candidate_locked(
    EmeraldFlowBlock *candidate,
    EmeraldFlowBlock **release_list
) {
    if (candidate == NULL || !EMERALD_FLOW_HAS(candidate, EMERALD_FLOW_BONDED) || !EMERALD_FLOW_HAS(candidate, EMERALD_FLOW_MANAGED) ||
        EMERALD_FLOW_HAS(candidate, EMERALD_FLOW_COLLECTING) || emerald_flow_extended_read(candidate)->bond_count == 0) {
        return;
    }
    if (candidate->first_child == 0 && emerald_flow_extended_read(candidate)->first_bond_out == NULL) {
        return; /* A leaf cannot participate in an ownership cycle. */
    }
    uint64_t incoming = 0;
    for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(candidate)->first_bond_in;
         edge != NULL && incoming < emerald_flow_extended_read(candidate)->bond_count; edge = edge->child_next) {
        incoming += 1;
    }
    if (emerald_flow_extended_read(candidate)->bond_count > incoming) {
        return; /* A direct external reference still keeps its entire closure alive. */
    }
    EmeraldFlowCycleComponent *component = emerald_flow_extended_read(candidate)->cycle_component;
    if (component != NULL &&
        component->graph_revision == emerald_flow_default_chamber.cycle_graph_revision &&
        component->external_count > 0) {
        return;
    }

    /* An incoming owner with a proven live Root chain keeps this whole
       closure reachable. Avoid walking large shared AST subtrees on every
       temporary header release. Ancestors in a Bond cycle do not qualify. */
    for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(candidate)->first_bond_in;
         edge != NULL; edge = edge->child_next) {
        if (emerald_flow_cycle_owner_is_rooted_locked(edge->owner)) {
            return;
        }
    }

    uint64_t capacity = 64;
    EmeraldFlowBlock **blocks = (EmeraldFlowBlock **) malloc(sizeof(*blocks) * (size_t) capacity);
    if (blocks == NULL) {
        emerald_flow_fail(capacity * sizeof(*blocks));
    }
    uint64_t count = 0;
    emerald_flow_cycle_append_locked(candidate, &blocks, &count, &capacity);
    for (uint64_t index = 0; index < count; index++) {
        EmeraldFlowBlock *block = blocks[index];
        for (EmeraldFlowBlock *child = emerald_flow_at(block->first_child);
             child != NULL; child = emerald_flow_at(child->next_sibling)) {
            emerald_flow_cycle_append_locked(child, &blocks, &count, &capacity);
        }
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_out;
             edge != NULL; edge = edge->owner_next) {
            emerald_flow_cycle_append_locked(edge->child, &blocks, &count, &capacity);
        }
    }

    emerald_flow_default_chamber.bond_cycle_scan_count += 1;
    uint64_t *trial_counts = (uint64_t *) malloc(sizeof(*trial_counts) * (size_t) count);
    uint8_t *reachable = (uint8_t *) calloc((size_t) count, sizeof(*reachable));
    uint64_t *queue = (uint64_t *) malloc(sizeof(*queue) * (size_t) count);
    if (trial_counts == NULL || reachable == NULL || queue == NULL) {
        emerald_flow_fail(count * sizeof(uint64_t));
    }
    for (uint64_t index = 0; index < count; index++) {
        trial_counts[index] = EMERALD_FLOW_HAS(blocks[index], EMERALD_FLOW_BONDED) ? emerald_flow_extended_read(blocks[index])->bond_count : 1;
    }
    for (uint64_t index = 0; index < count; index++) {
        EmeraldFlowBlock *block = blocks[index];
        for (EmeraldFlowBlock *child = emerald_flow_at(block->first_child);
             child != NULL; child = emerald_flow_at(child->next_sibling)) {
            if (emerald_flow_cycle_marked(child)) {
                trial_counts[emerald_flow_scan_index(child)] -= 1;
            }
        }
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_out;
             edge != NULL; edge = edge->owner_next) {
            EmeraldFlowBlock *child = edge->child;
            if (emerald_flow_cycle_marked(child) && trial_counts[emerald_flow_scan_index(child)] > 0) {
                trial_counts[emerald_flow_scan_index(child)] -= 1;
            }
        }
    }

    uint64_t start = 0;
    uint64_t end = 0;
    for (uint64_t index = 0; index < count; index++) {
        if (trial_counts[index] > 0) {
            reachable[index] = 1;
            queue[end++] = index;
        }
    }
    while (start < end) {
        EmeraldFlowBlock *block = blocks[queue[start++]];
        for (EmeraldFlowBlock *child = emerald_flow_at(block->first_child);
             child != NULL; child = emerald_flow_at(child->next_sibling)) {
            if (emerald_flow_cycle_marked(child) && !reachable[emerald_flow_scan_index(child)]) {
                reachable[emerald_flow_scan_index(child)] = 1;
                queue[end++] = emerald_flow_scan_index(child);
            }
        }
        for (EmeraldFlowBondEdge *edge = emerald_flow_extended_read(block)->first_bond_out;
             edge != NULL; edge = edge->owner_next) {
            EmeraldFlowBlock *child = edge->child;
            if (emerald_flow_cycle_marked(child) && !reachable[emerald_flow_scan_index(child)]) {
                reachable[emerald_flow_scan_index(child)] = 1;
                queue[end++] = emerald_flow_scan_index(child);
            }
        }
    }
    free(trial_counts);

    uint64_t victim_count = 0;
    for (uint64_t index = 0; index < count; index++) {
        if (!reachable[index]) {
            EMERALD_FLOW_SET(blocks[index], EMERALD_FLOW_COLLECTING);
            victim_count += 1;
        }
    }
    if (victim_count == 0) {
        emerald_flow_cycle_cache_component_locked(blocks, count, reachable, queue);
    } else {
        /* Mark all victims first, then detach every edge before releasing
           outside children: releases must not invalidate the edge iteration. */
        EmeraldFlowBondEdge *detached_edges = NULL;
        for (uint64_t index = 0; index < count; index++) {
            if (reachable[index]) {
                continue;
            }
            EmeraldFlowBlock *victim = blocks[index];
            while (emerald_flow_extended_read(victim)->first_bond_out != NULL) {
                EmeraldFlowBondEdge *edge = emerald_flow_extended_read(victim)->first_bond_out;
                EmeraldFlowBlock *child = edge->child;
                int child_victim = emerald_flow_cycle_marked(child) && !reachable[emerald_flow_scan_index(child)];
                emerald_flow_bond_unlink_edge_locked(edge);
                if (child_victim) {
                    free(edge);
                } else {
                    edge->owner_next = detached_edges;
                    detached_edges = edge;
                }
            }
            while (emerald_flow_extended_read(victim)->first_bond_in != NULL) {
                EmeraldFlowBondEdge *edge = emerald_flow_extended_read(victim)->first_bond_in;
                emerald_flow_bond_unlink_edge_locked(edge);
                free(edge);
            }
        }
        while (detached_edges != NULL) {
            EmeraldFlowBondEdge *next = detached_edges->owner_next;
            emerald_flow_bond_release_locked(detached_edges->child, release_list);
            free(detached_edges);
            detached_edges = next;
        }
        emerald_flow_default_chamber.bond_cycle_collection_count += 1;
        for (uint64_t index = 0; index < count; index++) {
            if (!reachable[index]) {
                emerald_flow_collect_cycle_block_locked(blocks[index], release_list);
            }
        }
    }

    /* Released blocks stay readable until the transaction frees its list. */
    for (uint64_t index = 0; index < count; index++) {
        EMERALD_FLOW_CLEAR(blocks[index], EMERALD_FLOW_SCAN_MARKED);
    }
    emerald_flow_scan_map_clear(blocks, count);
    free(queue);
    free(blocks);
    free(reachable);
}

static void emerald_flow_bond_collect_cycles_locked(EmeraldFlowBlock **release_list) {
    if (emerald_flow_bootstrap_leak_enabled()) {
        return;
    }
    while (emerald_flow_default_chamber.bond_cycle_candidates != NULL) {
        EmeraldFlowBlock *candidate = emerald_flow_default_chamber.bond_cycle_candidates;
        emerald_flow_default_chamber.bond_cycle_candidates = emerald_flow_at(emerald_flow_extended_read(candidate)->cycle_candidate_next);
        emerald_flow_extended_write(candidate)->cycle_candidate_next = 0;
        EMERALD_FLOW_CLEAR(candidate, EMERALD_FLOW_CANDIDATE_QUEUED);
        emerald_flow_bond_collect_candidate_locked(candidate, release_list);
    }
}

static void emerald_flow_bond_collect_pending_cycles_locked(
    uint64_t release_count_before,
    EmeraldFlowBlock **release_list
) {
    if (emerald_flow_default_chamber.bond_release_count != release_count_before) {
        emerald_flow_bond_collect_cycles_locked(release_list);
    }
}


/* ---------------------------------------------------------------------------
   Temporary use-after-free hunt, active only with EMERALD_FLOW_UAF_HUNT=1.
   Small released payloads (wrapper objects such as LlvmValue) are poisoned
   with a sentinel handle and parked in a FIFO quarantine together with the
   backtrace of the release. When the LLVM bridge later reads the sentinel it
   prints the release and the use backtrace and aborts. The hunt implies
   malloc payloads, so quarantined memory never returns to a Flow slot.
   ------------------------------------------------------------------------- */
#include <execinfo.h>

#define EMERALD_UAF_SENTINEL ((int32_t) 0x7EAD0BAD)
#define EMERALD_UAF_QUARANTINE 262144u
#define EMERALD_UAF_MAX_SIZE 32u
#define EMERALD_UAF_FRAMES 24

typedef struct EmeraldUafEntry {
    void *memory;
    void *allocation;
    uint64_t size;
    int frame_count;
    void *frames[EMERALD_UAF_FRAMES];
} EmeraldUafEntry;

static EmeraldUafEntry *emerald_uaf_entries = NULL;
static uint64_t emerald_uaf_next = 0;

EMERALD_INTERNAL void emerald_uaf_report(const char *site, void *object) {
    void *now[EMERALD_UAF_FRAMES];
    int count = backtrace(now, EMERALD_UAF_FRAMES);

    fprintf(stderr, "[uaf-hunt] %s: stale wrapper object %p read\n", site, object);

    if (object != NULL && emerald_uaf_entries != NULL) {
        for (uint64_t index = 0; index < EMERALD_UAF_QUARANTINE; index++) {
            EmeraldUafEntry *entry = &emerald_uaf_entries[index];

            if (entry->memory == object) {
                fprintf(stderr, "[uaf-hunt] object %p (size %llu) was released at:\n", object, (unsigned long long) entry->size);
                backtrace_symbols_fd(entry->frames, entry->frame_count, 2);
            }
        }
    }

    fprintf(stderr, "[uaf-hunt] stale read happened at:\n");
    backtrace_symbols_fd(now, count, 2);
    fflush(stderr);
    fflush(stdout);
    abort();
}

static int emerald_uaf_quarantine(void *memory, uint64_t size, void *allocation) {
    if (!emerald_uaf_enabled() || memory == NULL || size > EMERALD_UAF_MAX_SIZE) {
        return 0;
    }

    if (emerald_uaf_entries == NULL) {
        emerald_uaf_entries = (EmeraldUafEntry *) calloc(EMERALD_UAF_QUARANTINE, sizeof(EmeraldUafEntry));

        if (emerald_uaf_entries == NULL) {
            return 0;
        }
    }

    EmeraldUafEntry *entry = &emerald_uaf_entries[emerald_uaf_next % EMERALD_UAF_QUARANTINE];
    emerald_uaf_next += 1;

    if (entry->memory != NULL) {
        free(entry->allocation);
    }

    memset(memory, 0xAB, (size_t) size);

    if (size >= sizeof(int32_t)) {
        *((int32_t *) memory) = EMERALD_UAF_SENTINEL;
    }

    entry->memory = memory;
    entry->allocation = allocation;
    entry->size = size;
    entry->frame_count = backtrace(entry->frames, EMERALD_UAF_FRAMES);
    return 1;
}

/* Ends an ownership transaction: returns released headers, inline payloads
   and extensions to their slots while the lock is still held, then frees the
   malloc payloads after unlocking (in batches, under the lock, only when one
   transaction releases very many of them). */
#define EMERALD_FLOW_DEFERRED_FREES 64

static void emerald_flow_unlock_and_free(EmeraldFlowBlock *release_list) {
    void *payloads[EMERALD_FLOW_DEFERRED_FREES];
    size_t payload_count = 0;
    EmeraldFlowBlock *block = release_list;
    int keep_managed = emerald_flow_bootstrap_leak_enabled();

    while (block != NULL) {
        EmeraldFlowBlock *next = emerald_flow_at(block->next_sibling);

        emerald_flow_extended_release_locked(block);

        if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED) && keep_managed) {
            block = next;
            continue;
        }

        if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_EXTERNAL) && EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED)) {
            EmeraldFlowExternal *external = (EmeraldFlowExternal *) block;

            if (!emerald_uaf_quarantine(external->memory, external->size, external->memory)) {
                if (payload_count == EMERALD_FLOW_DEFERRED_FREES) {
                    while (payload_count > 0) {
                        free(payloads[--payload_count]);
                    }
                }
                payloads[payload_count++] = external->memory;
            }
        }

        atomic_store_explicit(&block->meta, 0, memory_order_relaxed);
        emerald_flow_slot_give_locked(block);
        block = next;
    }

    emerald_flow_unlock();

    while (payload_count > 0) {
        free(payloads[--payload_count]);
    }
}

void emerald_flow_owner_enter(void *owner) {
    if (owner == NULL) {
        return;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return;
    }

    emerald_flow_lock();
    if (emerald_flow_find_block_locked(owner) == NULL) {
        emerald_flow_external_new_locked(owner, 0, 0);
    }
    emerald_flow_unlock();
}

void emerald_flow_owner_leave(void *owner) {
    if (owner == NULL) {
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
    EmeraldFlowBlock *block = emerald_flow_find_block_locked(owner);

    if (block != NULL && !EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED) && block->parent == 0) {
        emerald_flow_collect_release_locked(block, &release_list);
    }

    emerald_flow_bond_collect_pending_cycles_locked(bond_release_count_before, &release_list);
    emerald_flow_unlock_and_free(release_list);
}

/* Would linking child under owner close a Root cycle, i.e. is child owner
   itself or one of its ancestors? */
static int emerald_flow_would_cycle(EmeraldFlowBlock *owner, EmeraldFlowBlock *child) {
    if (owner == child) {
        return 1;
    }

    /* A leaf has no descendants, so it cannot be an ancestor of the owner.
       This keeps tail appends to long Root chains O(1). */
    if (child->first_child == 0) {
        return 0;
    }

    /* A parentless child is the top of its tree; it is an ancestor of the
       owner exactly when the owner's tree has it as top. */
    if (child->parent == 0) {
        return emerald_flow_root_top_locked(owner) == child;
    }

    for (EmeraldFlowBlock *current = owner; current != NULL; current = emerald_flow_at(current->parent)) {
        if (current == child) {
            return 1;
        }
    }

    return 0;
}

void emerald_flow_owner_reset(void *owner_memory) {
    if (owner_memory == NULL) {
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
    EmeraldFlowBlock *owner = emerald_flow_find_block_locked(owner_memory);

    if (owner != NULL) {
        emerald_flow_bond_release_owner_edges_locked(owner, &release_list);
        uint32_t child_index = owner->first_child;
        owner->first_child = 0;

        while (child_index != 0) {
            EmeraldFlowBlock *child = emerald_flow_at(child_index);
            child_index = child->next_sibling;
            child->parent = 0;
            child->next_sibling = 0;
            emerald_flow_collect_release_locked(child, &release_list);
        }
    }

    emerald_flow_bond_collect_pending_cycles_locked(bond_release_count_before, &release_list);
    emerald_flow_unlock_and_free(release_list);
}

void *emerald_flow_root_detach(void *owner_memory, void *child_memory) {
    if (owner_memory == NULL || child_memory == NULL) {
        return child_memory;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return child_memory;
    }

    emerald_flow_lock();
    EmeraldFlowBlock *owner = emerald_flow_find_block_locked(owner_memory);
    EmeraldFlowBlock *child = emerald_flow_find_block_locked(child_memory);

    if (owner != NULL && child != NULL && EMERALD_FLOW_HAS(child, EMERALD_FLOW_BONDED)) {
        EmeraldFlowBondEdge *edge = emerald_flow_extended_read(owner)->first_bond_out;

        while (edge != NULL) {
            if (edge->child == child) {
                emerald_flow_bond_unlink_edge_locked(edge);
                free(edge);
                break;
            }

            edge = edge->owner_next;
        }
    } else if (owner != NULL && child != NULL && emerald_flow_at(child->parent) == owner) {
        emerald_flow_detach_from_parent_locked(child);
    }

    emerald_flow_unlock();
    return child_memory;
}

static void emerald_flow_promote_owned_child_locked(EmeraldFlowBlock *previous_owner, EmeraldFlowBlock *next_owner, EmeraldFlowBlock *child) {
    if (previous_owner == NULL || next_owner == NULL || child == NULL) {
        return;
    }

    emerald_flow_detach_from_parent_locked(child);
    EMERALD_FLOW_SET(child, EMERALD_FLOW_BONDED);
    EMERALD_FLOW_CLEAR(child, EMERALD_FLOW_SHARED);
    emerald_flow_extended_write(child)->bond_count = 0;
    emerald_flow_default_chamber.bond_promotion_count += 1;
    emerald_flow_default_chamber.bond_live_count += 1;
    emerald_flow_bond_add_edge_locked(previous_owner, child);
    emerald_flow_bond_add_edge_locked(next_owner, child);
}

/* Adds an ownership edge from owner to child: a counted edge for Bond
   children, a Root link for unowned children, promotion for owned ones. */
static void emerald_flow_adopt_locked(EmeraldFlowBlock *owner, EmeraldFlowBlock *child) {
    if (owner == NULL || child == NULL || !EMERALD_FLOW_HAS(child, EMERALD_FLOW_MANAGED)) {
        return;
    }

    if (EMERALD_FLOW_HAS(child, EMERALD_FLOW_BONDED)) {
        emerald_flow_bond_add_edge_locked(owner, child);
    } else if (emerald_flow_would_cycle(owner, child)) {
        return;
    } else if (child->parent != 0) {
        /* A second field of the same owner is still a distinct lifetime
           edge. Promote it just like a reference from another owner so
           replacing either field cannot free the shared child early. */
        emerald_flow_promote_owned_child_locked(emerald_flow_at(child->parent), owner, child);
    } else {
        emerald_flow_link_child_locked(owner, child);
        emerald_flow_default_chamber.root_adoption_count += 1;
    }
}

void emerald_flow_root_adopt(void *owner_memory, void *child_memory) {
    if (owner_memory == NULL || child_memory == NULL || owner_memory == child_memory) {
        return;
    }
    /* Bootstrap mode keeps every allocation alive until process exit, so
       ownership bookkeeping (registry walks, bond edges, scope tracking)
       is pure overhead; skip it entirely. */
    if (emerald_flow_bootstrap_leak_enabled()) {
        return;
    }

    emerald_flow_lock();
    EmeraldFlowBlock *owner = emerald_flow_find_block_locked(owner_memory);

    if (owner != NULL) {
        emerald_flow_adopt_locked(owner, emerald_flow_find_block_locked(child_memory));
    }

    emerald_flow_unlock();
}

/* A method hands a reference it keeps using (a parameter, `this`, an alias)
   to a call that may adopt it. When the value is an unparented Root, that
   adoption would make the adopting owner its only owner, so a short-lived
   owner such as a callee's stack Local would free it on scope exit. The
   unique Root reference becomes a counted Bond reference instead: the
   adopting owner adds an edge, and the scope that holds the Root still
   releases its count through emerald_flow_root_release. Children of another
   owner are already promoted with an edge per owner by root_adopt, and
   shared, bonded, static and stack values are left untouched. */
void emerald_flow_share_borrowed(void *memory) {
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

    if (block != NULL && EMERALD_FLOW_HAS(block, EMERALD_FLOW_MANAGED) && !EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED) &&
        !EMERALD_FLOW_HAS(block, EMERALD_FLOW_SHARED) && block->parent == 0) {
        emerald_flow_cycle_graph_changed_locked();
        EMERALD_FLOW_SET(block, EMERALD_FLOW_BONDED);
        emerald_flow_extended_write(block)->bond_count = 1;
        emerald_flow_default_chamber.bond_promotion_count += 1;
        emerald_flow_default_chamber.bond_live_count += 1;
    }

    emerald_flow_unlock();
}

void emerald_flow_root_replace(void *owner_memory, void *previous_memory, void *next_memory) {
    if (owner_memory == NULL || previous_memory == next_memory) {
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
    EmeraldFlowBlock *owner = emerald_flow_find_block_locked(owner_memory);

    if (owner != NULL && previous_memory != NULL) {
        EmeraldFlowBlock *previous = emerald_flow_find_block_locked(previous_memory);

        if (previous != NULL && EMERALD_FLOW_HAS(previous, EMERALD_FLOW_BONDED)) {
            emerald_flow_bond_remove_edge_locked(owner, previous, &release_list);
        } else if (previous != NULL && emerald_flow_at(previous->parent) == owner) {
            emerald_flow_detach_from_parent_locked(previous);
            emerald_flow_collect_release_locked(previous, &release_list);
        }
    }

    if (owner != NULL && next_memory != NULL && next_memory != owner_memory) {
        emerald_flow_adopt_locked(owner, emerald_flow_find_block_locked(next_memory));
    }

    emerald_flow_bond_collect_pending_cycles_locked(bond_release_count_before, &release_list);
    emerald_flow_unlock_and_free(release_list);
}

static uint64_t emerald_static_string_address_bucket(const void *memory) {
    uint64_t value = (uint64_t) (uintptr_t) memory;
    value >>= 4;
    value *= 0x9E3779B97F4A7C15ULL;
    return (value >> 50) & (uint64_t) (EMERALD_STATIC_STRING_BUCKET_COUNT - 1);
}

static int emerald_static_string_contains_locked(void *memory) {
    uint64_t low = 0, high = emerald_static_literal_count;
    uintptr_t address = (uintptr_t) memory;
    while (low < high) {
        uint64_t middle = low + (high - low) / 2;
        uintptr_t candidate = (uintptr_t) emerald_static_literal_addresses[middle];
        if (candidate < address) low = middle + 1;
        else high = middle;
    }
    if (low < emerald_static_literal_count &&
        (uintptr_t) emerald_static_literal_addresses[low] == address) return 1;
    EmeraldStaticStringNode *node = emerald_static_string_address_buckets[emerald_static_string_address_bucket(memory)];

    while (node != NULL) {
        if ((void *) &node->value == memory) {
            return 1;
        }

        node = node->address_next;
    }

    return 0;
}

void emerald_flow_root_release(void *memory) {
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

    if (block == NULL) {
        if (!emerald_static_string_contains_locked(memory)) {
            emerald_flow_default_chamber.invalid_release_count += 1;
        }
    } else if (EMERALD_FLOW_HAS(block, EMERALD_FLOW_BONDED)) {
        emerald_flow_bond_release_locked(block, &release_list);
    } else if (block->parent == 0 && !EMERALD_FLOW_HAS(block, EMERALD_FLOW_SHARED)) {
        emerald_flow_collect_release_locked(block, &release_list);
    }

    emerald_flow_bond_collect_pending_cycles_locked(bond_release_count_before, &release_list);
    emerald_flow_unlock_and_free(release_list);
}

uint64_t emerald_flow_root_release_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.root_release_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_root_released_bytes(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.root_released_bytes;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_root_adoption_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.root_adoption_count;
    emerald_flow_unlock();
    return value;
}

uint64_t emerald_flow_root_shared_fallback_count(void) {
    emerald_flow_lock();
    uint64_t value = emerald_flow_default_chamber.root_shared_fallback_count;
    emerald_flow_unlock();
    return value;
}

// Class identity shares the existing Flow metadata; object layouts stay unchanged.
// Inline blocks are found from the payload address alone, so their tag is
// read and written without the chamber lock. Stack objects and malloc
// payloads go through the registry.
void emerald_object_set_class(void *object, int32_t tag) {
    if (object == NULL || tag <= 0 || tag >= (int32_t) EMERALD_FLOW_TAG_LIMIT) {
        fprintf(stderr, "Emerald invalid object class tag\n"); exit(1);
    }
    EmeraldFlowBlock *block = emerald_flow_inline_block_unlocked(object);
    if (block != NULL) {
        EMERALD_FLOW_SET_TAG(block, tag);
        return;
    }
    emerald_flow_lock();
    block = emerald_flow_find_block_locked(object);
    if (block == NULL) {
        block = emerald_flow_external_new_locked(object, 0, 0);
    }
    EMERALD_FLOW_SET_TAG(block, tag);
    emerald_flow_unlock();
}

int32_t emerald_object_class(void *object) {
    EmeraldFlowBlock *block = emerald_flow_inline_block_unlocked(object);
    if (block != NULL) {
        return (int32_t) EMERALD_FLOW_TAG(block);
    }
    emerald_flow_lock();
    block = emerald_flow_find_block_locked(object);
    int32_t tag = block == NULL ? 0 : (int32_t) EMERALD_FLOW_TAG(block);
    emerald_flow_unlock();
    return tag;
}
