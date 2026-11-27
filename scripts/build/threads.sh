#!/usr/bin/env bash
# M0.1.1（AI-009 §2.1）：按 Docker daemon 实际可见 CPU/内存分级，输出分级诊断与建议并发值。
# 只读脚本：不启动容器、不写文件、不下载。daemon 不可用时 exit 1，不静默回退。
# 唯一分级实现：verify-env.sh 的 SUGGEST_* 亦调用本脚本，不重复阈值表。
# 实际构建并发由 kas/base.yml 的 oe.utils.cpu_count() 动态取（ISS-037：kas 隔离
# bitbake server 的 os.environ，环境变量注入无法进 datastore）；本脚本输出的
# YP_BUILD_THREADS/YP_PARALLEL_MAKE 供诊断/文档记录，分级表与 cpu_count 结果一致。
set -uo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker 不可用，无法读取 daemon 资源"
docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || die "docker daemon 不可用"

cpus="$(docker info --format '{{.NCPU}}' 2>/dev/null)"
mem_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null)"
[ -n "$cpus" ] && [ "$cpus" -gt 0 ] 2>/dev/null || die "docker info NCPU 无效: ${cpus:-<empty>}"
[ -n "$mem_bytes" ] && [ "$mem_bytes" -gt 0 ] 2>/dev/null || die "docker info MemTotal 无效: ${mem_bytes:-<empty>}"
mem_gb=$((mem_bytes / 1024 / 1024 / 1024))

# 分级表（AI-009 §2.1）：standard / mid / small / legacy
if [ "$cpus" -ge 32 ] && [ "$mem_gb" -ge 120 ]; then
  tier="standard"; threads="32"; parallel="-j 16"
elif [ "$cpus" -ge 16 ] && [ "$mem_gb" -ge 32 ]; then
  tier="mid"; threads="16"; parallel="-j 8"
elif [ "$cpus" -ge 8 ] && [ "$mem_gb" -ge 16 ]; then
  tier="small"; threads="8"; parallel="-j 4"
else
  tier="legacy"; threads="4"; parallel="-j 2"
fi

# 显式环境覆盖：YP_BUILD_THREADS 须正整数；YP_PARALLEL_MAKE 须 '-j <正整数>'
if [ -n "${YP_BUILD_THREADS:-}" ]; then
  case "$YP_BUILD_THREADS" in
    ''|*[!0-9]*) die "YP_BUILD_THREADS 必须为正整数，实际: '$YP_BUILD_THREADS'" ;;
  esac
  [ "$YP_BUILD_THREADS" -gt 0 ] 2>/dev/null || die "YP_BUILD_THREADS 必须为正整数，实际: '$YP_BUILD_THREADS'"
  threads="$YP_BUILD_THREADS"
fi
if [ -n "${YP_PARALLEL_MAKE:-}" ]; then
  case "$YP_PARALLEL_MAKE" in
    -j[[:space:]]*)
      mk_n="$(printf '%s' "$YP_PARALLEL_MAKE" | awk '{print $2}')"
      case "$mk_n" in
        ''|*[!0-9]*) die "YP_PARALLEL_MAKE 必须为 '-j <正整数>'，实际: '$YP_PARALLEL_MAKE'" ;;
      esac
      [ "$mk_n" -gt 0 ] 2>/dev/null || die "YP_PARALLEL_MAKE 必须为 '-j <正整数>'，实际: '$YP_PARALLEL_MAKE'"
      parallel="-j $mk_n"
      ;;
    *) die "YP_PARALLEL_MAKE 必须为 '-j <正整数>'，实际: '$YP_PARALLEL_MAKE'" ;;
  esac
fi

echo "RESOURCE_TIER=$tier"
echo "RESOURCE_CORES=$cpus"
echo "RESOURCE_MEM_GB=$mem_gb"
echo "export YP_BUILD_THREADS=$threads"
echo "export YP_PARALLEL_MAKE='$parallel'"
