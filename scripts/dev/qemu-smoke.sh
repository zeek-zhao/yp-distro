#!/usr/bin/env bash
# M1-S0（AI-001 §2.2 / DES-001）：调用 qemu-run.sh 并断言串口日志出现登录提示。
# 成功 QEMU_SMOKE_OK，失败 QEMU_SMOKE_FAIL 非 0；坏镜像/不存在镜像须非 0（负向）。
set -uo pipefail

RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qemu-run.sh"
IMAGE=""
LOG=""
TIMEOUT=180
SMOKE_MARKER="login:"

usage() { echo "usage: qemu-smoke.sh --image <ext4> [--log <path>] [--timeout <n>] [--marker <str>]"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --image)   IMAGE="${2:-}"; shift 2 ;;
    --log)     LOG="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --marker)  SMOKE_MARKER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "QEMU_SMOKE_FAIL reason=$*"; exit 1; }

[ -f "$RUN" ] || fail "missing qemu-run.sh: $RUN"
[ -n "$IMAGE" ] || fail "missing --image"
[ -n "$LOG" ] || fail "missing --log"

if ! bash "$RUN" --image "$IMAGE" --timeout "$TIMEOUT" --log "$LOG"; then
  fail "qemu-run.sh failed for image=$IMAGE"
fi

if grep -qi -- "$SMOKE_MARKER" "$LOG" 2>/dev/null; then
  echo "QEMU_SMOKE_OK image=${IMAGE} log=${LOG} marker=${SMOKE_MARKER}"
  grep -n -- "$SMOKE_MARKER" "$LOG" | head -3
  exit 0
else
  fail "no marker '${SMOKE_MARKER}' in log=${LOG}"
fi
