#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef YP_DEMO_VARIANT
#define YP_DEMO_VARIANT "make"
#endif

static const char *VERSION = "0.1.0";

/* 读 /proc/uptime 第一列（系统启动秒数） */
static double uptime_seconds(void) {
    FILE *f = fopen("/proc/uptime", "r");
    if (!f) return -1.0;
    double up = -1.0;
    if (fscanf(f, "%lf", &up) != 1) up = -1.0;
    fclose(f);
    return up;
}

int main(int argc, char **argv) {
    int json = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0) json = 1;
        else if (strcmp(argv[i], "--version") == 0) { printf("%s\n", VERSION); return 0; }
        else if (strcmp(argv[i], "--help") == 0) {
            printf("yp-demo-%s [--json|--version|--help]\n", YP_DEMO_VARIANT);
            return 0;
        }
    }
    double up = uptime_seconds();
    if (json) {
        printf("{\"name\":\"yp-demo-%s\",\"version\":\"%s\",\"variant\":\"%s\",\"uptime_s\":%.2f}\n",
               YP_DEMO_VARIANT, VERSION, YP_DEMO_VARIANT, up);
    } else {
        printf("yp-demo-%s v%s (variant=%s) uptime=%.2fs\n",
               YP_DEMO_VARIANT, VERSION, YP_DEMO_VARIANT, up);
    }
    return 0;
}
