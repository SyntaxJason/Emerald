#include "emerald_runtime.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Point { int64_t x, y, z, w; } Point;

/* Exercise public allocation/container lifetimes with varying payload sizes.
   The same executable and inputs are used for both runtime revisions. */
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    uint64_t count = strtoull(argv[2], NULL, 10);
    uint64_t bytes = strtoull(argv[3], NULL, 10);
    if (bytes < sizeof(Point) || count > 2000000) return 2;
    hyperalloc_flow_init();
    int64_t sum = 0;
    if (strcmp(argv[1], "retained") == 0) {
        EmeraldList *list = emerald_list_new();
        for (uint64_t i = 0; i < count; i++) {
            Point *p = hyperalloc_flow_alloc(bytes);
            p->x = (int64_t) i;
            p->y = 2; p->z = 3; p->w = 4;
            hyperalloc_flow_owner_enter(p);
            emerald_list_add(list, p);
        }
        for (uint64_t i = 0; i < count; i++) {
            Point *p = emerald_list_get(list, (int32_t) i);
            sum += p->x;
        }
        hyperalloc_flow_root_release(list);
    } else if (strcmp(argv[1], "transient") == 0) {
        for (uint64_t i = 0; i < count; i++) {
            Point *p = hyperalloc_flow_alloc(bytes);
            p->x = (int64_t) i;
            hyperalloc_flow_owner_enter(p);
            sum += p->x;
            hyperalloc_flow_root_release(p);
        }
    } else return 2;
    if (sum != (int64_t) (count * (count - 1) / 2) ||
        hyperalloc_flow_allocation_count() != 0 || hyperalloc_flow_invalid_release_count() != 0) return 1;
    printf("sum=%lld live=0 invalid=0\n", (long long) sum);
    hyperalloc_flow_shutdown();
    return 0;
}
