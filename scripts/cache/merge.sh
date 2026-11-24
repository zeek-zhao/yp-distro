#!/usr/bin/env bash
# 校验 manifest/SHA256SUMS 后按序合并分片；缺片或 sha256 不符直接拒绝（DES-006）
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

# 3) SHA256SUMS.slice 校验（若存在）
if [ -f "$IN_DIR/SHA256SUMS.slice" ]; then
  ( cd "$IN_DIR" && sha256sum -c SHA256SUMS.slice ) >/dev/null || { echo "ERROR: SHA256SUMS.slice 校验失败" >&2; exit 1; }
fi

# 4) 按序合并
: > "$OUT"
idx=0
while [ "$idx" -lt "$total_slices" ]; do
  cat "$IN_DIR/cache.slice.$(printf '%02d' "$idx")" >> "$OUT"
  idx=$((idx+1))
done

echo "MERGE_OK out=$OUT bytes=$(stat -c %s "$OUT") sha256=$(sha256sum "$OUT" | cut -d' ' -f1)"
