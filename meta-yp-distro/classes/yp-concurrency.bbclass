# 构建并发资源分级（M0.1.2 / CHG-022 / ISS-038）
# bitbake 的 local.conf（kas/base.yml 的 base: 块）不能定义多行 python def（ConfHandler
# 报 unparsed line），故分级函数放 .bbclass，由 base.yml 的 INHERIT 引入。
# 按 bitbake 进程可见 CPU + 容器 cgroup 内存双重分级，避免只按 CPU 翻倍在 8GB 容器 OOM。

def yp_mem_bytes(d):
    """容器可见内存字节数：cgroup v2 -> v1 -> /proc/meminfo 回退。
    Docker --memory 不改写 /proc/meminfo，必须优先读 cgroup 限制。"""
    def _read(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return ""

    for path in ("/sys/fs/cgroup/memory.max",
                 "/sys/fs/cgroup/memory/memory.limit_in_bytes"):
        raw = _read(path)
        if not raw or raw == "max":
            continue
        try:
            n = int(raw)
        except ValueError:
            continue
        if 0 < n < (1 << 60):
            return n

    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024
    except OSError:
        pass
    return 0


def yp_build_threads(d):
    """CPU + cgroup 内存二维分级，返回至少 1 的 bitbake 并发线程数。"""
    import os
    cpus = oe.utils.cpu_count() or os.cpu_count() or 1
    mem_gb = yp_mem_bytes(d) // (1024 ** 3)
    if cpus >= 32 and mem_gb >= 120:
        n = 32
    elif cpus >= 16 and mem_gb >= 32:
        n = min(16, cpus)
    elif cpus >= 8 and mem_gb >= 16:
        n = min(8, cpus)
    else:
        n = min(4, cpus)
    return max(1, n)
