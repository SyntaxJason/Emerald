#define _POSIX_C_SOURCE 200809L
#include "emerald_runtime.h"
#include <assert.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* Non-Flow runtime library: number formatting and parsing, substring search,
   buffered stdout, file lines, NUL-safe native names, List bounds, clocks. */

static EmeraldString *text(const char *value) {
    return emerald_string_from_cstr(value);
}

static EmeraldString *bytes(const char *value, uint64_t length) {
    return emerald_string_new((const uint8_t *) value, length);
}

static int same(EmeraldString *value, const char *expected) {
    size_t length = strlen(expected);
    return value != NULL && value->length == length && memcmp(value->bytes, expected, length) == 0;
}

static void expect_and_release(EmeraldString *value, const char *expected) {
    if (!same(value, expected)) {
        fprintf(stderr, "expected '%s', got '%.*s'\n", expected, (int) value->length, (const char *) value->bytes);
        abort();
    }
    hyperalloc_flow_root_release(value);
}

static void int_formatting(void) {
    const int64_t values[] = {0, 1, 9, 10, 99, 100, 101, -1, -9, -10, -99, -100, 123456789, -987654321,
        INT32_MAX, INT32_MIN, INT64_MAX, INT64_MIN, INT64_MAX - 1, INT64_MIN + 1, 1000000000000000000LL};
    char expected[32];
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        snprintf(expected, sizeof(expected), "%lld", (long long) values[i]);
        expect_and_release(emerald_int64_to_string(values[i]), expected);
    }
    uint64_t state = 88172645463325252ULL;
    for (int i = 0; i < 100000; i++) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17;
        int64_t value = (int64_t) (state >> (state & 63));
        if (i & 1) value = -value;
        snprintf(expected, sizeof(expected), "%lld", (long long) value);
        expect_and_release(emerald_int64_to_string(value), expected);
    }
    expect_and_release(emerald_int_to_string(INT32_MIN), "-2147483648");
    expect_and_release(emerald_int_to_string(42), "42");
}

static void int_parsing(void) {
    EmeraldString *values[] = {text("0"), text("-0"), text("007"), text("-9223372036854775808"),
        text("9223372036854775807"), text("42")};
    const int64_t expected[] = {0, 0, 7, INT64_MIN, INT64_MAX, 42};
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
        assert(emerald_string_to_int64(values[i]) == expected[i]);
        hyperalloc_flow_root_release(values[i]);
    }
}

static void float_formatting(void) {
    expect_and_release(emerald_float64_to_string(0.1), "0.1");
    expect_and_release(emerald_float64_to_string(1.0), "1");
    expect_and_release(emerald_float64_to_string(-0.0), "-0");
    expect_and_release(emerald_float64_to_string(62.5), "62.5");
    expect_and_release(emerald_float64_to_string(-3.75), "-3.75");
    expect_and_release(emerald_float64_to_string(0.30000000000000004), "0.30000000000000004");
    expect_and_release(emerald_float64_to_string(1.0 / 3.0), "0.3333333333333333");
    expect_and_release(emerald_float64_to_string(1e15), "1000000000000000");
    expect_and_release(emerald_float64_to_string(1e16), "10000000000000000");
    expect_and_release(emerald_float64_to_string(123456789012345678.0), "1.2345678901234568e+17");
    expect_and_release(emerald_float64_to_string(1e20), "1e+20");
    expect_and_release(emerald_float64_to_string(1e-20), "1e-20");
    expect_and_release(emerald_float64_to_string(0.0001), "0.0001");
    expect_and_release(emerald_float64_to_string(0.00001), "1e-05");
    expect_and_release(emerald_float64_to_string(INFINITY), "inf");
    expect_and_release(emerald_float64_to_string(-INFINITY), "-inf");
    EmeraldString *nan_text = emerald_float64_to_string(NAN);
    assert(same(nan_text, "nan") || same(nan_text, "-nan"));
    hyperalloc_flow_root_release(nan_text);
    /* Every finite value reads back exactly and is never longer than %.17g. */
    uint64_t state = 0x9E3779B97F4A7C15ULL;
    char longest[64];
    for (int i = 0; i < 100000; i++) {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17;
        double value;
        if (i % 3 == 0) {
            memcpy(&value, &state, sizeof(value));
        } else {
            value = (double) (state % 1000000) / (double) (1 + (state >> 40) % 1000);
        }
        if (!isfinite(value)) continue;
        EmeraldString *shortest = emerald_float64_to_string(value);
        int length = snprintf(longest, sizeof(longest), "%.17g", value);
        assert(shortest->length <= (uint64_t) length);
        assert(strtod((const char *) shortest->bytes, NULL) == value);
        assert((strchr((const char *) shortest->bytes, 'e') != NULL) == (strchr(longest, 'e') != NULL));
        hyperalloc_flow_root_release(shortest);
    }
}

static void searching(void) {
    EmeraldString *haystack = text("aaab-xyz-aab-");
    EmeraldString *needles[] = {text("aab"), text("-"), text(""), text("aaab-xyz-aab-!"), text("zz"), text("b-")};
    assert(emerald_string_index_of(haystack, needles[0]) == 1);
    assert(emerald_string_index_of(haystack, needles[1]) == 4);
    assert(emerald_string_index_of(haystack, needles[2]) == 0);
    assert(emerald_string_index_of(haystack, needles[3]) == -1);
    assert(emerald_string_index_of(haystack, needles[4]) == -1);
    assert(emerald_string_index_of(haystack, needles[5]) == 3);
    assert(emerald_string_contains(haystack, needles[0]) && emerald_string_contains(haystack, needles[2]));
    assert(!emerald_string_contains(haystack, needles[3]) && !emerald_string_contains(haystack, needles[4]));
    EmeraldString *empty = text("");
    EmeraldString *x = text("<>");
    expect_and_release(emerald_string_replace(haystack, needles[0], x), "a<>-xyz-<>-");
    expect_and_release(emerald_string_replace(haystack, needles[1], empty), "aaabxyzaab");
    expect_and_release(emerald_string_replace(haystack, needles[4], x), "aaab-xyz-aab-");
    expect_and_release(emerald_string_replace(haystack, needles[2], x), "aaab-xyz-aab-");
    EmeraldString *run = text("aaaaa");
    EmeraldString *pair = text("aa");
    expect_and_release(emerald_string_replace(run, pair, needles[1]), "--a");
    EmeraldList *parts = emerald_string_split(haystack, needles[1]);
    assert(emerald_list_length(parts) == 4);
    assert(same(emerald_list_get(parts, 0), "aaab") && same(emerald_list_get(parts, 1), "xyz"));
    assert(same(emerald_list_get(parts, 2), "aab") && same(emerald_list_get(parts, 3), ""));
    hyperalloc_flow_root_release(parts);
    parts = emerald_string_split(run, pair);
    assert(emerald_list_length(parts) == 3 && same(emerald_list_get(parts, 2), "a"));
    hyperalloc_flow_root_release(parts);
    /* Interior NUL bytes are ordinary data for search and split. */
    EmeraldString *binary = bytes("a\0b\0c", 5);
    EmeraldString *nul = bytes("\0", 1);
    EmeraldString *nul_c = bytes("\0c", 2);
    assert(emerald_string_index_of(binary, nul_c) == 3);
    parts = emerald_string_split(binary, nul);
    assert(emerald_list_length(parts) == 3 && same(emerald_list_get(parts, 1), "b"));
    hyperalloc_flow_root_release(parts);
    EmeraldString *replaced = emerald_string_replace(binary, nul, x);
    assert(same(replaced, "a<>b<>c"));
    hyperalloc_flow_root_release(replaced);
    EmeraldString *all[] = {haystack, empty, x, run, pair, binary, nul, nul_c};
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) hyperalloc_flow_root_release(all[i]);
    for (size_t i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) hyperalloc_flow_root_release(needles[i]);
}

static void write_file(const char *path, const char *content, size_t length) {
    FILE *file = fopen(path, "wb");
    assert(file != NULL);
    assert(fwrite(content, 1, length, file) == length);
    fclose(file);
}

static void expect_lines(const char *content, const char *const *lines, int count) {
    const char *path_text = "/tmp/emerald-runtime-library-lines.txt";
    if (content != NULL) write_file(path_text, content, strlen(content)); else remove(path_text);
    EmeraldString *path = text(path_text);
    uint64_t live = hyperalloc_flow_allocation_count();
    EmeraldList *list = emerald_file_read_lines(path);
    assert(emerald_list_length(list) == count);
    for (int i = 0; i < count; i++) assert(same(emerald_list_get(list, i), lines[i]));
    hyperalloc_flow_root_release(list);
    /* The whole-file text read for splitting is released, not leaked. */
    assert(hyperalloc_flow_allocation_count() == live);
    hyperalloc_flow_root_release(path);
    remove(path_text);
}

static void files(void) {
    const char *crlf[] = {"a", "b", "", "c"};
    expect_lines("a\r\nb\n\nc\n", crlf, 4);
    expect_lines("a\r\nb\n\nc", crlf, 4);
    const char *one[] = {""};
    expect_lines("\n", one, 1);
    expect_lines("", NULL, 0);
    expect_lines(NULL, NULL, 0);
    /* readText reads regular files straight into the String. */
    enum { SIZE = 300000 };
    char *content = malloc(SIZE);
    assert(content != NULL);
    for (int i = 0; i < SIZE; i++) content[i] = (char) ('a' + i % 26);
    content[1234] = 0;
    write_file("/tmp/emerald-runtime-library-big.txt", content, SIZE);
    EmeraldString *path = text("/tmp/emerald-runtime-library-big.txt");
    EmeraldString *read = emerald_file_read_text(path);
    assert(read->length == SIZE && memcmp(read->bytes, content, SIZE) == 0 && read->bytes[SIZE] == 0);
    assert(emerald_file_size(path) == SIZE);
    hyperalloc_flow_root_release(read);
    assert(emerald_file_delete(path) == 1);
    hyperalloc_flow_root_release(path);
    free(content);
    /* Pseudo files report size 0 but still have content. */
    path = text("/proc/self/status");
    read = emerald_file_read_text(path);
    assert(read->length > 0 && memcmp(read->bytes, "Name:", 5) == 0);
    hyperalloc_flow_root_release(read);
    hyperalloc_flow_root_release(path);
}

static void native_names(void) {
    /* An interior NUL must not silently name the prefix before it. */
    EmeraldString *directory = bytes("/tmp\0/ignored", 13);
    assert(emerald_directory_exists(directory) == 0);
    assert(emerald_file_exists(directory) == 0);
    EmeraldString *read = emerald_file_read_text(directory);
    assert(read->length == 0);
    hyperalloc_flow_root_release(read);
    EmeraldString *file = bytes("/tmp/emerald-runtime-library-nul\0.txt", 37);
    EmeraldString *content = text("data");
    emerald_file_write_text(file, content);
    EmeraldString *prefix = text("/tmp/emerald-runtime-library-nul");
    assert(emerald_file_exists(prefix) == 0);
    EmeraldString *variable = bytes("PATH\0X", 6);
    EmeraldString *fallback = text("fallback");
    assert(emerald_env_has(variable) == 0);
    read = emerald_env_get(variable);
    assert(read->length == 0);
    hyperalloc_flow_root_release(read);
    assert(emerald_env_get_or(variable, fallback) == fallback);
    EmeraldString *path = text("PATH");
    assert(emerald_env_has(path) == 1);
    EmeraldString *all[] = {directory, file, content, prefix, variable, fallback, path};
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); i++) hyperalloc_flow_root_release(all[i]);
}

static void paths(void) {
    EmeraldString *values[] = {text("/a/b.c/name.tar.gz"), text("dir/"), text("plain"), text(".hidden"),
        text("a.b/c"), text(""), text("/"), bytes("x\0y/z.q", 7)};
    expect_and_release(emerald_path_file_name(values[0]), "name.tar.gz");
    expect_and_release(emerald_path_extension(values[0]), ".gz");
    expect_and_release(emerald_path_parent(values[0]), "/a/b.c");
    expect_and_release(emerald_path_file_name(values[1]), "");
    expect_and_release(emerald_path_parent(values[1]), "dir");
    expect_and_release(emerald_path_extension(values[2]), "");
    expect_and_release(emerald_path_parent(values[2]), "");
    expect_and_release(emerald_path_extension(values[3]), ".hidden");
    expect_and_release(emerald_path_extension(values[4]), "");
    expect_and_release(emerald_path_parent(values[6]), "/");
    expect_and_release(emerald_path_join(values[5], values[2]), "plain");
    expect_and_release(emerald_path_join(values[1], values[2]), "dir/plain");
    expect_and_release(emerald_path_join(values[2], values[3]), "plain/.hidden");
    expect_and_release(emerald_path_extension(values[7]), ".q");
    EmeraldString *joined = emerald_path_join(values[7], values[2]);
    assert(joined->length == 13 && memcmp(joined->bytes, "x\0y/z.q/plain", 13) == 0);
    hyperalloc_flow_root_release(joined);
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) hyperalloc_flow_root_release(values[i]);
}

static void clocks(void) {
    int64_t first = emerald_time_monotonic_nanos();
    struct timespec pause = {0, 2000000};
    nanosleep(&pause, NULL);
    int64_t second = emerald_time_monotonic_nanos();
    assert(second - first >= 2000000);
    assert(emerald_time_monotonic_millis() >= 0);
}

static void hashing_and_strings(void) {
    assert(emerald_hash_int64(1) != emerald_hash_int64(2));
    assert(emerald_hash_int64(INT64_MIN) >= 0 && emerald_hash_int64(-1) >= 0);
    assert(emerald_hash_float64(0.0) == emerald_hash_float64(-0.0));
    assert(emerald_hash_float64(0.0 / 0.0) == emerald_hash_float64(-(0.0 / 0.0)));
    assert(emerald_hash_float64(1.5) >= 0);
    assert(emerald_time_unix_millis() > INT64_C(1600000000000));
    emerald_time_sleep_millis(1);
    assert(emerald_random_next() >= 0);
    EmeraldString *text = emerald_string_from_cstr("abcabc");
    EmeraldString *needle = emerald_string_from_cstr("bc");
    EmeraldString *other = emerald_string_from_cstr("abd");
    assert(emerald_string_last_index_of(text, needle) == 4);
    assert(emerald_string_compare(text, other) < 0 && emerald_string_compare(other, text) > 0 && emerald_string_compare(text, text) == 0);
    expect_and_release(emerald_string_repeat(needle, 3), "bcbcbc");
    EmeraldString *blank = emerald_string_from_cstr(" \t");
    assert(emerald_string_is_blank(blank) == 1);
    EmeraldList *parts = emerald_list_new();
    emerald_list_add(parts, emerald_string_from_cstr("x"));
    emerald_list_add(parts, emerald_string_from_cstr("y"));
    EmeraldString *separator = emerald_string_from_cstr(", ");
    expect_and_release(emerald_string_join(parts, separator), "x, y");
    hyperalloc_flow_root_release(separator);
    hyperalloc_flow_root_release(parts);
    hyperalloc_flow_root_release(blank);
    hyperalloc_flow_root_release(other);
    hyperalloc_flow_root_release(needle);
    hyperalloc_flow_root_release(text);
}

/* Runs operation in a child whose stdout and stderr share one pipe (stdout is
   therefore not a terminal and fully buffered). Returns the combined output. */
static char *capture(void (*operation)(int), int argument, int *status) {
    int pipe_ends[2];
    assert(pipe(pipe_ends) == 0);
    fflush(stdout);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        dup2(pipe_ends[1], 1);
        dup2(pipe_ends[1], 2);
        close(pipe_ends[0]);
        close(pipe_ends[1]);
        operation(argument);
        exit(0);
    }
    close(pipe_ends[1]);
    static char output[4096];
    size_t length = 0;
    ssize_t read_count;
    while ((read_count = read(pipe_ends[0], output + length, sizeof(output) - 1 - length)) > 0) length += (size_t) read_count;
    output[length] = 0;
    close(pipe_ends[0]);
    assert(waitpid(child, status, 0) == child);
    return output;
}

static void print_then_fail(int operation) {
    hyperalloc_flow_init();
    EmeraldString *before = text("before");
    emerald_println(before);
    emerald_print(before);
    emerald_println(NULL);
    EmeraldList *list = emerald_list_new_typed(0, sizeof(void *));
    emerald_list_add(list, (void *) (uintptr_t) 5);
    struct { int64_t a, b; } inline_value = {1, 2};
    EmeraldList *inline_list = emerald_list_new_typed(2, sizeof(inline_value));
    emerald_list_add(inline_list, &inline_value);
    switch (operation) {
        case 0: hyperalloc_flow_shutdown(); exit(0);
        case 1: emerald_int64_div(1, 0); break;
        case 2: emerald_panic(text("stop")); break;
        case 3: emerald_list_get(list, 1); break;
        case 4: emerald_list_get(list, -1); break;
        case 5: emerald_list_set(list, 3, NULL); break;
        case 6: emerald_list_remove_at(list, 1); break;
        case 7: emerald_list_get_into(inline_list, 2, &inline_value); break;
        case 8: emerald_list_remove_at_into(inline_list, -2, &inline_value); break;
        case 9: emerald_console_error_line(before); emerald_println(before); hyperalloc_flow_shutdown(); exit(0);
        case 10: emerald_string_to_int64(text(" 42")); break;
        case 11: emerald_string_to_int64(text("+42")); break;
        case 12: emerald_string_to_int64(text("42 ")); break;
        case 13: emerald_string_to_int64(text("-")); break;
        case 14: emerald_string_to_int64(bytes("4\0" "2", 3)); break;
        case 15: emerald_string_to_int64(text("-9223372036854775809")); break;
        case 16: emerald_process_exit(3); break;
    }
    _exit(99);
}

static void expect_output(int operation, const char *expected, int exit_code, int signal_number) {
    int status;
    char *output = capture(print_then_fail, operation, &status);
    if (strcmp(output, expected) != 0) {
        fprintf(stderr, "operation %d: unexpected output:\n%s\n", operation, output);
        abort();
    }
    if (signal_number != 0) {
        assert(WIFSIGNALED(status) && WTERMSIG(status) == signal_number);
    } else {
        assert(WIFEXITED(status) && WEXITSTATUS(status) == exit_code);
    }
}

static void stdout_and_failures(void) {
    const char *lines = "before\nbefore\n";
    char expected[512];
    expect_output(0, lines, 0, 0);
    snprintf(expected, sizeof(expected), "%sEmerald numeric error: division by zero\n", lines);
    expect_output(1, expected, 1, 0);
    snprintf(expected, sizeof(expected), "%sEmerald panic: stop\n", lines);
    expect_output(2, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.get index 1 out of bounds for length 1\n", lines);
    expect_output(3, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.get index -1 out of bounds for length 1\n", lines);
    expect_output(4, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.set index 3 out of bounds for length 1\n", lines);
    expect_output(5, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.removeAt index 1 out of bounds for length 1\n", lines);
    expect_output(6, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.get index 2 out of bounds for length 1\n", lines);
    expect_output(7, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sEmerald panic: List.removeAt index -2 out of bounds for length 1\n", lines);
    expect_output(8, expected, 0, SIGABRT);
    snprintf(expected, sizeof(expected), "%sbefore\nbefore\n", lines);
    expect_output(9, expected, 0, 0);
    snprintf(expected, sizeof(expected), "%sEmerald numeric error: invalid Int text\n", lines);
    for (int operation = 10; operation <= 14; operation++) expect_output(operation, expected, 1, 0);
    snprintf(expected, sizeof(expected), "%sEmerald numeric error: Int overflow in conversion\n", lines);
    expect_output(15, expected, 1, 0);
    expect_output(16, lines, 3, 0);
}

int main(void) {
    hyperalloc_flow_init();
    int_formatting();
    int_parsing();
    float_formatting();
    searching();
    files();
    native_names();
    paths();
    clocks();
    hashing_and_strings();
    assert(hyperalloc_flow_allocation_count() == 0);
    assert(hyperalloc_flow_invalid_release_count() == 0);
    hyperalloc_flow_shutdown();
    stdout_and_failures();
    puts("runtime-library-tests-ok");
    return 0;
}
