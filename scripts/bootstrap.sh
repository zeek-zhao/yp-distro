#!/usr/bin/env bash
# S4 挂载初始化（DES-004 / CHG-002）：幂等创建两个宿主卷目录、写 .yp-volume 标识、对齐属主。
# 只补缺失，不清空已有下载/缓存内容；完成后调用 preflight.sh 自检。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/scripts/cache/threshold.conf"

if [ ! -f "$CONF" ]; then
  echo "ERROR: 缺少集中配置 $CONF" >&2
  exit 1
fi
# shellcheck source=scripts/cache/threshold.conf
source "$CONF"

DOWNLOADS=""
SSTATE=""
MIN_FREE=""
START=0
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
CONTAINER="yp-m0-build"

usage() {
  cat <<EOF
用法: bash scripts/bootstrap.sh --downloads <dir> --sstate <dir> [--min-free-bytes <n>] [--start]

  --downloads <dir>        下载卷宿主目录（容器挂载点 /work/downloads）
  --sstate <dir>           缓存卷宿主目录（容器挂载点 /work/sstate）
  --min-free-bytes <n>     覆盖最小可用空间阈值（透传给 preflight 自检）
  --start                  可选：拉起命名持久容器 yp-m0-build（已存在则跳过）

幂等：重复执行只补缺失，不覆盖已有下载/缓存内容，不重复 chown。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --downloads)
      [ $# -ge 2 ] || { echo "ERROR: --downloads 缺少参数" >&2; exit 1; }
      DOWNLOADS="$2"; shift 2 ;;
    --sstate)
      [ $# -ge 2 ] || { echo "ERROR: --sstate 缺少参数" >&2; exit 1; }
      SSTATE="$2"; shift 2 ;;
    --min-free-bytes)
      [ $# -ge 2 ] || { echo "ERROR: --min-free-bytes 缺少参数" >&2; exit 1; }
      MIN_FREE="$2"; shift 2 ;;
    --start)
      START=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: 未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$DOWNLOADS" ] || [ -z "$SSTATE" ]; then
  echo "ERROR: 必须同时提供 --downloads 与 --sstate" >&2
  usage >&2
  exit 1
fi
if [ -z "${JENKINS_UID:-}" ] || [ -z "${JENKINS_GID:-}" ]; then
  echo "ERROR: threshold.conf 缺少 JENKINS_UID/JENKINS_GID（见 CHG-002）" >&2
  exit 1
fi

# 先创建，再取绝对路径（docker -v 需要绝对路径）
mkdir -p "$DOWNLOADS" "$SSTATE"
DOWNLOADS="$(realpath "$DOWNLOADS")"
SSTATE="$(realpath "$SSTATE")"

init_volume() {
  local dir="$1" role="$2"
  local marker cur_uid cur_gid ts

  marker="$dir/.yp-volume"
  if [ -f "$marker" ]; then
    echo "KEEP  $role marker=$marker"
  else
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'type=%s\ncreated_at=%s\nowner=yp-m0\nschema=1\n' "$role" "$ts" > "$marker"
    echo "INIT  $role marker=$marker"
  fi

  cur_uid="$(stat -c %u "$dir")"
  cur_gid="$(stat -c %g "$dir")"
  if [ "$cur_uid" != "$JENKINS_UID" ] || [ "$cur_gid" != "$JENKINS_GID" ]; then
    chown -R "${JENKINS_UID}:${JENKINS_GID}" "$dir"
    echo "CHOWN $dir -> ${JENKINS_UID}:${JENKINS_GID}"
  else
    echo "OWNER_OK $dir (${cur_uid}:${cur_gid})"
  fi
}

init_volume "$DOWNLOADS" downloads
init_volume "$SSTATE" sstate

echo "MOUNTS=-v $DOWNLOADS:/work/downloads -v $SSTATE:/work/sstate"

# 自检：只读 preflight（属主/空间不合格时 bootstrap 应失败）
PREFLIGHT_ARGS=(--downloads "$DOWNLOADS" --sstate "$SSTATE")
if [ -n "$MIN_FREE" ]; then
  PREFLIGHT_ARGS+=(--min-free-bytes "$MIN_FREE")
fi
bash "$ROOT/scripts/preflight.sh" "${PREFLIGHT_ARGS[@]}"

# 可选：拉起持久容器（幂等）；默认不拉起，与 DES-004 §5 验收命令一致
if [ "$START" -eq 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: --start 需要 docker 命令" >&2
    exit 1
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "CONTAINER_EXISTS $CONTAINER (skip)"
  else
    docker run -d --name "$CONTAINER" \
      -v "$DOWNLOADS:/work/downloads" \
      -v "$SSTATE:/work/sstate" \
      "$IMAGE" sleep infinity
    echo "CONTAINER_STARTED $CONTAINER"
  fi
fi
