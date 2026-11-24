#!/usr/bin/env bash
# 按 threshold.conf 的 SLICE_MAX_BYTES 把 tar 切片，生成 manifest.json（DES-006）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=threshold.conf
. "$SCRIPT_DIR/threshold.conf"

IN=""; OUT_DIR=""; MAX="$SLICE_MAX_BYTES"
while [ $# -gt 0 ]; do
  case "$1" in
    --in) IN="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --max-bytes) MAX="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -f "$IN" ] || { echo "错误: 输入文件不存在: $IN" >&2; exit 2; }
[ -n "$OUT_DIR" ] || { echo "错误: 缺少 --out" >&2; exit 2; }
mkdir -p "$OUT_DIR"

total="$(stat -c %s "$IN")"
slices=$(( (total + MAX - 1) / MAX )); [ "$slices" -lt 1 ] && slices=1

rm -f "$OUT_DIR"/manifest.json "$OUT_DIR"/cache.slice.*
idx=0
while [ "$idx" -lt "$slices" ]; do
  slice="$OUT_DIR/cache.slice.$(printf '%02d' "$idx")"
  dd if="$IN" of="$slice" bs="$MAX" skip="$idx" count=1 status=none
  printf '%s  %s\n' "$(sha256sum "$slice" | cut -d' ' -f1)" "$(basename "$slice")" >> "$OUT_DIR/SHA256SUMS.slice"
  idx=$((idx+1))
done

# manifest.json：序号、字节数、sha256、总片数
printf '{\n  "source": "%s",\n  "total_bytes": %s,\n  "slice_max_bytes": %s,\n  "total_slices": %s,\n  "slices": [\n' \
  "$(basename "$IN")" "$total" "$MAX" "$slices" > "$OUT_DIR/manifest.json"
idx=0
while [ "$idx" -lt "$slices" ]; do
  f="$OUT_DIR/cache.slice.$(printf '%02d' "$idx")"
  printf '    {"index": %d, "bytes": %s, "sha256": "%s"}%s\n' \
    "$idx" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" \
    "$([ "$idx" -lt $((slices-1)) ] && echo ',' || echo '')" >> "$OUT_DIR/manifest.json"
  idx=$((idx+1))
done
printf '  ]\n}\n' >> "$OUT_DIR/manifest.json"

echo "SPLIT_OK slices=$slices total_bytes=$total max=$MAX manifest=$OUT_DIR/manifest.json"
