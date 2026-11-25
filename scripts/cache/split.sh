#!/usr/bin/env bash
# 按 threshold.conf 的 SLICE_MAX_BYTES 把 tar 切片，生成 manifest.json（DES-006 / CHG-006）
# 阈值唯一源：不再提供 --max-bytes CLI 覆盖（约束 8）；测试可用 YP_SPLIT_MAX_BYTES（打印 WARN）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=threshold.conf
. "$SCRIPT_DIR/threshold.conf"

MAX="$SLICE_MAX_BYTES"
IN=""; OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --in) IN="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    *) echo "未知参数: $1（注意：--max-bytes 已移除，阈值只来自 threshold.conf）" >&2; exit 2 ;;
  esac
done

[ -f "$IN" ] || { echo "错误: 输入文件不存在: $IN" >&2; exit 2; }
[ -n "$OUT_DIR" ] || { echo "错误: 缺少 --out" >&2; exit 2; }

if [ -n "${YP_SPLIT_MAX_BYTES:-}" ]; then
  echo "WARN: 使用非标准切片阈值 YP_SPLIT_MAX_BYTES=$YP_SPLIT_MAX_BYTES（仅用于测试；常规阈值来自 threshold.conf）" >&2
  MAX="$YP_SPLIT_MAX_BYTES"
fi

mkdir -p "$OUT_DIR"
# F-11：清理旧的 SHA256SUMS.slice 残留与旧分片/清单
rm -f "$OUT_DIR"/manifest.json "$OUT_DIR"/cache.slice.* "$OUT_DIR"/SHA256SUMS.slice

total="$(stat -c %s "$IN")"
source_sha="$(sha256sum "$IN" | cut -d' ' -f1)"
slices=$(( (total + MAX - 1) / MAX )); [ "$slices" -lt 1 ] && slices=1

idx=0
while [ "$idx" -lt "$slices" ]; do
  # ISS-019：不能用 dd bs=$MAX + skip=<片号>——GNU dd 对 >2GiB 的 bs 会按约 2GiB 分块，
  # 使 skip=1 只跳过 ~2GiB 而非第二个 MAX 块，导致大文件切片丢失尾部数据。
  # 用 iflag=skip_bytes,count_bytes 让 skip/count 按字节解释，bs 只影响 I/O 缓冲。
  dd if="$IN" of="$OUT_DIR/cache.slice.$(printf '%02d' "$idx")" \
     bs=1M iflag=skip_bytes,count_bytes skip=$((idx * MAX)) count="$MAX" status=none
  idx=$((idx+1))
done

# manifest.json：新增 source_sha256 供 merge 后与源比对（CHG-006）
printf '{\n  "source": "%s",\n  "source_sha256": "%s",\n  "total_bytes": %s,\n  "slice_max_bytes": %s,\n  "total_slices": %s,\n  "slices": [\n' \
  "$(basename "$IN")" "$source_sha" "$total" "$MAX" "$slices" > "$OUT_DIR/manifest.json"
idx=0
while [ "$idx" -lt "$slices" ]; do
  f="$OUT_DIR/cache.slice.$(printf '%02d' "$idx")"
  printf '    {"index": %d, "bytes": %s, "sha256": "%s"}%s\n' \
    "$idx" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)" \
    "$([ "$idx" -lt $((slices-1)) ] && echo ',' || echo '')" >> "$OUT_DIR/manifest.json"
  idx=$((idx+1))
done
printf '  ]\n}\n' >> "$OUT_DIR/manifest.json"

echo "SPLIT_OK slices=$slices total_bytes=$total source_sha256=$source_sha max=$MAX manifest=$OUT_DIR/manifest.json"
