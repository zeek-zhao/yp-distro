#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef YP_VERSION
#define YP_VERSION "0.1"
#endif
#ifndef YP_BUILD
#define YP_BUILD "unknown"
#endif
#ifndef YP_MACHINE
#define YP_MACHINE "unknown"
#endif

#define PORT 8080
#define REQUEST_SIZE 4096

static int send_all(int fd, const char *data, size_t length)
{
    size_t sent = 0;
    while (sent < length) {
        ssize_t result = send(fd, data + sent, length - sent, 0);
        if (result < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }
        if (result == 0)
            return -1;
        sent += (size_t)result;
    }
    return 0;
}

static void respond(int fd, const char *status, const char *type,
                    const char *body)
{
    char header[256];
    int length = snprintf(header, sizeof(header),
                          "HTTP/1.1 %s\r\nContent-Type: %s\r\n"
                          "Content-Length: %zu\r\nConnection: close\r\n\r\n",
                          status, type, strlen(body));
    if (length > 0 && (size_t)length < sizeof(header)) {
        (void)send_all(fd, header, (size_t)length);
        (void)send_all(fd, body, strlen(body));
    }
}

static void read_status(double *uptime, unsigned long *mem_total,
                        unsigned long *mem_free, char *loadavg, size_t size)
{
    FILE *file = fopen("/proc/uptime", "r");
    if (file != NULL) {
        if (fscanf(file, "%lf", uptime) != 1)
            *uptime = 0.0;
        fclose(file);
    }

    file = fopen("/proc/meminfo", "r");
    if (file != NULL) {
        char line[256];
        while (fgets(line, sizeof(line), file) != NULL) {
            if (sscanf(line, "MemTotal: %lu kB", mem_total) == 1)
                continue;
            (void)sscanf(line, "MemFree: %lu kB", mem_free);
        }
        fclose(file);
    }

    file = fopen("/proc/loadavg", "r");
    if (file != NULL) {
        double load1;
        double load5;
        double load15;
        if (fscanf(file, "%lf %lf %lf", &load1, &load5, &load15) == 3)
            (void)snprintf(loadavg, size, "%.2f %.2f %.2f", load1, load5, load15);
        else
            (void)snprintf(loadavg, size, "0.00 0.00 0.00");
        fclose(file);
    }
}

static int json_escape(char *out, size_t capacity, const char *input)
{
    size_t used = 0;
    for (const unsigned char *p = (const unsigned char *)input; *p != '\0'; ++p) {
        char escaped[7];
        size_t length;
        if (*p == '"' || *p == '\\') {
            escaped[0] = '\\';
            escaped[1] = (char)*p;
            length = 2;
        } else if (*p < 0x20) {
            int n = snprintf(escaped, sizeof(escaped), "\\u%04x", *p);
            if (n != 6)
                return -1;
            length = 6;
        } else {
            escaped[0] = (char)*p;
            length = 1;
        }
        if (used + length >= capacity)
            return -1;
        memcpy(out + used, escaped, length);
        used += length;
    }
    out[used] = '\0';
    return 0;
}

static void serve_status(int fd)
{
    double uptime = 0.0;
    unsigned long mem_total = 0;
    unsigned long mem_free = 0;
    char loadavg[128] = "0.00 0.00 0.00";
    char escaped_loadavg[256];
    char escaped_version[128];
    char escaped_build[256];
    char escaped_machine[128];
    char body[1024];

    read_status(&uptime, &mem_total, &mem_free, loadavg, sizeof(loadavg));
    if (json_escape(escaped_loadavg, sizeof(escaped_loadavg), loadavg) != 0 ||
        json_escape(escaped_version, sizeof(escaped_version), YP_VERSION) != 0 ||
        json_escape(escaped_build, sizeof(escaped_build), YP_BUILD) != 0 ||
        json_escape(escaped_machine, sizeof(escaped_machine), YP_MACHINE) != 0) {
        respond(fd, "500 Internal Server Error", "text/plain", "error\n");
        return;
    }

    int length = snprintf(body, sizeof(body),
                          "{\"uptime\":%.2f,\"mem_total_kb\":%lu,"
                          "\"mem_free_kb\":%lu,\"loadavg\":\"%s\","
                          "\"version\":\"%s\",\"build\":\"%s\","
                          "\"machine\":\"%s\"}\n",
                          uptime, mem_total, mem_free, escaped_loadavg,
                          escaped_version, escaped_build, escaped_machine);
    if (length < 0 || (size_t)length >= sizeof(body)) {
        respond(fd, "500 Internal Server Error", "text/plain", "error\n");
        return;
    }
    respond(fd, "200 OK", "application/json", body);
}

static void handle_client(int fd)
{
    char request[REQUEST_SIZE];
    size_t used = 0;
    while (used < sizeof(request) - 1) {
        ssize_t result = recv(fd, request + used, sizeof(request) - 1 - used, 0);
        if (result < 0) {
            if (errno == EINTR)
                continue;
            return;
        }
        if (result == 0)
            return;
        used += (size_t)result;
        request[used] = '\0';
        if (strchr(request, '\n') != NULL)
            break;
    }
    if (used == sizeof(request) - 1) {
        respond(fd, "400 Bad Request", "text/plain", "bad request\n");
        return;
    }

    char method[16];
    char path[256];
    if (sscanf(request, "%15s %255s", method, path) != 2) {
        respond(fd, "400 Bad Request", "text/plain", "bad request\n");
    } else if (strcmp(method, "GET") != 0) {
        respond(fd, "405 Method Not Allowed", "text/plain", "method not allowed\n");
    } else if (strcmp(path, "/status") == 0) {
        serve_status(fd);
    } else if (strcmp(path, "/healthz") == 0) {
        respond(fd, "200 OK", "text/plain", "ok\n");
    } else {
        respond(fd, "404 Not Found", "text/plain", "not found\n");
    }
}

int main(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    int reuse = 1;
    if (setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        perror("setsockopt");
        close(server);
        return EXIT_FAILURE;
    }
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        perror("signal");
        close(server);
        return EXIT_FAILURE;
    }

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(PORT);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind");
        close(server);
        return EXIT_FAILURE;
    }
    if (listen(server, 16) < 0) {
        perror("listen");
        close(server);
        return EXIT_FAILURE;
    }

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR)
                continue;
            perror("accept");
            close(server);
            return EXIT_FAILURE;
        }
        handle_client(client);
        close(client);
    }
}
