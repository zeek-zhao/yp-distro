#!/usr/bin/env bash
# M0.1.2（AI-010 §2.2 / CHG-022 / ISS-038）：Docker daemon 级资源诊断（只读）。
#
# 本脚本只在宿主读取 Docker daemon 的 NCPU / MemTotal，输出分级标签与“建议值”
# SUGGEST_*，供 runbook / verify-env 记录。**它不是 bitbake 并发控制通道**：
#   - 不输出可 eval 的 export；YP_BUILD_THREADS / YP_PARALLEL_MAKE 已不再是控制变量（ISS-039）；
#   - 实际并发由容器内 kas/base.yml 的 yp_build_threads(d) 按 cgroup 内存 + 可见 CPU 计算；
#   - 负向容器（--cpuset-cpus/--memory）下，daemon 建议值（宿主级）与容器内实际值会不同，
#     最终必须以容器内 bitbake-getvar BB_NUMBER_THREADS PARALLEL_MAKE 为准（ISS-037）。
# 只读：不启动容器、不写文件、不下载。daemon 不可用时 exit 1，不静默回退。
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker 不可用，无法读取 daemon 资源"
docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || die "docker daemon 不可用"

cpus="$(docker info --format '{{.NCPU}}' 2>/dev/null)"
mem_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null)"
[ -n "$cpus" ] && [ "$cpus" -gt 0 ] 2>/dev/null || die "docker info NCPU 无效: ${cpus:-<empty>}"
[ -n "$mem_bytes" ] && [ "$mem_bytes" -gt 0 ] 2>/dev/null || die "docker info MemTotal 无效: ${mem_bytes:-<empty>}"
mem_gb=$((mem_bytes / 1024 / 1024 / 1024))

# 分级表（与 kas/base.yml 的 yp_build_threads(d) 完全一致，AI-010 §2.1/§2.2）：
# standard cpus>=32 且 mem>=120 -> 32；mid cpus>=16 且 mem>=32 -> min(16,cpus)；
# small   cpus>=8  且 mem>=16  -> min(8,cpus)；legacy 其他 -> min(4,cpus)。
# 建议线程至少 1；PARALLEL_MAKE = max(1, threads//2)，不出现 -j 0。
if [ "$cpus" -ge 32 ] && [ "$mem_gb" -ge 120 ]; then
  tier="standard"; n=32
elif [ "$cpus" -ge 16 ] && [ "$mem_gb" -ge 32 ]; then
  tier="mid"; n=16; [ "$cpus" -lt 16 ] && n=$cpus
elif [ "$cpus" -ge 8 ] && [ "$mem_gb" -ge 16 ]; then
  tier="small"; n=8; [ "$cpus" -lt 8 ] && n=$cpus
else
  tier="legacy"; n=4; [ "$cpus" -lt 4 ] && n=$cpus
fi
[ "$n" -ge 1 ] || n=1
parallel_n=$((n / 2)); [ "$parallel_n" -ge 1 ] || parallel_n=1

echo "RESOURCE_TIER=$tier"
echo "RESOURCE_CORES=$cpus"
echo "RESOURCE_MEM_GB=$mem_gb"
echo "SUGGEST_BUILD_THREADS=$n"
echo "SUGGEST_PARALLEL_MAKE='-j $parallel_n'"
