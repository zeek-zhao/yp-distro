#!/usr/bin/env bash
# S4 挂载初始化（DES-004 / CHG-002 / T4）：幂等创建两个宿主卷目录、写 .yp-volume 标识、对齐属主。
# 只补缺失，不清空已有下载/缓存内容；完成后调用 preflight.sh 自检。
# T4：目标 UID/GID 默认取当前用户；与当前非 root 用户不一致时拒绝执行并给两条修复路径，禁止静默 chown。
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
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"
TARGET_UID="$CURRENT_UID"
TARGET_GID="$CURRENT_GID"

uid_mismatch_help() {
  cat >&2 <<EOF
ERROR[2] UID_MISMATCH: 目标 UID:GID=$TARGET_UID:$TARGET_GID 与当前用户 $CURRENT_UID:$CURRENT_GID 不一致。
非 root 用户 chown 到别的 UID 需要 sudo，且 chown 后自己反而不可写（流程自锁）。请选择一条路径：
  路径 1（用 sudo 执行，卷属主保持镜像默认 ${JENKINS_UID}:${JENKINS_GID}）:
    sudo bash scripts/bootstrap.sh --downloads <dir> --sstate <dir> --uid ${JENKINS_UID} --gid ${JENKINS_GID}
  路径 2（按当前用户重建镜像，卷保持当前用户可写）:
    docker build --build-arg JENKINS_UID=\$(id -u) --build-arg JENKINS_GID=\$(id -g) -t yp-builder:local docker/
    export YP_BUILDER_IMAGE=yp-builder:local
    bash scripts/bootstrap.sh --downloads <dir> --sstate <dir>
EOF
}

usage() {
  cat <<EOF
用法: bash scripts/bootstrap.sh --downloads <dir> --sstate <dir> [--uid <n>] [--gid <n>] [--min-free-bytes <n>] [--start]

  --downloads <dir>        下载卷宿主目录（容器挂载点 /work/downloads）
  --sstate <dir>           缓存卷宿主目录（容器挂载点 /work/sstate）
  --uid <n>                目标 UID（默认当前用户 id -u；镜像默认 JENKINS_UID=${JENKINS_UID:-unset}）
  --gid <n>                目标 GID（默认当前用户 id -g；镜像默认 JENKINS_GID=${JENKINS_GID:-unset}）
  --min-free-bytes <n>     覆盖最小可用空间阈值（透传给 preflight 自检）
  --start                  可选：拉起命名持久容器 yp-m0-build（已存在则跳过）

幂等：重复执行只补缺失，不覆盖已有下载/缓存内容，不重复 chown。
当前用户为 1000 时，默认行为与 M0 验收命令完全一致（chown 到 1000:1000）。
目标 UID/GID 与当前非 root 用户不一致时 exit 2，并给出 sudo / 重建镜像两条路径。
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
    --uid)
      [ $# -ge 2 ] || { echo "ERROR: --uid 缺少参数" >&2; exit 1; }
      TARGET_UID="$2"; shift 2 ;;
    --gid)
      [ $# -ge 2 ] || { echo "ERROR: --gid 缺少参数" >&2; exit 1; }
      TARGET_GID="$2"; shift 2 ;;
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
case "$TARGET_UID" in ''|*[!0-9]*) echo "ERROR: --uid 必须是整数" >&2; exit 1 ;; esac
case "$TARGET_GID" in ''|*[!0-9]*) echo "ERROR: --gid 必须是整数" >&2; exit 1 ;; esac

# T4：非 root 用户不得 chown 到别的 UID（会把自己锁在目录外）
if [ "$TARGET_UID" != "$CURRENT_UID" ] || [ "$TARGET_GID" != "$CURRENT_GID" ]; then
  if [ "$CURRENT_UID" -ne 0 ]; then
    uid_mismatch_help
    exit 2
  fi
  echo "WARN SUDO_PATH current=${CURRENT_UID}:${CURRENT_GID} target=${TARGET_UID}:${TARGET_GID}（root 执行，chown 后仍可写）"
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
  if [ "$cur_uid" != "$TARGET_UID" ] || [ "$cur_gid" != "$TARGET_GID" ]; then
    chown -R "${TARGET_UID}:${TARGET_GID}" "$dir"
    echo "CHOWN $dir -> ${TARGET_UID}:${TARGET_GID}"
  else
    echo "OWNER_OK $dir (${cur_uid}:${cur_gid})"
  fi
}

init_volume "$DOWNLOADS" downloads
init_volume "$SSTATE" sstate

echo "MOUNTS=-v $DOWNLOADS:/work/downloads -v $SSTATE:/work/sstate"

# 自检：只读 preflight（属主/空间不合格时 bootstrap 应失败）
PREFLIGHT_ARGS=(--downloads "$DOWNLOADS" --sstate "$SSTATE" --uid "$TARGET_UID" --gid "$TARGET_GID")
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
