#!/usr/bin/env bash
# 校验 manifest 后按序合并分片；缺片/sha256 不符/源 sha256 不符直接拒绝（DES-006 / CHG-006）
# SHA256SUMS.slice 已由 CHG-006 移除；若目录中存在旧产物则忽略（不再强制校验）
set -euo pipefail

IN_DIR=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --in) IN_DIR="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -d "$IN_DIR" ] || { echo "错误: 分片目录不存在: $IN_DIR" >&2; exit 2; }
[ -n "$OUT" ] || { echo "错误: 缺少 --out" >&2; exit 2; }

# 1) 清单存在性
for f in manifest.json; do
  [ -f "$IN_DIR/$f" ] || { echo "ERROR: 缺少 $f，拒绝恢复" >&2; exit 1; }
done

# 2) 从 manifest 读取总片数并逐片校验存在性与 sha256
total_slices="$(python3 -c "import json,sys; print(json.load(open('$IN_DIR/manifest.json'))['total_slices'])")"
idx=0
while [ "$idx" -lt "$total_slices" ]; do
  name="cache.slice.$(printf '%02d' "$idx")"
  [ -f "$IN_DIR/$name" ] || { echo "ERROR: 缺片 $name，拒绝恢复" >&2; exit 1; }
  expected="$(python3 -c "import json,sys; d=json.load(open('$IN_DIR/manifest.json')); print(d['slices'][$idx]['sha256'])")"
  actual="$(sha256sum "$IN_DIR/$name" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ] || { echo "ERROR: 分片 $name sha256 不符，拒绝恢复" >&2; exit 1; }
  idx=$((idx+1))
done

# 3) 读取 manifest 中的源文件 sha256（CHG-006 新增；旧 manifest 无此字段时跳过比对）
source_sha="$(python3 -c "import json; d=json.load(open('$IN_DIR/manifest.json')); print(d.get('source_sha256',''))")"

# 4) 按序合并
: > "$OUT"
idx=0
while [ "$idx" -lt "$total_slices" ]; do
  cat "$IN_DIR/cache.slice.$(printf '%02d' "$idx")" >> "$OUT"
  idx=$((idx+1))
done

merged_sha="$(sha256sum "$OUT" | cut -d' ' -f1)"
# 5) 合并结果与源 sha256 比对
if [ -n "$source_sha" ] && [ "$merged_sha" != "$source_sha" ]; then
  echo "ERROR: 合并结果 sha256 ($merged_sha) 与源 sha256 ($source_sha) 不符，拒绝恢复" >&2
  exit 1
fi

echo "MERGE_OK out=$OUT bytes=$(stat -c %s "$OUT") sha256=$merged_sha source_sha256=${source_sha:-N/A}"
