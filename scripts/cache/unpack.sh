#!/usr/bin/env bash
# 把合并后的缓存 tar 解包到目标目录（DES-006）
set -euo pipefail

IN=""; DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --in) IN="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -f "$IN" ] || { echo "错误: 输入 tar 不存在: $IN" >&2; exit 2; }
[ -n "$DEST" ] || { echo "错误: 缺少 --dest" >&2; exit 2; }
mkdir -p "$DEST"

tar -xf "$IN" -C "$DEST"
echo "UNPACK_OK dest=$DEST entries=$(tar -tf "$IN" | wc -l)"
