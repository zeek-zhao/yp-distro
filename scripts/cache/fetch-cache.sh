#!/usr/bin/env bash
# 换机缓存取回（T3 / RV-013；CHG-017 收口）：release 分片重组 或 GHCR 分片合并，校验通过后单层解包到 dest-parent。
# release 归档为 direct（顶层 downloads/ sstate/）；pack.sh 本地产出为 two-stage；GHCR 源 tar（a8870b50…）布局 UNVERIFIED（未拉取验证）。脚本对实际 tar 布局探测。
# 只读 GH_TOKEN 环境变量；公开仓库匿名下载；脚本内不保存任何 token。
# 校验失败 exit 1；校验通过前不解包，所有解包在临时目录完成再 mv，不留半成品。
# CHG-017：重组判断读 manifest.requires_reassembly（缺失回退 layout==two-stage）；官方顺序 fetch → bootstrap → preflight。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="zeek-zhao/yp-distro"
MODE=""; DEST_PARENT=""; WORK=""; RELEASE_TAG=""; MANIFEST=""; PARTS=""
FORCE=0; KEEP=0; DRY_RUN=0; UNPACK_ONLY=""

usage() {
  cat <<EOF
用法: bash scripts/cache/fetch-cache.sh --mode release|ghcr|unpack-only [选项]

公共选项:
  --dest-parent <dir>   目标父目录，其下生成 downloads/ 与 sstate/
  --work <dir>          下载/重组临时区（--keep 时保留）
  --manifest <path>     manifest 路径（release 可省略，按 tag 自动选；ghcr 必填）
  --dry-run             只打印资产 URL/大小/校验期望值，不下载
  --force               允许覆盖非空目标目录
  --keep                保留 work 临时区
  -h|--help

release 模式选项:
  --release-tag <tag>   GitHub release tag（默认取 manifest 的 release_tag）
  --parts <n>           只取前 n 个分片（默认全部）

ghcr 模式:
  --manifest 必填，指向 manifests/full-slices-manifest.json（merge.sh 兼容格式）

unpack-only 模式（本地自测）:
  --unpack-only <tar>   跳过下载，只做布局识别 + 校验后解包（验证两层/直接两种布局）

鉴权: 公开仓库匿名下载；如需鉴权只读取 GH_TOKEN 环境变量，不写入脚本或日志。
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) [ $# -ge 2 ] || die "--mode 缺少参数"; MODE="$2"; shift 2 ;;
    --dest-parent) [ $# -ge 2 ] || die "--dest-parent 缺少参数"; DEST_PARENT="$2"; shift 2 ;;
    --work) [ $# -ge 2 ] || die "--work 缺少参数"; WORK="$2"; shift 2 ;;
    --release-tag) [ $# -ge 2 ] || die "--release-tag 缺少参数"; RELEASE_TAG="$2"; shift 2 ;;
    --manifest) [ $# -ge 2 ] || die "--manifest 缺少参数"; MANIFEST="$2"; shift 2 ;;
    --parts) [ $# -ge 2 ] || die "--parts 缺少参数"; PARTS="$2"; shift 2 ;;
    --unpack-only) [ $# -ge 2 ] || die "--unpack-only 缺少参数"; UNPACK_ONLY="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --keep) KEEP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数 $1（见 --help）" ;;
  esac
done

[ -n "$MODE" ] || die "缺少 --mode（release|ghcr|unpack-only）"
[ -n "$DEST_PARENT" ] || die "缺少 --dest-parent"
[ -n "$WORK" ] || die "缺少 --work"
command -v python3 >/dev/null 2>&1 || die "缺少 python3（manifest 解析需要）"

# 幂等检查（CHG-017/T1）：目标不存在、空目录、或仅含 .yp-volume 视为可写；
# 只要含任何其他条目（含隐藏文件）仍拒绝覆盖。判断无损——不删除 marker。
marker_only() {
  local t="$1" e
  [ -d "$t" ] || return 1                       # 不存在：交给外层按“可写”处理
  while IFS= read -r e; do
    [ "$(basename "$e")" = ".yp-volume" ] || return 1
  done < <(find "$t" -mindepth 1 -print 2>/dev/null)
  return 0
}
check_target() {
  local d t extra
  for d in downloads sstate; do
    t="$DEST_PARENT/$d"
    [ -d "$t" ] || continue                      # 目标不存在 → 可写
    if marker_only "$t"; then
      note "TARGET_OK dir=$t marker-only（.yp-volume 保留，无需 --force）"
      continue
    fi
    extra="$(find "$t" -mindepth 1 ! -name '.yp-volume' -print -quit 2>/dev/null)"
    if [ "$FORCE" -ne 1 ]; then
      die "目标 $t 含非 marker 条目（如 ${extra:-<隐藏或嵌套项>}），拒绝覆盖；--force 会删除整个目标目录（破坏性，不可恢复）"
    fi
    note "WARN --force 将删除整个目标目录 $t（含 ${extra:-非 marker 条目}，破坏性不可恢复）"
  done
}

# 布局识别 + 校验后解包（先临时目录，成功再 mv）
unpack_archive() {
  local tar="$1" stage="$2" first names mode
  names="$(tar -tf "$tar" 2>/dev/null | sed 's#^\./##' | cut -d/ -f1 | sort -u | tr '\n' ' ')"
  case " $names " in
    *" downloads.tar sstate.tar "*)
      mode="two-stage"
      tar -xf "$tar" -C "$stage" || die "外层 tar 解包失败"
      [ -f "$stage/downloads.tar" ] && [ -f "$stage/sstate.tar" ] || die "外层 tar 缺少内层 downloads.tar/sstate.tar"
      tar -xf "$stage/downloads.tar" -C "$stage" || die "downloads.tar 解包失败"
      tar -xf "$stage/sstate.tar" -C "$stage" || die "sstate.tar 解包失败"
      ;;
    *" downloads sstate "*)
      mode="direct"
      case "$tar" in
        *.gz|*.tgz) tar -xzf "$tar" -C "$stage" || die "tar.gz 解包失败" ;;
        *) tar -xf "$tar" -C "$stage" || die "tar 解包失败" ;;
      esac
      ;;
    *) die "未知归档布局（顶层项: ${names:-empty}）；期望 downloads.tar+sstate.tar 或 downloads/+sstate/" ;;
  esac

  [ -d "$stage/downloads" ] || die "解包后缺少 downloads/"
  [ -d "$stage/sstate" ] || die "解包后缺少 sstate/"
  first="$(find "$stage/downloads" -mindepth 1 -print -quit 2>/dev/null)"
  [ -n "$first" ] || die "downloads/ 为空"
  first="$(find "$stage/sstate" -mindepth 1 -print -quit 2>/dev/null)"
  [ -n "$first" ] || die "sstate/ 为空"
  note "STRUCT_OK mode=$mode downloads=$(find "$stage/downloads" -type f | wc -l) sstate=$(find "$stage/sstate" -type f | wc -l)"

  # CHG-017/T1：先保留目标已有的 .yp-volume（归档自身若带 marker 则不覆盖），
  # 再替换目标卷。走到这里的目标已由 check_target 判为不存在/空/仅 marker（或 --force），可安全替换。
  local _d
  for _d in downloads sstate; do
    if [ -f "$DEST_PARENT/$_d/.yp-volume" ] && [ ! -f "$stage/$_d/.yp-volume" ]; then
      cp -a "$DEST_PARENT/$_d/.yp-volume" "$stage/$_d/.yp-volume" || die "保留 $_d marker 失败"
    fi
  done
  rm -rf "$DEST_PARENT/downloads" "$DEST_PARENT/sstate"
  mkdir -p "$DEST_PARENT"
  mv "$stage/downloads" "$DEST_PARENT/downloads" || die "mv downloads 失败"
  mv "$stage/sstate" "$DEST_PARENT/sstate" || die "mv sstate 失败"
  note "UNPACK_OK dest_parent=$DEST_PARENT mode=$mode"
  if [ "$(id -u)" -eq 0 ]; then
    note "OWNER_HINT current_uid=0：归档条目可能带非 1000 属主，请随后执行 bootstrap.sh --uid 1000 --gid 1000 归一属主"
  fi
}

# 下载单个 release 资产并校验大小与 sha256
download_release_asset() {
  local name="$1" bytes="$2" sha="$3" tag="$4" dst="$WORK/$1"
  local url="https://github.com/$REPO/releases/download/$tag/$name"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "ASSET_URL name=$name bytes=$bytes sha256=$sha url=$url"
    return 0
  fi
  local args=(-fL --retry 3 --max-time 3600 -o "$dst")
  if [ -n "${GH_TOKEN:-}" ]; then
    args+=(-H "Authorization: Bearer $GH_TOKEN")
  fi
  curl "${args[@]}" "$url" || die "下载失败: $url"
  local actual_bytes actual_sha
  actual_bytes="$(stat -c %s "$dst")"
  actual_sha="$(sha256sum "$dst" | cut -d' ' -f1)"
  if [ "$actual_bytes" != "$bytes" ] || [ "$actual_sha" != "$sha" ]; then
    die "资产 $name 校验不符: bytes=$actual_bytes/$bytes sha256=$actual_sha/$sha"
  fi
  note "ASSET_OK name=$name bytes=$actual_bytes sha256=$actual_sha"
}

# ISS-025/CHG-016：--work 可能是用户已存在的目录；不得无条件 rm -rf 整个它。
# 仅当 WORK 由本脚本创建时才整体删除；否则只清理本脚本自建的工件与 STAGE。
WORK_CREATED=0
[ -d "$WORK" ] || WORK_CREATED=1
mkdir -p "$WORK"
STAGE="$WORK/.unpack.$$"
mkdir -p "$STAGE"
if [ "$KEEP" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
  if [ "$WORK_CREATED" -eq 1 ]; then
    trap 'rm -rf "$WORK"' EXIT
  else
    trap 'rm -rf "$STAGE" "$WORK/release.env" "$WORK/slices.env" "$WORK"/cache-full.part-* "$WORK/cache-full.tar" "$WORK/cache-full.sha256" "$WORK/cache-full.manifest.json" "$WORK/merged.tar" "$WORK/slices"' EXIT
  fi
fi

case "$MODE" in
  unpack-only)
    [ -n "$UNPACK_ONLY" ] || die "unpack-only 需要 --unpack-only <tar>"
    [ -f "$UNPACK_ONLY" ] || die "tar 不存在: $UNPACK_ONLY"
    check_target
    note "UNPACK_ONLY tar=$UNPACK_ONLY"
    unpack_archive "$UNPACK_ONLY" "$STAGE"
    note "FETCH_OK mode=unpack-only"
    ;;

  release)
    if [ -z "$MANIFEST" ]; then
      tag="${RELEASE_TAG:-m0-s5-payload-full}"
      case "$tag" in
        m0-s5-payload-full) MANIFEST="$ROOT/manifests/cache-full.release.json" ;;
        m0-s5-payload-sample) MANIFEST="$ROOT/manifests/cache-sample.release.json" ;;
        *) die "未知 release tag $tag，请用 --manifest 指定清单" ;;
      esac
    fi
    [ -f "$MANIFEST" ] || die "manifest 不存在: $MANIFEST"
    python3 - "$MANIFEST" > "$WORK/release.env" <<'PY'
import json,sys,shlex
d=json.load(open(sys.argv[1]))
def p(k,v): print('%s=%s'%(k,shlex.quote(str(v))))
p('M_TAG',d.get('release_tag',''))
p('M_LAYOUT',d.get('layout',''))
# CHG-017/T4：requires_reassembly 描述“下载后需合并分片”；缺失时回退旧逻辑 layout==two-stage
_set = 'requires_reassembly' in d
_rr = bool(d['requires_reassembly']) if _set else (d.get('layout','') == 'two-stage')
p('M_REASSEMBLE', 1 if _rr else 0)
p('M_REASSEMBLE_SET', 1 if _set else 0)
p('M_ARCHIVE',d.get('archive_name',''))
p('M_EXPECTED_SHA',d.get('expected_sha256',''))
p('M_EXPECTED_BYTES',d.get('expected_bytes',''))
p('M_CHECKSUM',d.get('checksum_asset',''))
p('M_CHECKSUM_SHA',d.get('checksum_asset_sha256',''))
p('M_CHECKSUM_BYTES',d.get('checksum_asset_bytes',''))
a=d['assets']
p('M_COUNT',len(a))
for i,x in enumerate(a):
    p('A%d_NAME'%i,x['name']); p('A%d_BYTES'%i,x['bytes']); p('A%d_SHA'%i,x['sha256'])
PY
    . "$WORK/release.env" || die "manifest 解析失败"
    tag="${RELEASE_TAG:-$M_TAG}"
    count="$M_COUNT"
    if [ -n "$PARTS" ]; then
      case "$PARTS" in ''|*[!0-9]*) die "--parts 必须是整数" ;; esac
      count="$PARTS"
    fi
    if [ "$count" -lt 1 ] || [ "$count" -gt "$M_COUNT" ]; then die "--parts 超出范围 1..$M_COUNT"; fi
    # CHG-017/T4 一致性校验：防止 layout 与 requires_reassembly 再次漂移（ISS-030）
    if [ "$M_LAYOUT" = "direct" ] && [ "$M_COUNT" -gt 1 ] && [ "$M_REASSEMBLE" -ne 1 ]; then
      die "manifest 不一致：layout=direct 且 assets>1 时必须 requires_reassembly=true（ISS-030）"
    fi
    if [ "$M_LAYOUT" = "two-stage" ] && [ "$M_REASSEMBLE_SET" -eq 1 ] && [ "$M_REASSEMBLE" -eq 0 ]; then
      die "manifest 不一致：layout=two-stage 时 requires_reassembly 不应为 false（ISS-030）"
    fi
    # CHG-017/T4：分片归档只在取全部分片时可重组；部分取片显式拒绝，不再写死 two-stage（ISS-026/030）
    if [ -n "$PARTS" ] && [ "$M_REASSEMBLE" -eq 1 ] && [ "$count" -ne "$M_COUNT" ]; then
      die "分片归档不支持部分取片（requires_reassembly=true，ISS-026/ISS-030）；请取全部分片或改用 sample 归档"
    fi
    if [ "$DRY_RUN" -ne 1 ]; then check_target; fi
    note "MODE_INFO mode=release tag=$tag assets=$count layout=$M_LAYOUT reassemble=$M_REASSEMBLE dry_run=$DRY_RUN"

    i=0
    while [ "$i" -lt "$count" ]; do
      eval "n=\$A${i}_NAME; b=\$A${i}_BYTES; s=\$A${i}_SHA"
      download_release_asset "$n" "$b" "$s" "$tag"
      i=$((i+1))
    done
    if [ "$DRY_RUN" -eq 1 ]; then
      note "EXPECTED_ARCHIVE name=$M_ARCHIVE sha256=$M_EXPECTED_SHA bytes=$M_EXPECTED_BYTES"
      note "DRY_RUN_OK no download performed"
      exit 0
    fi
    note "ASSETS_OK count=$count"

    archive="$WORK/$M_ARCHIVE"
    # CHG-017/T4：是否重组由 requires_reassembly 决定，不再拿 layout 当开关
    if [ "$count" -eq "$M_COUNT" ] && [ "$M_REASSEMBLE" -eq 1 ]; then
      : > "$archive"
      i=0
      while [ "$i" -lt "$count" ]; do
        eval "n=\$A${i}_NAME"
        cat "$WORK/$n" >> "$archive" || die "重组失败: $n"
        i=$((i+1))
      done
      actual_bytes="$(stat -c %s "$archive")"
      if [ "$actual_bytes" != "$M_EXPECTED_BYTES" ]; then
        die "重组字节数 $actual_bytes != 期望 $M_EXPECTED_BYTES"
      fi
      note "REASSEMBLE_OK name=$M_ARCHIVE bytes=$actual_bytes"
      if [ -n "$M_CHECKSUM" ]; then
        download_release_asset "$M_CHECKSUM" "$M_CHECKSUM_BYTES" "$M_CHECKSUM_SHA" "$tag" || die "校验文件下载失败"
        actual_sha="$(sha256sum "$archive" | cut -d' ' -f1)"
        file_sha="$(awk 'NR==1{print $1}' "$WORK/$M_CHECKSUM")"
        if [ "$actual_sha" != "$M_EXPECTED_SHA" ] || [ "$file_sha" != "$M_EXPECTED_SHA" ]; then
          die "重组 tar sha256 不符: actual=$actual_sha file=$file_sha expected=$M_EXPECTED_SHA"
        fi
      else
        actual_sha="$(sha256sum "$archive" | cut -d' ' -f1)"
        [ "$actual_sha" = "$M_EXPECTED_SHA" ] || die "归档 sha256 不符: $actual_sha != $M_EXPECTED_SHA"
      fi
      note "SHA256_OK sha256=$actual_sha"
    else
      eval "n=\$A0_NAME"
      archive="$WORK/$n"
      note "SHA256_OK sha256=$M_EXPECTED_SHA (single asset)"
    fi

    check_target
    unpack_archive "$archive" "$STAGE"
    note "FETCH_OK mode=release tag=$tag"
    ;;

  ghcr)
    [ -n "$MANIFEST" ] || die "ghcr 模式必须提供 --manifest"
    [ -f "$MANIFEST" ] || die "manifest 不存在: $MANIFEST"
    python3 - "$MANIFEST" > "$WORK/slices.env" <<'PY'
import json,sys,shlex
d=json.load(open(sys.argv[1]))
def p(k,v): print('%s=%s'%(k,shlex.quote(str(v))))
p('S_TOTAL',d['total_slices'])
p('S_SRC_SHA',d.get('source_sha256',''))
p('S_TOTAL_BYTES',d.get('total_bytes',''))
for i,x in enumerate(d['slices']):
    p('S%d_INDEX'%i,i)
    p('S%d_BYTES'%i,x['bytes'])
    p('S%d_SHA'%i,x['sha256'])
    p('S%d_IMAGE'%i,x['image'])
    p('S%d_DIGEST'%i,x.get('digest',''))
PY
    . "$WORK/slices.env" || die "manifest 解析失败"
    if [ "$DRY_RUN" -eq 1 ]; then
      note "DRY_RUN mode=ghcr slices=$S_TOTAL source_sha256=$S_SRC_SHA"
      i=0
      while [ "$i" -lt "$S_TOTAL" ]; do
        eval "nn=\$(printf '%02d' \$S${i}_INDEX); im=\$S${i}_IMAGE; dg=\$S${i}_DIGEST; b=\$S${i}_BYTES; s=\$S${i}_SHA"
        note "SLICE_IMAGE index=$nn image=$im digest=$dg bytes=$b sha256=$s"
        i=$((i+1))
      done
      note "DRY_RUN_OK no docker pull performed"
      exit 0
    fi
    command -v docker >/dev/null 2>&1 || die "ghcr 模式需要 docker"
    docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || die "docker daemon 不可用"
    mkdir -p "$WORK/slices"
    cp "$MANIFEST" "$WORK/slices/manifest.json" || die "复制 manifest 失败"
    i=0
    while [ "$i" -lt "$S_TOTAL" ]; do
      eval "nn=\$(printf '%02d' \$S${i}_INDEX); im=\$S${i}_IMAGE; b=\$S${i}_BYTES; s=\$S${i}_SHA"
      docker pull "$im" || die "docker pull 失败: $im"
      note "PULL_OK image=$im"
      cid="$(docker create "$im" true)" || die "docker create 失败: $im"
      docker cp "$cid:/work/slices/cache.slice.$nn" "$WORK/slices/cache.slice.$nn" || { docker rm -f "$cid" >/dev/null 2>&1 || true; die "docker cp 缺片 cache.slice.$nn"; }
      docker rm -f "$cid" >/dev/null 2>&1 || true
      actual_bytes="$(stat -c %s "$WORK/slices/cache.slice.$nn")"
      actual_sha="$(sha256sum "$WORK/slices/cache.slice.$nn" | cut -d' ' -f1)"
      if [ "$actual_bytes" != "$b" ] || [ "$actual_sha" != "$s" ]; then
        die "分片 cache.slice.$nn 校验不符: bytes=$actual_bytes/$b sha256=$actual_sha/$s"
      fi
      note "SLICE_OK index=$nn bytes=$actual_bytes sha256=$actual_sha"
      i=$((i+1))
    done
    bash "$ROOT/scripts/cache/merge.sh" --in "$WORK/slices" --out "$WORK/merged.tar" || die "merge.sh 失败（缺片/哈希不符）"
    check_target
    unpack_archive "$WORK/merged.tar" "$STAGE"
    note "FETCH_OK mode=ghcr"
    ;;

  *) die "未知 --mode $MODE（release|ghcr|unpack-only）" ;;
esac