#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1000000000.0;
}

/* A small native parent avoids including the Python harness's own resident
   memory in the forked child's peak RSS. Build and link time are excluded. */
int main(int argc, char **argv) {
    if (argc < 5) return 2;
    double start = now();
    pid_t pid = fork();
    if (pid == 0) { execvp(argv[4], &argv[4]); _exit(127); }
    if (pid < 0) return 2;
    int status;
    struct rusage usage;
    while (wait4(pid, &status, 0, &usage) < 0) if (errno != EINTR) return 2;
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    fprintf(stderr, "%s %s run=%s seconds=%.6f rss_kib=%ld exit=%d\n",
        argv[1], argv[2], argv[3], now() - start, usage.ru_maxrss, code);
    return code;
}
