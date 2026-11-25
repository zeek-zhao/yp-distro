#!/usr/bin/env bash
# S4 挂载预检（DES-004 / CHG-002 / T4）：只读检查两个卷的存在性、标识、属主、当前用户可写性与可用空间。
# 本脚本绝不修改目录内容，也不 chown；异常只报告退出码与修复命令。
# 退出码：0 可继续 / 1 其他错误（目录缺失、标识异常、df 失败）
#         2 属主/可写性不符（含目标 UID 与当前 UID 不一致）/ 3 空间不足
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
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
TARGET_UID="$CURRENT_UID"
TARGET_GID="$CURRENT_GID"

uid_mismatch_help() {
  cat >&2 <<EOF
ERROR[2] UID_MISMATCH: 目标 UID:GID=$TARGET_UID:$TARGET_GID 与当前用户 $CURRENT_UID:$CURRENT_GID 不一致。
非 root 用户 chown 到别的 UID 需要 sudo，且 chown 后自己反而不可写（流程自锁）。请选择一条路径：
  路径 1（用 sudo 执行，卷属主保持镜像默认 ${JENKINS_UID}:${JENKINS_GID}）:
    sudo bash scripts/preflight.sh --downloads <dir> --sstate <dir> --uid ${JENKINS_UID} --gid ${JENKINS_GID}
  路径 2（按当前用户重建镜像，卷保持当前用户可写）:
    docker build --build-arg JENKINS_UID=\$(id -u) --build-arg JENKINS_GID=\$(id -g) -t yp-builder:local docker/
    export YP_BUILDER_IMAGE=yp-builder:local
EOF
}

usage() {
  cat <<EOF
用法: bash scripts/preflight.sh --downloads <dir> --sstate <dir> [--uid <n>] [--gid <n>] [--min-free-bytes <n>]

  --downloads <dir>        下载卷的宿主目录（容器挂载点 /work/downloads）
  --sstate <dir>           缓存卷的宿主目录（容器挂载点 /work/sstate）
  --uid <n>                目标 UID（默认当前用户 id -u；镜像默认 JENKINS_UID=${JENKINS_UID:-unset}）
  --gid <n>                目标 GID（默认当前用户 id -g；镜像默认 JENKINS_GID=${JENKINS_GID:-unset}）
  --min-free-bytes <n>     覆盖最小可用空间阈值（仅用于验收模拟，默认取 threshold.conf）

退出码: 0 可继续 / 1 其他错误 / 2 属主或可写性不符 / 3 空间不足
检查: 目录属主 == 目标 UID 且当前用户可写；两者任一不符即 exit 2 并给具体修复命令。
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
    --uid)
      [ $# -ge 2 ] || { echo "ERROR[1]: --uid 缺少参数" >&2; exit 1; }
      TARGET_UID="$2"; shift 2 ;;
    --gid)
      [ $# -ge 2 ] || { echo "ERROR[1]: --gid 缺少参数" >&2; exit 1; }
      TARGET_GID="$2"; shift 2 ;;
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
case "$TARGET_UID" in ''|*[!0-9]*) echo "ERROR[1]: --uid 必须是整数" >&2; exit 1 ;; esac
case "$TARGET_GID" in ''|*[!0-9]*) echo "ERROR[1]: --gid 必须是整数" >&2; exit 1 ;; esac

if [ "$TARGET_UID" != "$CURRENT_UID" ] || [ "$TARGET_GID" != "$CURRENT_GID" ]; then
  if [ "$CURRENT_UID" -ne 0 ]; then
    uid_mismatch_help
    exit 2
  fi
  echo "WARN[2] SUDO_PATH current=${CURRENT_UID}:${CURRENT_GID} target=${TARGET_UID}:${TARGET_GID}（root 执行，chown 后仍可写）"
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
  if [ "$owner" != "$TARGET_UID" ]; then
    echo "ERROR[2] BAD_OWNER: $dir 属主 UID=$owner，期望目标 UID=$TARGET_UID（当前用户 $CURRENT_UID）" >&2
    echo "FIX 1: sudo chown -R ${TARGET_UID}:${TARGET_GID} $dir" >&2
    echo "FIX 2: docker build --build-arg JENKINS_UID=\$(id -u) --build-arg JENKINS_GID=\$(id -g) -t yp-builder:local docker/ && export YP_BUILDER_IMAGE=yp-builder:local" >&2
    return 2
  fi

  if [ ! -w "$dir" ]; then
    echo "ERROR[2] NOT_WRITABLE: $dir 属主为 $TARGET_UID，但当前用户 $CURRENT_UID 不可写（会自锁）" >&2
    echo "FIX 1: sudo chown -R ${CURRENT_UID}:${CURRENT_GID} $dir 后以 --uid ${CURRENT_UID} --gid ${CURRENT_GID} 运行" >&2
    echo "FIX 2: docker build --build-arg JENKINS_UID=\$(id -u) --build-arg JENKINS_GID=\$(id -g) -t yp-builder:local docker/ && export YP_BUILDER_IMAGE=yp-builder:local" >&2
    return 2
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

  echo "OK role=$role dir=$dir owner=$owner current_uid=$CURRENT_UID writable=yes avail_bytes=$avail"
  return 0
}

rc=0
check_volume "$DOWNLOADS" downloads || rc=$?
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi
check_volume "$SSTATE" sstate || rc=$?
exit "$rc"
