#include "emerald_runtime_internal.h"
#include <time.h>
#include <errno.h>
#include <unistd.h>

static int32_t emerald_process_argc = 0;
static char **emerald_process_argv = NULL;

int32_t emerald_time_monotonic_millis(void) {
    static int has_baseline = 0;
    static struct timespec baseline;
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);

    if (!has_baseline) {
        baseline = now;
        has_baseline = 1;
    }

    int64_t delta_ms = (int64_t) (now.tv_sec - baseline.tv_sec) * 1000
        + (int64_t) (now.tv_nsec - baseline.tv_nsec) / 1000000;

    if (delta_ms > INT32_MAX) {
        return INT32_MAX;
    }

    return (int32_t) delta_ms;
}

/* Monotonic clock in nanoseconds from an arbitrary fixed origin. Unlike
   emerald_time_monotonic_millis (kept for ABI compatibility) it does not
   saturate at INT32_MAX and is fine-grained enough for benchmarking. */
int64_t emerald_time_monotonic_nanos(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t) now.tv_sec * INT64_C(1000000000) + (int64_t) now.tv_nsec;
}

/* Wall clock in milliseconds since the Unix epoch (UTC). */
int64_t emerald_time_unix_millis(void) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return (int64_t) now.tv_sec * 1000 + (int64_t) now.tv_nsec / 1000000;
}

/* Offset of the local time zone from UTC, in minutes, at the given instant. */
int64_t emerald_time_local_offset_minutes(int64_t unix_seconds) {
    time_t instant = (time_t) unix_seconds;
    struct tm local;
    struct tm utc;
    if (localtime_r(&instant, &local) == NULL || gmtime_r(&instant, &utc) == NULL) return 0;
    int day_delta = local.tm_year != utc.tm_year ? (local.tm_year > utc.tm_year ? 1 : -1) : local.tm_yday - utc.tm_yday;
    return (int64_t) day_delta * 1440 + (int64_t) (local.tm_hour - utc.tm_hour) * 60 + (local.tm_min - utc.tm_min);
}

void emerald_time_sleep_millis(int64_t millis) {
    if (millis <= 0) return;
    struct timespec request;
    request.tv_sec = (time_t) (millis / 1000);
    request.tv_nsec = (long) (millis % 1000) * 1000000L;
    while (nanosleep(&request, &request) != 0 && errno == EINTR) {
    }
}

/* xorshift64* generator, lazily seeded from the clock and the process id.
   Returns a non-negative 63-bit value. */
int64_t emerald_random_next(void) {
    static uint64_t state = 0;
    if (state == 0) {
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        state = ((uint64_t) now.tv_sec * UINT64_C(1000000007)) ^ ((uint64_t) now.tv_nsec << 20) ^ ((uint64_t) getpid() << 40) ^ UINT64_C(0x9E3779B97F4A7C15);
        if (state == 0) state = UINT64_C(0x2545F4914F6CDD1D);
    }
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    return (int64_t) ((state * UINT64_C(0x2545F4914F6CDD1D)) >> 1);
}

EmeraldString *emerald_env_get(EmeraldString *name) {
    const char *native = emerald_runtime_native_cstr(name);
    const char *value = native == NULL ? NULL : getenv(native);
    return emerald_string_from_cstr(value == NULL ? "" : value);
}

EmeraldString *emerald_env_get_or(EmeraldString *name, EmeraldString *fallback) {
    const char *native = emerald_runtime_native_cstr(name);
    const char *value = native == NULL ? NULL : getenv(native);

    if (value == NULL) {
        return fallback == NULL ? emerald_string_from_cstr("") : fallback;
    }

    return emerald_string_from_cstr(value);
}

int32_t emerald_env_has(EmeraldString *name) {
    const char *native = emerald_runtime_native_cstr(name);
    return native == NULL || getenv(native) == NULL ? 0 : 1;
}

EmeraldString *emerald_env_current_directory(void) {
    return emerald_path_current();
}

EmeraldList *emerald_env_args(void) {
    return emerald_process_args();
}

void emerald_process_set_args(int32_t argc, char **argv) {
    emerald_process_argc = argc;
    emerald_process_argv = argv;
}

EmeraldString *emerald_process_command(void) {
    if (emerald_process_argc > 0 && emerald_process_argv != NULL && emerald_process_argv[0] != NULL) {
        return emerald_string_from_cstr(emerald_process_argv[0]);
    }

#if defined(_WIN32)
    return emerald_string_from_cstr(GetCommandLineA());
#else
    char buffer[4096];
    ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);

    if (length < 0) {
        return emerald_string_from_cstr("");
    }

    buffer[length] = 0;
    return emerald_string_from_cstr(buffer);
#endif
}

EmeraldList *emerald_process_args(void) {
    EmeraldList *values = emerald_list_new_typed(EMERALD_LIST_REFERENCE, sizeof(void *));
    int32_t index = 1;

    while (index < emerald_process_argc) {
        const char *argument = emerald_process_argv == NULL ? NULL : emerald_process_argv[index];
        emerald_list_add(values, emerald_string_from_cstr(argument == NULL ? "" : argument));
        index++;
    }

    return values;
}

void emerald_process_exit(int32_t code) {
    fflush(stdout);
    emerald_flow_shutdown();
    exit(code);
}

EmeraldString *emerald_system_os(void) {
#if defined(_WIN32)
    return emerald_string_from_cstr("windows");
#elif defined(__APPLE__)
    return emerald_string_from_cstr("macos");
#elif defined(__linux__)
    return emerald_string_from_cstr("linux");
#elif defined(__FreeBSD__)
    return emerald_string_from_cstr("freebsd");
#else
    return emerald_string_from_cstr("unknown");
#endif
}

int32_t emerald_system_is_windows(void) {
#if defined(_WIN32)
    return 1;
#else
    return 0;
#endif
}

int32_t emerald_system_is_linux(void) {
#if defined(__linux__)
    return 1;
#else
    return 0;
#endif
}

EmeraldString *emerald_system_line_separator(void) {
#if defined(_WIN32)
    return emerald_string_from_cstr("\r\n");
#else
    return emerald_string_from_cstr("\n");
#endif
}

EmeraldString *emerald_system_path_separator(void) {
#if defined(_WIN32)
    return emerald_string_from_cstr(";");
#else
    return emerald_string_from_cstr(":");
#endif
}

EmeraldString *emerald_system_directory_separator(void) {
#if defined(_WIN32)
    return emerald_string_from_cstr("\\");
#else
    return emerald_string_from_cstr("/");
#endif
}

EmeraldString *emerald_system_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return emerald_string_from_cstr("x86_64");
#elif defined(__aarch64__) || defined(_M_ARM64)
    return emerald_string_from_cstr("aarch64");
#elif defined(__i386__) || defined(_M_IX86)
    return emerald_string_from_cstr("x86");
#else
    return emerald_string_from_cstr("unknown");
#endif
}

int32_t emerald_system_processor_count(void) {
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return (int32_t) info.dwNumberOfProcessors;
#elif defined(_SC_NPROCESSORS_ONLN)
    long count = sysconf(_SC_NPROCESSORS_ONLN);
    return count > 0 ? (int32_t) count : 1;
#else
    return 1;
#endif
}

EmeraldString *emerald_system_user_name(void) {
#if defined(_WIN32)
    char buffer[256];
    DWORD size = sizeof(buffer);

    if (GetUserNameA(buffer, &size)) {
        return emerald_string_from_cstr(buffer);
    }

    return emerald_env_get(emerald_string_from_cstr("USERNAME"));
#else
    const char *value = getenv("USER");

    if (value != NULL) {
        return emerald_string_from_cstr(value);
    }

    struct passwd *entry = getpwuid(getuid());
    return emerald_string_from_cstr(entry == NULL ? "" : entry->pw_name);
#endif
}

EmeraldString *emerald_system_host_name(void) {
    char buffer[256];

#if defined(_WIN32)
    DWORD size = sizeof(buffer);

    if (!GetComputerNameA(buffer, &size)) {
        return emerald_string_from_cstr("");
    }
#else
    if (gethostname(buffer, sizeof(buffer)) != 0) {
        return emerald_string_from_cstr("");
    }
#endif

    buffer[sizeof(buffer) - 1] = 0;
    return emerald_string_from_cstr(buffer);
}

EmeraldString *emerald_system_home_directory(void) {
#if defined(_WIN32)
    const char *value = getenv("USERPROFILE");
#else
    const char *value = getenv("HOME");
#endif

    return emerald_string_from_cstr(value == NULL ? "" : value);
}

EmeraldString *emerald_system_temp_directory(void) {
#if defined(_WIN32)
    const char *value = getenv("TEMP");
#else
    const char *value = getenv("TMPDIR");
#endif

    return emerald_string_from_cstr(value == NULL ? "/tmp" : value);
}
