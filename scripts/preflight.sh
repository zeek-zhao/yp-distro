#!/usr/bin/env bash
# S4 挂载预检（DES-004 / CHG-002）：只读检查两个卷的存在性、标识、属主与可用空间。
# 本脚本绝不修改目录内容，也不 chown；异常只报告退出码与修复命令。
# 退出码：0 可继续 / 1 其他错误（目录缺失、标识异常、不可写、df 失败）
#         2 属主不符 / 3 空间不足
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/scripts/cache/threshold.conf"

if [ ! -f "$CONF" ]; then
  echo "ERROR[1] CONF_MISSING: 缺少集中配置 $CONF" >&2
  exit 1
fi
# shellcheck source=scripts/cache/threshold.conf
source "$CONF"

DOWNLOADS=""
SSTATE=""
MIN_FREE="${MIN_FREE_BYTES:-}"

usage() {
  cat <<EOF
用法: bash scripts/preflight.sh --downloads <dir> --sstate <dir> [--min-free-bytes <n>]

  --downloads <dir>        下载卷的宿主目录（容器挂载点 /work/downloads）
  --sstate <dir>           缓存卷的宿主目录（容器挂载点 /work/sstate）
  --min-free-bytes <n>     覆盖最小可用空间阈值（仅用于验收模拟，默认取 threshold.conf）

退出码: 0 可继续 / 1 其他错误 / 2 属主不符 / 3 空间不足
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --downloads)
      [ $# -ge 2 ] || { echo "ERROR[1]: --downloads 缺少参数" >&2; exit 1; }
      DOWNLOADS="$2"; shift 2 ;;
    --sstate)
      [ $# -ge 2 ] || { echo "ERROR[1]: --sstate 缺少参数" >&2; exit 1; }
      SSTATE="$2"; shift 2 ;;
    --min-free-bytes)
      [ $# -ge 2 ] || { echo "ERROR[1]: --min-free-bytes 缺少参数" >&2; exit 1; }
      MIN_FREE="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR[1]: 未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$DOWNLOADS" ] || [ -z "$SSTATE" ]; then
  echo "ERROR[1]: 必须同时提供 --downloads 与 --sstate" >&2
  usage >&2
  exit 1
fi
if [ -z "${JENKINS_UID:-}" ] || [ -z "${JENKINS_GID:-}" ] || [ -z "$MIN_FREE" ]; then
  echo "ERROR[1]: threshold.conf 缺少 JENKINS_UID/JENKINS_GID/MIN_FREE_BYTES（见 CHG-002）" >&2
  exit 1
fi

# 只读检查单个卷；返回 0/1/2/3
check_volume() {
  local dir="$1" role="$2"
  local marker owner avail actual_type

  if [ ! -d "$dir" ]; then
    echo "ERROR[1] NOT_FOUND: ${role} 目录不存在: $dir" >&2
    echo "FIX: 先运行 bash scripts/bootstrap.sh --downloads <dir> --sstate <dir>" >&2
    return 1
  fi

  marker="$dir/.yp-volume"
  if [ ! -f "$marker" ]; then
    echo "ERROR[1] BAD_VOLUME: $dir 缺少 .yp-volume 标识，未初始化或挂错卷" >&2
    echo "FIX: 用正确路径运行 bash scripts/bootstrap.sh 重建标识" >&2
    return 1
  fi
  actual_type="$(sed -n 's/^type=//p' "$marker" | head -n 1)"
  if [ "$actual_type" != "$role" ]; then
    echo "ERROR[1] BAD_VOLUME: $dir 的 .yp-volume type='$actual_type'，期望 '$role'（挂错卷）" >&2
    return 1
  fi

  owner="$(stat -c %u "$dir")"
  if [ "$owner" != "$JENKINS_UID" ]; then
    echo "ERROR[2] BAD_OWNER: $dir 属主 UID=$owner，期望 jenkins UID=$JENKINS_UID" >&2
    echo "FIX: chown -R ${JENKINS_UID}:${JENKINS_GID} $dir" >&2
    return 2
  fi

  if [ ! -w "$dir" ]; then
    echo "ERROR[1] NOT_WRITABLE: $dir 对当前用户不可写" >&2
    return 1
  fi

  avail="$(df -PB1 "$dir" | awk 'NR==2 {print $4}')"
  if [ -z "$avail" ]; then
    echo "ERROR[1] DF_FAILED: 无法读取 $dir 的可用空间" >&2
    return 1
  fi
  if [ "$avail" -lt "$MIN_FREE" ]; then
    echo "ERROR[3] LOW_SPACE: $dir 可用 $avail 字节 < 阈值 $MIN_FREE 字节" >&2
    echo "FIX: 清理旧下载/缓存或换用更大的卷" >&2
    return 3
  fi

  echo "OK role=$role dir=$dir owner=$owner avail_bytes=$avail"
  return 0
}

rc=0
check_volume "$DOWNLOADS" downloads || rc=$?
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi
check_volume "$SSTATE" sstate || rc=$?
exit "$rc"
