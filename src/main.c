#define _POSIX_C_SOURCE 200809L
#include "net.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static void on_signal(int sig) { (void)sig; running = 0; }

int main(void) {
    signal(SIGPIPE, SIG_IGN);          /* don't die writing to a closed peer */

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;         /* no SA_RESTART: accept() returns EINTR */
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    int lfd = net_listen("8080", 16);
    if (lfd < 0) return 1;
    printf("listening on http://localhost:8080\n");

    static const char body[] = "Hello, world!\n";
    char resp[256];
    int len = snprintf(resp, sizeof resp,
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n%s",
        sizeof body - 1, body);

    while (running) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            break;
        }

        char buf[4096];
        (void)read(cfd, buf, sizeof buf);   /* TODO milestone 2: parse properly */

        net_write_all(cfd, resp, (size_t)len);
        close(cfd);
    }

    close(lfd);
    puts("\nbye");
    return 0;
}
