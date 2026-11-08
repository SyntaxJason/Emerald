#include "emerald_runtime_internal.h"

typedef struct EmeraldSocketEntry {
    int32_t handle;
    EMERALD_SOCKET socket;
    int32_t kind;
    int32_t open;
    char last_host[128];
    int32_t last_port;
} EmeraldSocketEntry;

static EmeraldSocketEntry emerald_socket_entries[1024];
static int32_t emerald_next_socket_handle = 1;

static int32_t emerald_store_socket(EMERALD_SOCKET socket, int32_t kind) {
    if (socket == EMERALD_INVALID_SOCKET) {
        return -1;
    }

    int32_t index = 0;

    while (index < 1024) {
        if (!emerald_socket_entries[index].open) {
            int32_t handle = emerald_next_socket_handle++;
            emerald_socket_entries[index].handle = handle;
            emerald_socket_entries[index].socket = socket;
            emerald_socket_entries[index].kind = kind;
            emerald_socket_entries[index].open = 1;
            emerald_socket_entries[index].last_host[0] = 0;
            emerald_socket_entries[index].last_port = 0;
            return handle;
        }

        index++;
    }

    emerald_close_socket(socket);
    return -1;
}

static EmeraldSocketEntry *emerald_socket_entry(int32_t handle, int32_t kind) {
    int32_t index = 0;

    while (index < 1024) {
        if (emerald_socket_entries[index].open && emerald_socket_entries[index].handle == handle && emerald_socket_entries[index].kind == kind) {
            return &emerald_socket_entries[index];
        }

        index++;
    }

    return NULL;
}

static int32_t emerald_close_handle(int32_t handle, int32_t kind) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, kind);

    if (entry == NULL) {
        return 0;
    }

    emerald_close_socket(entry->socket);
    entry->open = 0;
    return 1;
}

static int32_t emerald_socket_local_port(EMERALD_SOCKET socket) {
    struct sockaddr_storage address;
    socklen_t length = sizeof(address);

    if (getsockname(socket, (struct sockaddr *) &address, &length) != 0) {
        return 0;
    }

    if (address.ss_family == AF_INET) {
        return ntohs(((struct sockaddr_in *) &address)->sin_port);
    }

    return 0;
}

static EMERALD_SOCKET emerald_create_tcp_socket(void) {
    if (!emerald_runtime_socket_ready()) {
        return EMERALD_INVALID_SOCKET;
    }

    return socket(AF_INET, SOCK_STREAM, 0);
}

static EMERALD_SOCKET emerald_create_udp_socket(void) {
    if (!emerald_runtime_socket_ready()) {
        return EMERALD_INVALID_SOCKET;
    }

    return socket(AF_INET, SOCK_DGRAM, 0);
}

static int emerald_fill_ipv4(struct sockaddr_in *address, const char *host, int32_t port) {
    memset(address, 0, sizeof(*address));
    address->sin_family = AF_INET;
    address->sin_port = htons((uint16_t) port);

    if (host == NULL || host[0] == 0 || strcmp(host, "0.0.0.0") == 0) {
        address->sin_addr.s_addr = INADDR_ANY;
        return 1;
    }

    if (strcmp(host, "localhost") == 0) {
        host = "127.0.0.1";
    }

    if (inet_pton(AF_INET, host, &address->sin_addr) == 1) {
        return 1;
    }

    struct hostent *entry = gethostbyname(host);

    if (entry == NULL || entry->h_addr_list == NULL || entry->h_addr_list[0] == NULL) {
        return 0;
    }

    memcpy(&address->sin_addr, entry->h_addr_list[0], (size_t) entry->h_length);
    return 1;
}

/* Rejects host Strings with an interior NUL instead of resolving a truncated
   name; a NULL C host would otherwise mean "any address" to emerald_fill_ipv4. */
static int emerald_fill_ipv4_host(struct sockaddr_in *address, EmeraldString *host, int32_t port) {
    const char *native = emerald_runtime_native_cstr(host);
    return native != NULL && emerald_fill_ipv4(address, native, port);
}

int32_t emerald_tcp_connect(EmeraldString *host, int32_t port) {
    EMERALD_SOCKET socket_value = emerald_create_tcp_socket();

    if (socket_value == EMERALD_INVALID_SOCKET) {
        return -1;
    }

    struct sockaddr_in address;

    if (!emerald_fill_ipv4_host(&address, host, port)) {
        emerald_close_socket(socket_value);
        return -1;
    }

    if (connect(socket_value, (struct sockaddr *) &address, sizeof(address)) != 0) {
        emerald_close_socket(socket_value);
        return -1;
    }

    return emerald_store_socket(socket_value, 1);
}

int32_t emerald_tcp_listen(EmeraldString *host, int32_t port) {
    EMERALD_SOCKET socket_value = emerald_create_tcp_socket();

    if (socket_value == EMERALD_INVALID_SOCKET) {
        return -1;
    }

    int one = 1;
    setsockopt(socket_value, SOL_SOCKET, SO_REUSEADDR, (const char *) &one, sizeof(one));

    struct sockaddr_in address;

    if (!emerald_fill_ipv4_host(&address, host, port)) {
        emerald_close_socket(socket_value);
        return -1;
    }

    if (bind(socket_value, (struct sockaddr *) &address, sizeof(address)) != 0) {
        emerald_close_socket(socket_value);
        return -1;
    }

    if (listen(socket_value, 64) != 0) {
        emerald_close_socket(socket_value);
        return -1;
    }

    return emerald_store_socket(socket_value, 2);
}

int32_t emerald_tcp_is_open(int32_t handle) {
    return emerald_socket_entry(handle, 1) == NULL ? 0 : 1;
}

int32_t emerald_tcp_listener_is_open(int32_t handle) {
    return emerald_socket_entry(handle, 2) == NULL ? 0 : 1;
}

int32_t emerald_tcp_listener_port(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 2);
    return entry == NULL ? 0 : emerald_socket_local_port(entry->socket);
}

EmeraldString *emerald_tcp_read_text(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 1);

    if (entry == NULL) {
        return emerald_string_from_cstr("");
    }

    /* Accumulate into one malloc buffer: concatenating a String per chunk
       copied the text repeatedly and leaked every intermediate String. */
    size_t length = 0;
    size_t capacity = 4096;
    char *buffer = (char *) malloc(capacity);

    if (buffer == NULL) {
        return emerald_string_from_cstr("");
    }

    for (;;) {
        if (capacity - length < 4096) {
            char *next = (char *) realloc(buffer, capacity * 2);

            if (next == NULL) {
                break;
            }

            buffer = next;
            capacity *= 2;
        }

        int read = recv(entry->socket, buffer + length, 4096, 0);

        if (read <= 0) {
            break;
        }

        length += (size_t) read;

        if (read < 4096) {
            break;
        }
    }

    return emerald_runtime_string_from_owned_buffer(buffer, length);
}

EmeraldString *emerald_tcp_read_line(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 1);

    if (entry == NULL) {
        return emerald_string_from_cstr("");
    }

    char buffer[4096];
    int index = 0;

    while (index < (int) sizeof(buffer) - 1) {
        char ch;
        int read = recv(entry->socket, &ch, 1, 0);

        if (read <= 0 || ch == '\n') {
            break;
        }

        if (ch != '\r') {
            buffer[index++] = ch;
        }
    }

    return emerald_string_new((const uint8_t *) buffer, (uint64_t) index);
}

int32_t emerald_tcp_write_text(int32_t handle, EmeraldString *text) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 1);

    if (entry == NULL || text == NULL) {
        return 0;
    }

    uint64_t sent = 0;

    while (sent < text->length) {
        int written = send(entry->socket, (const char *) text->bytes + sent, (int) (text->length - sent), 0);

        if (written <= 0) {
            return 0;
        }

        sent += (uint64_t) written;
    }

    return 1;
}

int32_t emerald_tcp_close(int32_t handle) {
    return emerald_close_handle(handle, 1);
}

int32_t emerald_tcp_accept(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 2);

    if (entry == NULL) {
        return -1;
    }

    EMERALD_SOCKET socket_value = accept(entry->socket, NULL, NULL);
    return emerald_store_socket(socket_value, 1);
}

int32_t emerald_tcp_close_listener(int32_t handle) {
    return emerald_close_handle(handle, 2);
}

int32_t emerald_udp_bind(EmeraldString *host, int32_t port) {
    EMERALD_SOCKET socket_value = emerald_create_udp_socket();

    if (socket_value == EMERALD_INVALID_SOCKET) {
        return -1;
    }

    struct sockaddr_in address;

    if (!emerald_fill_ipv4_host(&address, host, port)) {
        emerald_close_socket(socket_value);
        return -1;
    }

    if (bind(socket_value, (struct sockaddr *) &address, sizeof(address)) != 0) {
        emerald_close_socket(socket_value);
        return -1;
    }

#if defined(_WIN32)
    DWORD timeout = 2000;
#else
    struct timeval timeout;
    timeout.tv_sec = 2;
    timeout.tv_usec = 0;
#endif
    setsockopt(socket_value, SOL_SOCKET, SO_RCVTIMEO, (const char *) &timeout, sizeof(timeout));

    return emerald_store_socket(socket_value, 3);
}

int32_t emerald_udp_is_open(int32_t handle) {
    return emerald_socket_entry(handle, 3) == NULL ? 0 : 1;
}

int32_t emerald_udp_local_port(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 3);
    return entry == NULL ? 0 : emerald_socket_local_port(entry->socket);
}

int32_t emerald_udp_send_text(int32_t handle, EmeraldString *host, int32_t port, EmeraldString *text) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 3);

    if (entry == NULL || text == NULL) {
        return 0;
    }

    struct sockaddr_in address;

    if (!emerald_fill_ipv4_host(&address, host, port)) {
        return 0;
    }

    int sent = sendto(entry->socket, (const char *) text->bytes, (int) text->length, 0, (struct sockaddr *) &address, sizeof(address));
    return sent == (int) text->length ? 1 : 0;
}

EmeraldString *emerald_udp_receive_text(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 3);

    if (entry == NULL) {
        return emerald_string_from_cstr("");
    }

    char buffer[65536];
    struct sockaddr_in sender;
    socklen_t sender_length = sizeof(sender);
    int read = recvfrom(entry->socket, buffer, sizeof(buffer), 0, (struct sockaddr *) &sender, &sender_length);

    if (read <= 0) {
        return emerald_string_from_cstr("");
    }

    const char *host = inet_ntoa(sender.sin_addr);
    snprintf(entry->last_host, sizeof(entry->last_host), "%s", host == NULL ? "" : host);
    entry->last_port = ntohs(sender.sin_port);

    return emerald_string_new((const uint8_t *) buffer, (uint64_t) read);
}

EmeraldString *emerald_udp_last_sender_host(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 3);
    return emerald_string_from_cstr(entry == NULL ? "" : entry->last_host);
}

int32_t emerald_udp_last_sender_port(int32_t handle) {
    EmeraldSocketEntry *entry = emerald_socket_entry(handle, 3);
    return entry == NULL ? 0 : entry->last_port;
}

int32_t emerald_udp_close(int32_t handle) {
    return emerald_close_handle(handle, 3);
}
