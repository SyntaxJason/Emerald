#ifndef EMERALD_RUNTIME_INTERNAL_H
#define EMERALD_RUNTIME_INTERNAL_H

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "../emerald_runtime.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#include <process.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <shellapi.h>
#include <objbase.h>
#define EMERALD_SOCKET SOCKET
#define EMERALD_INVALID_SOCKET INVALID_SOCKET
#define emerald_close_socket closesocket
#else
#include <arpa/inet.h>
#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <netdb.h>
#include <pwd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <unistd.h>
#define EMERALD_SOCKET int
#define EMERALD_INVALID_SOCKET -1
#define emerald_close_socket close
#endif

#define EMERALD_LIST_PRIMITIVE 0
#define EMERALD_LIST_REFERENCE 1
#define EMERALD_LIST_INLINE 2

#if defined(_WIN32)
#define EMERALD_INTERNAL
#elif defined(__GNUC__) || defined(__clang__)
#define EMERALD_INTERNAL __attribute__((visibility("hidden")))
#else
#define EMERALD_INTERNAL
#endif

EMERALD_INTERNAL void emerald_flow_fail(uint64_t size);
EMERALD_INTERNAL void *emerald_flow_resize_atomic_owned(void *owner, void *memory, uint64_t size);
EMERALD_INTERNAL void emerald_flow_note_container_owned_adoption(void);
EMERALD_INTERNAL void emerald_flow_note_container_owned_release(void);
EMERALD_INTERNAL void emerald_flow_note_container_inline_copy(void);
EMERALD_INTERNAL const char *emerald_runtime_cstr(EmeraldString *value);
EMERALD_INTERNAL const char *emerald_runtime_native_cstr(EmeraldString *value);
EMERALD_INTERNAL EmeraldString *emerald_runtime_string_alloc(uint64_t length);
EMERALD_INTERNAL void emerald_runtime_flush_stdout(void);
EMERALD_INTERNAL EmeraldString *emerald_runtime_string_from_owned_buffer(char *buffer, size_t length);
EMERALD_INTERNAL int emerald_runtime_socket_ready(void);

#endif
