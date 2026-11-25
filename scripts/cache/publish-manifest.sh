#!/usr/bin/env bash
# 把全量切片 manifest 作为 release 资产持久上传（T5 / CHG-013）。
# 只在 GH_TOKEN 环境变量存在时联网上传；脚本内不保存任何 token；--dry-run 不联网、不伪造成功。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="zeek-zhao/yp-distro"
TAG="m0-s5-payload-full"
MANIFEST="$ROOT/manifests/full-slices-manifest.json"
ASSET="cache-full.manifest.json"
DRY_RUN=0
FORCE=0

usage() {
  cat <<EOF
用法: bash scripts/cache/publish-manifest.sh [--release-tag <tag>] [--manifest <path>] [--asset-name <name>] [--force] [--dry-run]

  --release-tag <tag>   GitHub release tag（默认 m0-s5-payload-full）
  --manifest <path>     要上传的 manifest（默认 manifests/full-slices-manifest.json）
  --asset-name <name>   release 资产名（默认 cache-full.manifest.json）
  --force               同名资产已存在时先删除再上传
  --dry-run             只打印计划与凭据要求，不联网、不上传

鉴权：只读取环境变量 GH_TOKEN；脚本内无 token。公开信息可匿名读，上传必须有 token。
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --release-tag) [ $# -ge 2 ] || die "--release-tag 缺少参数"; TAG="$2"; shift 2 ;;
    --manifest) [ $# -ge 2 ] || die "--manifest 缺少参数"; MANIFEST="$2"; shift 2 ;;
    --asset-name) [ $# -ge 2 ] || die "--asset-name 缺少参数"; ASSET="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数 $1" ;;
  esac
done

[ -f "$MANIFEST" ] || die "manifest 不存在: $MANIFEST"
bytes="$(stat -c %s "$MANIFEST")"
sha="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY_RUN mode=publish-manifest tag=$TAG asset=$ASSET bytes=$bytes sha256=$sha"
  echo "PLAN 1: GET https://api.github.com/repos/$REPO/releases/tags/$TAG -> upload_url"
  echo "PLAN 2: POST https://uploads.github.com/repos/$REPO/releases/<release_id>/assets?name=$ASSET"
  echo "PLAN 3: GET 资产列表确认 $ASSET 存在且 sha256 一致"
  echo "REQUIRES_GH_TOKEN 上传需要环境变量 GH_TOKEN（CI 用 secret GHCR_PAT 之外另设具名 secret）；未执行任何联网操作"
  echo "DRY_RUN_OK no upload performed"
  exit 0
fi

[ -n "${GH_TOKEN:-}" ] || die "缺少 GH_TOKEN 环境变量：上传 release 资产必须有 token；用 --dry-run 预览计划（不伪造成功）"
command -v curl >/dev/null 2>&1 || die "缺少 curl"
command -v python3 >/dev/null 2>&1 || die "缺少 python3"

info="$(curl -sS -m 30 -H "Authorization: Bearer $GH_TOKEN" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG")" || die "查询 release $TAG 失败"
release_id="$(printf '%s' "$info" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id",""))
except Exception: print("")' 2>/dev/null || true)"
upload_url="$(printf '%s' "$info" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("upload_url","").split("{")[0])
except Exception: print("")' 2>/dev/null || true)"
[ -n "$release_id" ] && [ -n "$upload_url" ] || die "无法从 release $TAG 解析 id/upload_url（token 权限不足或 tag 不存在？）"
echo "RELEASE id=$release_id tag=$TAG"

if [ "$FORCE" -ne 1 ]; then
  existing="$(curl -sS -m 30 -H "Authorization: Bearer $GH_TOKEN" \
    "https://api.github.com/repos/$REPO/releases/$release_id/assets" 2>/dev/null)" || die "查询资产列表失败"
  if printf '%s' "$existing" | python3 -c 'import json,sys,os
name=os.environ["N"]
try: sys.exit(0 if any(a["name"]==name for a in json.load(sys.stdin)) else 1)
except Exception: sys.exit(1)' N="$ASSET"; then
    die "资产 $ASSET 已存在；如需替换请加 --force"
  fi
else
  existing="$(curl -sS -m 30 -H "Authorization: Bearer $GH_TOKEN" \
    "https://api.github.com/repos/$REPO/releases/$release_id/assets" 2>/dev/null)" || die "查询资产列表失败"
  asset_id="$(printf '%s' "$existing" | python3 -c 'import json,sys,os
name=os.environ["N"]
try:
    print(next((a["id"] for a in json.load(sys.stdin) if a["name"]==name), ""))
except Exception: print("")' N="$ASSET" 2>/dev/null || true)"
  if [ -n "$asset_id" ]; then
    curl -sS -m 30 -X DELETE -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/repos/$REPO/releases/assets/$asset_id" >/dev/null || die "删除旧资产 $ASSET 失败"
    echo "DELETED old asset=$ASSET id=$asset_id"
  fi
fi

resp="$(curl -sS -m 120 -X POST -H "Authorization: Bearer $GH_TOKEN" \
  -H "Content-Type: application/json" --data-binary "@$MANIFEST" \
  "${upload_url}?name=${ASSET}")" || die "上传资产失败"
uploaded_sha="$(printf '%s' "$resp" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("digest","").split(":",1)[-1])
except Exception: print("")' 2>/dev/null || true)"
if [ -z "$uploaded_sha" ] || [ "$uploaded_sha" != "$sha" ]; then
  die "上传结果未返回可核对的 sha256（got=${uploaded_sha:-none} expected=$sha）"
fi
echo "UPLOAD_OK tag=$TAG asset=$ASSET bytes=$bytes sha256=$uploaded_sha"
