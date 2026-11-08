#include "emerald_runtime_internal.h"

/* stdout is buffered instead of flushed after every print. When it is not a
   terminal it gets a 64 KiB buffer; on a terminal it stays line buffered and
   print/println still flush, so prompts and interactive output appear as
   before (and Windows, which treats _IOLBF as full buffering, behaves the
   same). Pending output is flushed at exit, before reading stdin, before any
   runtime diagnostic is written to stderr, and before panics and aborts. */
static int emerald_stdout_mode = 0; /* 0 = not configured, 1 = buffered, 2 = terminal */
static char emerald_stdout_buffer[1 << 16];

static void emerald_stdout_flush_at_exit(void) {
    fflush(stdout);
}

static int emerald_stdout_is_terminal(void) {
    if (emerald_stdout_mode == 0) {
        if (isatty(fileno(stdout))) {
            setvbuf(stdout, NULL, _IOLBF, BUFSIZ);
            emerald_stdout_mode = 2;
        } else {
            setvbuf(stdout, emerald_stdout_buffer, _IOFBF, sizeof(emerald_stdout_buffer));
            emerald_stdout_mode = 1;
        }

        atexit(emerald_stdout_flush_at_exit);
    }

    return emerald_stdout_mode == 2;
}

void emerald_runtime_flush_stdout(void) {
    fflush(stdout);
}

void emerald_print(EmeraldString *value) {
    if (value == NULL) {
        return;
    }

    int terminal = emerald_stdout_is_terminal();

    if (value->length > 0) {
        fwrite(value->bytes, 1, (size_t) value->length, stdout);
    }

    if (terminal) {
        fflush(stdout);
    }
}

void emerald_println(EmeraldString *value) {
    int terminal = emerald_stdout_is_terminal();

    if (value != NULL && value->length > 0) {
        fwrite(value->bytes, 1, (size_t) value->length, stdout);
    }

    fputc('\n', stdout);

    if (terminal) {
        fflush(stdout);
    }
}

void emerald_panic(EmeraldString *message) {
    fflush(stdout);
    fputs("Emerald panic: ", stderr);

    if (message != NULL && message->length > 0) {
        fwrite(message->bytes, 1, (size_t) message->length, stderr);
    }

    fputc('\n', stderr);
    emerald_flow_root_release(message);
    emerald_flow_shutdown();
    abort();
}


const char *emerald_runtime_cstr(EmeraldString *value) {
    if (value == NULL || value->bytes == NULL) {
        return "";
    }

    return (const char *) value->bytes;
}

/* Filesystem, environment and socket calls take NUL-terminated names. A
   String with an interior NUL byte would silently name a different (shorter)
   path there, so this returns NULL and callers fail the operation instead. */
const char *emerald_runtime_native_cstr(EmeraldString *value) {
    if (value == NULL || value->bytes == NULL) {
        return "";
    }

    if (value->length > 0 && memchr(value->bytes, 0, (size_t) value->length) != NULL) {
        return NULL;
    }

    return (const char *) value->bytes;
}

EmeraldString *emerald_runtime_string_from_owned_buffer(char *buffer, size_t length) {
    if (buffer == NULL) {
        return emerald_string_from_cstr("");
    }

    EmeraldString *value = emerald_string_new((const uint8_t *) buffer, (uint64_t) length);
    free(buffer);
    return value;
}

int emerald_runtime_socket_ready(void) {
#if defined(_WIN32)
    static int initialized = 0;
    static int failed = 0;

    if (initialized) {
        return failed ? 0 : 1;
    }

    WSADATA data;
    initialized = 1;

    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
        failed = 1;
        return 0;
    }

    return 1;
#else
    return 1;
#endif
}

void emerald_console_error_line(EmeraldString *value) {
    fflush(stdout);

    if (value != NULL && value->length > 0) {
        fwrite(value->bytes, 1, (size_t) value->length, stderr);
    }

    fputc('\n', stderr);
    fflush(stderr);
}

EmeraldString *emerald_console_read_line(void) {
    char *line = NULL;
    size_t capacity = 0;

    fflush(stdout);

#if defined(_WIN32)
    char buffer[4096];

    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return emerald_string_from_cstr("");
    }

    size_t length = strlen(buffer);

    while (length > 0 && (buffer[length - 1] == '\n' || buffer[length - 1] == '\r')) {
        length--;
    }

    return emerald_string_new((const uint8_t *) buffer, (uint64_t) length);
#else
    ssize_t read = getline(&line, &capacity, stdin);

    if (read < 0) {
        free(line);
        return emerald_string_from_cstr("");
    }

    size_t length = (size_t) read;

    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
        length--;
    }

    return emerald_runtime_string_from_owned_buffer(line, length);
#endif
}

int32_t emerald_file_exists(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    struct stat info;
    return native != NULL && stat(native, &info) == 0 ? 1 : 0;
}

int32_t emerald_file_is_file(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    struct stat info;

    if (native == NULL || stat(native, &info) != 0) {
        return 0;
    }

    return S_ISREG(info.st_mode) ? 1 : 0;
}

/* Reads the rest of file in growing chunks after the first length bytes
   already in buffer (capacity bytes allocated, or buffer NULL). */
static EmeraldString *emerald_file_read_chunks(FILE *file, char *buffer, size_t length, size_t capacity) {
    for (;;) {
        if (buffer == NULL || length + 4096 + 1 > capacity) {
            size_t next_capacity = capacity < 4096 ? 8192 : capacity * 2;

            while (next_capacity < length + 4096 + 1) {
                next_capacity *= 2;
            }

            char *next_buffer = (char *) realloc(buffer, next_capacity);

            if (next_buffer == NULL) {
                free(buffer);
                fclose(file);
                return emerald_string_from_cstr("");
            }

            buffer = next_buffer;
            capacity = next_capacity;
        }

        size_t read = fread(buffer + length, 1, 4096, file);
        length += read;

        if (read < 4096) {
            break;
        }
    }

    fclose(file);
    return emerald_runtime_string_from_owned_buffer(buffer, length);
}

EmeraldString *emerald_file_read_text(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    FILE *file = native == NULL ? NULL : fopen(native, "rb");

    if (file == NULL) {
        return emerald_string_from_cstr("");
    }

    /* Regular files are read straight into a String sized from fstat, with
       no intermediate buffer. Pseudo filesystems like /proc report size 0
       even though reading yields content, and a file may change size while
       it is read, so those cases continue with chunked reads until EOF. */
    struct stat info;

    if (fstat(fileno(file), &info) == 0 && S_ISREG(info.st_mode) && info.st_size > 0
        && (uint64_t) info.st_size < (uint64_t) SIZE_MAX / 2) {
        size_t expected = (size_t) info.st_size;
        EmeraldString *value = emerald_runtime_string_alloc((uint64_t) expected);
        size_t read = fread(value->bytes, 1, expected, file);
        int extra = read < expected ? EOF : fgetc(file);

        if (extra == EOF) {
            fclose(file);
            value->length = (uint64_t) read;
            value->bytes[read] = 0;
            return value;
        }

        size_t capacity = expected * 2 + 4096;
        char *buffer = (char *) malloc(capacity);

        if (buffer == NULL) {
            fclose(file);
            return value;
        }

        memcpy(buffer, value->bytes, expected);
        buffer[expected] = (char) extra;
        emerald_flow_root_release(value);
        return emerald_file_read_chunks(file, buffer, expected + 1, capacity);
    }

    return emerald_file_read_chunks(file, NULL, 0, 0);
}

/* Lines are split on "\n" with one trailing "\r" removed. A final newline
   ends the last line rather than starting an empty one, so "a\nb\n" and
   "a\nb" both give ["a", "b"], and an empty or missing file gives []. */
EmeraldList *emerald_file_read_lines(EmeraldString *path) {
    EmeraldString *text = emerald_file_read_text(path);
    EmeraldList *list = emerald_list_new();
    const uint8_t *cursor = text->bytes;
    const uint8_t *end = text->bytes + text->length;

    while (cursor < end) {
        const uint8_t *newline = (const uint8_t *) memchr(cursor, '\n', (size_t) (end - cursor));
        const uint8_t *line_end = newline == NULL ? end : newline;

        if (line_end > cursor && line_end[-1] == '\r') {
            line_end--;
        }

        emerald_list_add(list, emerald_string_new(cursor, (uint64_t) (line_end - cursor)));

        if (newline == NULL) {
            break;
        }

        cursor = newline + 1;
    }

    emerald_flow_root_release(text);
    return list;
}

static void emerald_file_write_mode(EmeraldString *path, EmeraldString *text, const char *mode) {
    const char *native = emerald_runtime_native_cstr(path);
    FILE *file = native == NULL ? NULL : fopen(native, mode);

    if (file == NULL) {
        return;
    }

    if (text != NULL && text->bytes != NULL && text->length > 0) {
        fwrite(text->bytes, 1, (size_t) text->length, file);
    }

    fclose(file);
}

void emerald_file_write_text(EmeraldString *path, EmeraldString *text) {
    emerald_file_write_mode(path, text, "wb");
}

void emerald_file_append_text(EmeraldString *path, EmeraldString *text) {
    emerald_file_write_mode(path, text, "ab");
}

int32_t emerald_file_delete(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    return native != NULL && remove(native) == 0 ? 1 : 0;
}

int32_t emerald_file_size(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    struct stat info;

    if (native == NULL || stat(native, &info) != 0) {
        return 0;
    }

    if (info.st_size > INT32_MAX) {
        return INT32_MAX;
    }

    return (int32_t) info.st_size;
}

int32_t emerald_directory_exists(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);
    struct stat info;

    if (native == NULL || stat(native, &info) != 0) {
        return 0;
    }

    return S_ISDIR(info.st_mode) ? 1 : 0;
}

static int emerald_directory_create_single(const char *path) {
#if defined(_WIN32)
    if (_mkdir(path) == 0) {
        return 1;
    }
#else
    if (mkdir(path, 0777) == 0) {
        return 1;
    }
#endif

    return errno == EEXIST ? 1 : 0;
}

int32_t emerald_directory_create(EmeraldString *path) {
    const char *text = emerald_runtime_native_cstr(path);

    if (text == NULL) {
        return 0;
    }

    size_t length = strlen(text);

    if (length == 0) {
        return 1;
    }

    char *buffer = (char *) malloc(length + 1);

    if (buffer == NULL) {
        return 0;
    }

    memcpy(buffer, text, length + 1);

    size_t index = 0;

#if defined(_WIN32)
    if (length >= 2 && buffer[1] == ':') {
        index = 2;
    }
#endif

    while (index < length && (buffer[index] == '/' || buffer[index] == '\\')) {
        index++;
    }

    for (; index < length; index++) {
        if (buffer[index] != '/' && buffer[index] != '\\') {
            continue;
        }

        char separator = buffer[index];
        buffer[index] = 0;

        if (buffer[0] != 0 && !emerald_directory_create_single(buffer)) {
            free(buffer);
            return 0;
        }

        buffer[index] = separator;
    }

    int result = emerald_directory_create_single(buffer);
    free(buffer);
    return result ? 1 : 0;
}

int32_t emerald_directory_delete(EmeraldString *path) {
    const char *native = emerald_runtime_native_cstr(path);

    if (native == NULL) {
        return 0;
    }

#if defined(_WIN32)
    return _rmdir(native) == 0 ? 1 : 0;
#else
    return rmdir(native) == 0 ? 1 : 0;
#endif
}

EmeraldList *emerald_directory_list(EmeraldString *path) {
    EmeraldList *list = emerald_list_new();
    const char *native = emerald_runtime_native_cstr(path);

    if (native == NULL) {
        return list;
    }

#if defined(_WIN32)
    char search[MAX_PATH];
    snprintf(search, sizeof(search), "%s\\*", native);
    struct _finddata_t entry;
    intptr_t handle = _findfirst(search, &entry);

    if (handle == -1) {
        return list;
    }

    do {
        if (strcmp(entry.name, ".") != 0 && strcmp(entry.name, "..") != 0) {
            emerald_list_add(list, emerald_string_from_cstr(entry.name));
        }
    } while (_findnext(handle, &entry) == 0);

    _findclose(handle);
#else
    DIR *directory = opendir(native);

    if (directory == NULL) {
        return list;
    }

    struct dirent *entry;

    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
            emerald_list_add(list, emerald_string_from_cstr(entry->d_name));
        }
    }

    closedir(directory);
#endif

    return list;
}

EmeraldString *emerald_path_current(void) {
    char buffer[4096];

#if defined(_WIN32)
    if (_getcwd(buffer, sizeof(buffer)) == NULL) {
        return emerald_string_from_cstr("");
    }
#else
    if (getcwd(buffer, sizeof(buffer)) == NULL) {
        return emerald_string_from_cstr("");
    }
#endif

    return emerald_string_from_cstr(buffer);
}

/* Path helpers below are pure String operations: they work on the String
   length and bytes, so they never truncate at an interior NUL byte. */
static int emerald_path_is_separator(uint8_t value) {
    return value == '/' || value == '\\';
}

EmeraldString *emerald_path_join(EmeraldString *left, EmeraldString *right) {
    uint64_t left_length = left == NULL ? 0 : left->length;
    uint64_t right_length = right == NULL ? 0 : right->length;
#if defined(_WIN32)
    const uint8_t separator = '\\';
#else
    const uint8_t separator = '/';
#endif

    if (left_length == 0) {
        return emerald_string_new(right_length == 0 ? NULL : right->bytes, right_length);
    }

    int has_separator = emerald_path_is_separator(left->bytes[left_length - 1]);
    EmeraldString *result = emerald_runtime_string_alloc(left_length + right_length + (has_separator ? 0 : 1));
    uint8_t *target = result->bytes;
    memcpy(target, left->bytes, (size_t) left_length);
    target += left_length;

    if (!has_separator) {
        *target++ = separator;
    }

    if (right_length > 0) {
        memcpy(target, right->bytes, (size_t) right_length);
    }

    return result;
}

EmeraldString *emerald_path_parent(EmeraldString *path) {
    if (path == NULL || path->length == 0) {
        return emerald_string_from_cstr("");
    }

    const uint8_t *text = path->bytes;
    uint64_t length = path->length;

    while (length > 0 && !emerald_path_is_separator(text[length - 1])) {
        length--;
    }

    if (length == 0) {
        return emerald_string_from_cstr("");
    }

    while (length > 1 && emerald_path_is_separator(text[length - 1])) {
        length--;
    }

    return emerald_string_new(text, length);
}

static uint64_t emerald_path_file_name_start(EmeraldString *path) {
    uint64_t start = path->length;

    while (start > 0 && !emerald_path_is_separator(path->bytes[start - 1])) {
        start--;
    }

    return start;
}

EmeraldString *emerald_path_file_name(EmeraldString *path) {
    if (path == NULL || path->length == 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t start = emerald_path_file_name_start(path);
    return emerald_string_new(path->bytes + start, path->length - start);
}

EmeraldString *emerald_path_extension(EmeraldString *path) {
    if (path == NULL || path->length == 0) {
        return emerald_string_from_cstr("");
    }

    uint64_t start = emerald_path_file_name_start(path);
    uint64_t dot = path->length;

    while (dot > start && path->bytes[dot - 1] != '.') {
        dot--;
    }

    if (dot == start) {
        return emerald_string_from_cstr("");
    }

    return emerald_string_new(path->bytes + dot - 1, path->length - dot + 1);
}
