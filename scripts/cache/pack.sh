#!/usr/bin/env bash
# 把 download/sstate 目录打包成单一 tar，并生成 SHA256SUMS（DES-006）
set -euo pipefail

SRC_DIRS=()
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC_DIRS+=("$2"); shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ ${#SRC_DIRS[@]} -gt 0 ] || { echo "错误: 至少需要一个 --src" >&2; exit 2; }
[ -n "$OUT" ] || { echo "错误: 缺少 --out" >&2; exit 2; }
for d in "${SRC_DIRS[@]}"; do
  [ -d "$d" ] || { echo "错误: 源目录不存在: $d" >&2; exit 2; }
done

TMPDIR_PACK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_PACK"' EXIT
name="$(basename "$OUT")"

# 逐目录打包进 stage/，保持 downloads/ 与 sstate/ 顶层结构
i=0
for d in "${SRC_DIRS[@]}"; do
  label="$(basename "$d")"
  tar -C "$(dirname "$d")" -cf "$TMPDIR_PACK/${label}.tar" "$label"
  i=$((i+1))
done

# 合并为单一 tar（缓存数据镜像的 payload）
tar -C "$TMPDIR_PACK" -cf "$OUT" .
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > SHA256SUMS )

echo "PACK_OK out=$OUT size=$(stat -c %s "$OUT") sha256=$(sha256sum "$OUT" | cut -d' ' -f1)"
