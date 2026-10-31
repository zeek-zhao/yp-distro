#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <dirent.h>
#include <stdlib.h>
#include <time.h>

static volatile sig_atomic_t stopping = 0;

struct metrics {
    double uptime;
    double load1;
    unsigned long long mem_free_kb;
    unsigned long long procs;
};

static void handle_signal(int signal_number)
{
    (void)signal_number;
    stopping = 1;
}

static int read_metrics(struct metrics *m)
{
    FILE *file;
    char line[256];
    int found;

    file = fopen("/proc/uptime", "r");
    if (file == NULL) {
        perror("打开 /proc/uptime 失败");
        return -1;
    }
    if (fscanf(file, "%lf", &m->uptime) != 1) {
        fprintf(stderr, "无法读取 /proc/uptime\n");
        fclose(file);
        return -1;
    }
    fclose(file);

    file = fopen("/proc/loadavg", "r");
    if (file == NULL) {
        perror("打开 /proc/loadavg 失败");
        return -1;
    }
    if (fscanf(file, "%lf", &m->load1) != 1) {
        fprintf(stderr, "无法读取 /proc/loadavg\n");
        fclose(file);
        return -1;
    }
    fclose(file);

    file = fopen("/proc/meminfo", "r");
    if (file == NULL) {
        perror("打开 /proc/meminfo 失败");
        return -1;
    }
    found = 0;
    while (fgets(line, sizeof(line), file) != NULL) {
        if (sscanf(line, "MemFree: %llu kB", &m->mem_free_kb) == 1) {
            found = 1;
            break;
        }
    }
    fclose(file);
    if (!found) {
        fprintf(stderr, "无法读取 /proc/meminfo 的 MemFree\n");
        return -1;
    }

    /* /proc/stat 的 "processes" 是开机以来的累计 fork 次数（现网是个上亿的数），
       不是「现在有多少进程」。要当前进程数只能按 /proc/<pid> 目录计数。 */
    {
        DIR *dir = opendir("/proc");
        struct dirent *ent;

        if (dir == NULL) {
            perror("打开 /proc 失败");
            return -1;
        }
        m->procs = 0;
        while ((ent = readdir(dir)) != NULL) {
            const char *n = ent->d_name;
            const char *q = n;

            while (*q >= '0' && *q <= '9')
                q++;
            if (q != n && *q == '\0')
                m->procs++;
        }
        closedir(dir);
    }
    return 0;
}

static unsigned int get_interval(void)
{
    const char *value = getenv("YP_COLLECTD_INTERVAL");
    char *end;
    long seconds;

    if (value == NULL || *value == '\0') {
        return 60;
    }
    errno = 0;
    seconds = strtol(value, &end, 10);
    if (errno == 0 && end != value && *end == '\0' &&
        seconds >= 1 && seconds <= 86400) {
        return (unsigned int)seconds;
    }
    fprintf(stderr, "YP_COLLECTD_INTERVAL 无效，使用默认值 60 秒\n");
    return 60;
}

static int wait_interval(unsigned int seconds)
{
    unsigned int tick;

    for (tick = 0; tick < seconds * 5U && !stopping; ++tick) {
        struct timespec remaining = {0, 200000000L};
        int result;

        do {
            result = nanosleep(&remaining, &remaining);
        } while (result == -1 && errno == EINTR && !stopping);
        if (result == -1 && !stopping) {
            perror("nanosleep 失败");
            return -1;
        }
    }
    return 0;
}

int main(void)
{
    struct sigaction action = {0};
    struct metrics m;
    char line[256];
    unsigned int interval = get_interval();

    action.sa_handler = handle_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) == -1 ||
        sigaction(SIGINT, &action, NULL) == -1) {
        perror("注册退出信号处理器失败");
        return EXIT_FAILURE;
    }

    while (!stopping) {
        int length;

        if (read_metrics(&m) != 0) {
            return EXIT_FAILURE;
        }
        length = snprintf(line, sizeof(line),
                          "{\"ts\":%lld,\"uptime\":%.1f,\"load1\":%.2f,"
                          "\"mem_free_kb\":%llu,\"procs\":%llu}\n",
                          (long long)time(NULL), m.uptime, m.load1,
                          m.mem_free_kb, m.procs);
        if (length < 0 || (size_t)length >= sizeof(line)) {
            fprintf(stderr, "生成指标 JSON 失败\n");
            return EXIT_FAILURE;
        }
        /* stdout 接到 journald 时是管道；显式刷新才能及时交付每一行。 */
        if (fputs(line, stdout) == EOF || fflush(stdout) == EOF) {
            perror("写入指标日志失败");
            return EXIT_FAILURE;
        }
        if (!stopping && wait_interval(interval) != 0) {
            return EXIT_FAILURE;
        }
    }
    return EXIT_SUCCESS;
}
