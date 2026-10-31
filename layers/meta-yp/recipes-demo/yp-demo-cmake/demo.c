#include <stdio.h>
#include <string.h>

#ifndef YP_DEMO_VARIANT
#define YP_DEMO_VARIANT "unknown"
#endif

#define DEMO_NAME "yp-demo-cmake"
#define DEMO_VERSION "0.1"

static void print_help(const char *program)
{
    printf("Usage: %s [--json | --version | --help]\n", program);
}

int main(int argc, char **argv)
{
    int json = 0;
    if (argc > 2) {
        print_help(argv[0]);
        return 2;
    }
    if (argc == 2) {
        if (strcmp(argv[1], "--json") == 0) {
            json = 1;
        } else if (strcmp(argv[1], "--version") == 0) {
            printf("%s %s\n", DEMO_NAME, DEMO_VERSION);
            return 0;
        } else if (strcmp(argv[1], "--help") == 0) {
            print_help(argv[0]);
            return 0;
        } else {
            print_help(argv[0]);
            return 2;
        }
    }

    FILE *uptime_file = fopen("/proc/uptime", "r");
    double uptime;
    if (uptime_file == NULL) {
        perror("cannot open /proc/uptime");
        return 1;
    }
    int read_ok = fscanf(uptime_file, "%lf", &uptime) == 1;
    fclose(uptime_file);
    if (!read_ok) {
        fprintf(stderr, "cannot read uptime from /proc/uptime\n");
        return 1;
    }

    if (json) {
        printf("{\"name\":\"%s\",\"version\":\"%s\",\"variant\":\"%s\","
               "\"uptime_seconds\":%.2f}\n",
               DEMO_NAME, DEMO_VERSION, YP_DEMO_VARIANT, uptime);
    } else {
        printf("%s %s (variant: %s), uptime: %.2f seconds\n",
               DEMO_NAME, DEMO_VERSION, YP_DEMO_VARIANT, uptime);
    }
    return 0;
}
