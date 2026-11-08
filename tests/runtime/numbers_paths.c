#include "emerald_runtime.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static void dies(int operation) {
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        switch (operation) {
            case 0: emerald_int64_add(INT64_MAX, 1); break;
            case 1: emerald_int64_sub(INT64_MIN, 1); break;
            case 2: emerald_int64_mul(INT64_MAX, 2); break;
            case 3: emerald_int64_div(INT64_MIN, -1); break;
            case 4: emerald_int64_neg(INT64_MIN); break;
            case 5: emerald_int64_div(1, 0); break;
            case 6: emerald_int64_rem(1, 0); break;
            case 7: emerald_int64_to_int32_checked(INT64_C(4000000000)); break;
            case 8: emerald_string_to_int64(emerald_string_from_cstr("9223372036854775808")); break;
            case 9: emerald_float64_to_int(0x1p63); break;
            case 10: emerald_string_to_int64(emerald_string_from_cstr("42x")); break;
        }
        _exit(99);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
}

static void join(const char *left, const char *right, const char *expected) {
    EmeraldString *a = emerald_string_from_cstr(left);
    EmeraldString *b = emerald_string_from_cstr(right);
    EmeraldString *path = emerald_path_join(a, b);
    assert(path->length == strlen(expected));
    assert(!memcmp(path->bytes, expected, path->length));
    hyperalloc_flow_root_release(path);
    hyperalloc_flow_root_release(a);
    hyperalloc_flow_root_release(b);
}

int main(void) {
    hyperalloc_flow_init();
    assert(emerald_int64_add(INT64_C(2000000000), INT64_C(2000000000)) == INT64_C(4000000000));
    assert(emerald_int64_sub(INT64_MIN, 0) == INT64_MIN);
    assert(emerald_int64_mul(INT64_MIN, 1) == INT64_MIN);
    assert(emerald_int64_div(-9, 2) == -4);
    assert(emerald_int64_rem(INT64_MIN, -1) == 0);
    EmeraldString *maximum = emerald_int64_to_string(INT64_MAX);
    EmeraldString *minimum = emerald_int64_to_string(INT64_MIN);
    assert(emerald_string_to_int64(maximum) == INT64_MAX);
    assert(emerald_string_to_int64(minimum) == INT64_MIN);
    hyperalloc_flow_root_release(maximum);
    hyperalloc_flow_root_release(minimum);
    assert(emerald_float64_to_int(-3.75) == -3);
    assert(emerald_float64_to_int(-0x1p63) == INT64_MIN);
    join("/", "stdlib", "/stdlib");
    join("/tmp/", "module.ems", "/tmp/module.ems");
    join("/tmp", "module.ems", "/tmp/module.ems");
    join("", "module.ems", "module.ems");
    void *object = hyperalloc_flow_alloc(8);
    emerald_object_set_class(object, 42);
    assert(emerald_object_class(object) == 42);
    hyperalloc_flow_root_release(object);
    int local = 0;
    emerald_object_set_class(&local, 7);
    emerald_object_set_class(&local, 8);
    assert(emerald_object_class(&local) == 8);
    hyperalloc_flow_owner_leave(&local);
    assert(emerald_object_class(&local) == 0);
    for (int operation = 0; operation <= 10; operation++) dies(operation);
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
    puts("numbers-paths-tests-ok");
}
