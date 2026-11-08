/* Observe live allocations before shutdown can conceal temporary leaks. */
#define hyperalloc_flow_shutdown emerald_memory_test_real_shutdown
#include "../../../runtime/emerald_runtime.c"
#undef hyperalloc_flow_shutdown

void hyperalloc_flow_shutdown(void) {
    uint64_t live = hyperalloc_flow_allocation_count();
    uint64_t invalid = hyperalloc_flow_invalid_release_count();
    fprintf(stderr, "flow-memory-final-live=%llu invalid=%llu\n",
        (unsigned long long)live, (unsigned long long)invalid);
    if (live != 0 || invalid != 0) {
        exit(90);
    }
    emerald_memory_test_real_shutdown();
}
