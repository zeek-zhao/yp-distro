#!/usr/bin/env bash
# M1-S0（AI-001 §2.1 / DES-001）：启动 core-image-minimal ext4 于 QEMU，串口落盘。
# 无 /dev/kvm 时用 TCG（-cpu max 传递 AVX 等扩展，避免 init vzeroupper invalid opcode）；
# 不硬编码 32c/128G，不加 --cpus/--memory 等限制；成功 BOOT_OK，失败 BOOT_FAIL 非 0。
set -uo pipefail

IMAGE=""
MACHINE="qemux86-64"
TIMEOUT=180
LOG=""
KERNEL=""
ROOT_DEV="/dev/vda"

usage() { echo "usage: qemu-run.sh --image <ext4> [--machine qemux86-64] [--timeout <n>] --log <path> [--kernel <path>] [--root <dev>]"; }
die() { echo "BOOT_FAIL reason=$*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --image)   IMAGE="${2:-}"; shift 2 ;;
    --machine) MACHINE="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --log)     LOG="${2:-}"; shift 2 ;;
    --kernel)  KERNEL="${2:-}"; shift 2 ;;
    --root)    ROOT_DEV="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$IMAGE" ] || die "missing --image"
[ -n "$LOG" ] || die "missing --log"
case "$TIMEOUT" in ''|*[!0-9]*) die "invalid --timeout: $TIMEOUT" ;; esac
[ "$TIMEOUT" -gt 0 ] || die "invalid --timeout: $TIMEOUT"
[ "$MACHINE" = "qemux86-64" ] || die "unsupported --machine: $MACHINE（S0 仅 qemux86-64）"

# ---- 资源记录（每次运行实测，不硬编码）----
NPROC="$(nproc 2>/dev/null || echo unknown)"
MEMTOTAL_KB="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo unknown)"
# 仅当本进程确实在容器内（/.dockerenv 存在）时才记录 docker inspect 三项；宿主跑 QEMU 时标 N/A。
if [ -f /.dockerenv ] && command -v docker >/dev/null 2>&1; then
  DOCKER_INSPECT="$(docker inspect --format 'NanoCpus={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}} CpuQuota={{.HostConfig.CpuQuota}}' "$(hostname)" 2>/dev/null | tr -d '\n' || true)"
  [ -n "$DOCKER_INSPECT" ] || DOCKER_INSPECT="N/A(host-is-nested-container)"
else
  DOCKER_INSPECT="N/A(running-on-host)"
fi
echo "RESOURCE nproc=${NPROC} MemTotal_kb=${MEMTOTAL_KB} docker_inspect=${DOCKER_INSPECT}"

# ---- KVM / TCG 判定 ----
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL="kvm"; ACCEL_ARGS=""
else
  ACCEL="tcg"; ACCEL_ARGS="-cpu max"
fi
echo "ACCEL=${ACCEL}（TCG 为软件仿真，不视为硬件加速通过）"

# ---- 工具检查 ----
QEMU="$(command -v qemu-system-x86_64 2>/dev/null || true)"
[ -n "$QEMU" ] || die "qemu-system-x86_64 不在 PATH（提示：apt-get install qemu-system）"
DEBUGFS="$(command -v debugfs 2>/dev/null || true)"

# ---- 镜像检查 ----
[ -f "$IMAGE" ] || die "image not found: $IMAGE"
if command -v file >/dev/null 2>&1; then
  FTYPE="$(file -b "$IMAGE" 2>/dev/null || true)"
  echo "IMAGE_TYPE=${FTYPE}"
  echo "$FTYPE" | grep -qi 'ext4 filesystem' || die "image not ext4: $IMAGE ($FTYPE)"
fi

# ---- 内核：显式 --kernel 或从 ext4 /boot 提取 ----
TMPDIR_RUN="$(mktemp -d /tmp/qemu-run.XXXXXX)" || die "mktemp failed"
cleanup() {
  # 杀本轮 QEMU 进程（若有），等待回收，杜绝僵尸
  if [ -n "${QEMU_PID:-}" ]; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  [ -n "${WATCH_PID:-}" ] && { kill "$WATCH_PID" 2>/dev/null || true; wait "$WATCH_PID" 2>/dev/null || true; }
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT INT TERM

KERNEL_USED="$KERNEL"
if [ -z "$KERNEL_USED" ]; then
  [ -n "$DEBUGFS" ] || die "debugfs 不在 PATH，无法从 ext4 提取内核；请用 --kernel 指定"
  KERNEL_USED="$TMPDIR_RUN/bzImage"
  # ext4 内 /boot/bzImage 是指向 bzImage-<ver>-yocto-standard 的符号链接，debugfs dump 需具体文件名
  KPATH="$(debugfs -R 'ls -l /boot' "$IMAGE" 2>/dev/null | awk '$NF ~ /^bzImage-[0-9]/ {print $NF}' | head -1)"
  [ -n "$KPATH" ] || die "ext4 /boot 未找到 bzImage-<ver>"
  debugfs -R "dump /boot/$KPATH $KERNEL_USED" "$IMAGE" >/dev/null 2>&1 || die "debugfs 提取内核失败: /boot/$KPATH"
fi
[ -s "$KERNEL_USED" ] || die "kernel empty: $KERNEL_USED"
echo "KERNEL=$(basename "$KERNEL_USED") ACCEL=${ACCEL}"

# ---- 启动 QEMU（串口 -> LOG），后台监控 login: ----
: > "$LOG" || die "cannot write log: $LOG"
START_TS="$(date +%s)"
timeout --signal=TERM --kill-after=5s "${TIMEOUT}s" \
  "$QEMU" -m 512 -smp 2 -nographic -no-reboot \
  ${ACCEL_ARGS} \
  -kernel "$KERNEL_USED" \
  -append "console=ttyS0 root=${ROOT_DEV} rw init=/sbin/init" \
  -drive file="$IMAGE",format=raw,if=none,id=hd0 \
  -device virtio-blk-pci,drive=hd0 \
  > "$LOG" 2>&1 &
QEMU_PID=$!

# 监控：串口出现 login: 即视为启动成功，提前终止 QEMU（不必等满 timeout）
(
  while kill -0 "$QEMU_PID" 2>/dev/null; do
    if grep -qi 'login:' "$LOG" 2>/dev/null; then exit 0; fi
    sleep 1
  done
  exit 1
) &
WATCH_PID=$!

wait "$WATCH_PID"; WATCH_RC=$?
ELAPSED=$(( $(date +%s) - START_TS ))

if [ "$WATCH_RC" -eq 0 ] && grep -qi 'login:' "$LOG" 2>/dev/null; then
  # 清理 QEMU（trap 也会兜底）
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  echo "BOOT_OK image=${IMAGE} log=${LOG} timeout=${TIMEOUT}"
  echo "BOOT_ELAPSED=${ELAPSED}s ACCEL=${ACCEL} nproc=${NPROC} MemTotal_kb=${MEMTOTAL_KB}"
  exit 0
else
  echo "BOOT_FAIL reason=no-login-within-timeout elapsed=${ELAPSED}s timeout=${TIMEOUT} accel=${ACCEL}" >&2
  echo "--- log tail ---" >&2
  tail -20 "$LOG" >&2 2>/dev/null || true
  exit 1
fi
