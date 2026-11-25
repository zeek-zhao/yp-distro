#!/usr/bin/env bash
# S5 两次构建测量（DES-005 / RV-005）：在 builder 容器内运行。
# 首次冷构建填充 downloads/sstate；清 build 保留两卷后第二次构建，验证缓存复用。
# 只读 kas 配置，不写死数字常量；所有原始日志保存在 --logs 目录。
set -uo pipefail

WORKDIR="/work/build-run"
LOGS="/work/measure-logs"
EDITION="ci"
MACHINE="qemux86-64"

usage() {
  cat <<EOF
用法: bash scripts/build/measure.sh [--workdir <dir>] [--logs <dir>] [--edition <name>] [--machine <name>]

  --workdir <dir>    容器内工作副本根目录（含 kas/ 与 meta-yp-distro/），默认 /work/build-run
  --logs <dir>       原始日志与计时结果目录，默认 /work/measure-logs
  --edition <name>   kas edition，默认 ci
  --machine <name>   目标机器，默认 qemux86-64

前提：DL_DIR=/work/downloads、SSTATE_DIR=/work/sstate 已由 S4 挂载且属主对齐。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) [ $# -ge 2 ] || { echo "ERROR: --workdir 缺少参数" >&2; exit 1; }; WORKDIR="$2"; shift 2 ;;
    --logs)    [ $# -ge 2 ] || { echo "ERROR: --logs 缺少参数" >&2; exit 1; }; LOGS="$2"; shift 2 ;;
    --edition) [ $# -ge 2 ] || { echo "ERROR: --edition 缺少参数" >&2; exit 1; }; EDITION="$2"; shift 2 ;;
    --machine) [ $# -ge 2 ] || { echo "ERROR: --machine 缺少参数" >&2; exit 1; }; MACHINE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

for d in "$WORKDIR/kas" "$WORKDIR/meta-yp-distro" /work/downloads /work/sstate; do
  if [ ! -d "$d" ]; then
    echo "ERROR: 缺少目录 $d（工作副本或 S4 卷未就绪）" >&2
    exit 1
  fi
done
mkdir -p "$LOGS"

KAS_CFG="kas/yp.yml:editions/${EDITION}.yml"   # CHG-009/ISS-015：cwd 相对 + 根级 editions 链接

# 执行一次构建：清 build 保留两卷；保存 stdout、wall time、退出码与 cooker 日志副本。
run_build() {
  local label="$1"
  local logfile="$LOGS/${label}.log"
  local console_src="$WORKDIR/build/tmp/log/cooker/${MACHINE}/console-latest.log"
  local console_dst="$LOGS/${label}-console.log"
  local t0 t1 rc

  rm -rf "$WORKDIR/build"
  t0="$(date +%s)"
  ( cd "$WORKDIR" && kas build "$KAS_CFG" ) 2>&1 | tee "$logfile"
  rc="${PIPESTATUS[0]}"
  t1="$(date +%s)"

  echo "$((t1 - t0))" > "$LOGS/${label}.seconds"
  echo "$rc" > "$LOGS/${label}.rc"
  if [ -f "$console_src" ]; then
    cp "$console_src" "$console_dst"
  else
    echo "NO_CONSOLE_LOG" > "$console_dst"
  fi

  echo "BUILD_DONE label=$label wall_seconds=$((t1 - t0)) rc=$rc"
  return "$rc"
}

count_pattern() {
  local pattern="$1" file="$2" n
  n="$(grep -c "$pattern" "$file" 2>/dev/null || true)"
  [ -n "$n" ] || n=0
  echo "$n"
}

# 统计并打印一个构建的原始证据行
collect() {
  local label="$1"
  local logfile="$LOGS/${label}.log"
  local console="$LOGS/${label}-console.log"
  local wall rc

  wall="$(cat "$LOGS/${label}.seconds" 2>/dev/null || echo NA)"
  rc="$(cat "$LOGS/${label}.rc" 2>/dev/null || echo NA)"
  echo "=== STATS $label ==="
  echo "wall_seconds=$wall rc=$rc"
  echo "from_sstate_lines=$(count_pattern 'from sstate' "$logfile")"
  echo "reusing_lines=$(count_pattern 'Reusing' "$logfile")"
  echo "fetching_lines=$(count_pattern 'Fetching' "$logfile")"
  echo "--- raw Sstate/Tasks summary lines ($label) ---"
  grep -E "Sstate summary|Tasks Summary" "$console" 2>/dev/null | tail -n 10 || echo "NO_SUMMARY_LINES"
  echo "--- raw from-sstate/Reusing lines ($label, first 10) ---"
  grep -E "from sstate|Reusing" "$console" 2>/dev/null | head -n 10 || echo "NO_MATCHED_LINES"
}

echo "=== MEASURE START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "workdir=$WORKDIR logs=$LOGS edition=$EDITION machine=$MACHINE"
echo "kas_cfg=$KAS_CFG"

if ! run_build first; then
  echo "WARN: 首次构建非零退出，继续采集证据（见 $LOGS/first.log）"
fi
if ! run_build second; then
  echo "WARN: 第二次构建非零退出，继续采集证据（见 $LOGS/second.log）"
fi

collect first
collect second

echo "=== ARTIFACTS ==="
IMAGE_DIR="$WORKDIR/build/tmp/deploy/images/$MACHINE"
if [ -d "$IMAGE_DIR" ]; then
  ls -lh "$IMAGE_DIR"
  echo "--- file output (regular deploy files) ---"
  find "$IMAGE_DIR" -maxdepth 1 -type f ! -name '*.symlink' ! -name '*.txt' \
    -exec file {} \; 2>/dev/null | grep -vE 'ASCII text|empty' | head -n 20 || echo "NO_IMAGE_FILES"
else
  echo "NO_IMAGE_DIR"
fi

echo "=== MEASURE END $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
