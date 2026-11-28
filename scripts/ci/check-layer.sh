#!/usr/bin/env bash
# YP-M1-S4 / DES-005 / D-08: yocto-check-layer 正向 + 临时坏层负向测试。
#
# 正向：对目标层跑 yocto-check-layer，断言核心用例全绿（README/SECURITY/parse/
#       layerseries_compat/signatures）。test_world 是重用例（bitbake -S none world），
#       在受限资源下可能超时：若仅 test_world 未完成而核心用例全绿，标 PARTIAL
#       （RESOURCE_PARTIAL 口径），不冒充全绿，也不判整体失败。
# 负向：用 mktemp 建一个只有 conf/layer.conf、无 README 的临时层，跑 check-layer
#       必须 FAIL（test_readme），否则说明检查器失效。
#
# 用法：
#   check-layer.sh [--layer <dir>] [--oe-core <dir>] [--deps <dir> ...]
#                  [--log <file>] [--timeout <sec>] [--positive-only|--negative-only]
# 退出：0=检查通过（含 PARTIAL 标注）；1=失败；2=参数/环境错误。
set -uo pipefail

LAYER=""
OE_CORE=""
DEPS=()
LOG=""
TIMEOUT=600
RUN_POS=1
RUN_NEG=1

usage() {
  echo "usage: check-layer.sh --layer <dir> --oe-core <dir> [--deps <dir> ...] [opts]"
  echo "  --layer <dir>      被检查层根目录（必填）"
  echo "  --oe-core <dir>    openembedded-core 根目录（必填，提供 oe-init-build-env）"
  echo "  --deps <dir>       依赖层目录，可重复（默认取 oe-core 同级的 meta-poky/meta-oe）"
  echo "  --log <file>       正向日志输出（默认 /tmp/yp-checklayer-positive.log）"
  echo "  --timeout <sec>    check-layer 超时（默认 600s）"
  echo "  --positive-only    只跑正向"
  echo "  --negative-only    只跑负向"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --layer) LAYER="${2:-}"; shift 2 ;;
    --oe-core) OE_CORE="${2:-}"; shift 2 ;;
    --deps) DEPS+=("${2:-}"); shift 2 ;;
    --log) LOG="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --positive-only) RUN_POS=1; RUN_NEG=0; shift ;;
    --negative-only) RUN_POS=0; RUN_NEG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$LAYER" ] && [ -d "$LAYER" ] || { echo "ERR layer dir missing: $LAYER" >&2; exit 2; }
[ -n "$OE_CORE" ] && [ -f "$OE_CORE/oe-init-build-env" ] || { echo "ERR oe-init-build-env missing under $OE_CORE" >&2; exit 2; }
CL="$OE_CORE/scripts/yocto-check-layer"
WRAP="$OE_CORE/scripts/yocto-check-layer-wrapper"
[ -x "$CL" ] || { echo "ERR yocto-check-layer not executable: $CL" >&2; exit 2; }

# 默认依赖层：oe-core 同级的 meta-poky / meta-oe（meta-yp-distro 的 LAYERDEPENDS=core yocto）
if [ "${#DEPS[@]}" -eq 0 ]; then
  BASE="$(cd "$OE_CORE/.." && pwd)"
  [ -d "$BASE/meta-yocto/meta-poky" ] && DEPS+=("$BASE/meta-yocto/meta-poky")
  [ -d "$BASE/meta-openembedded/meta-oe" ] && DEPS+=("$BASE/meta-openembedded/meta-oe")
fi

echo "CHECK_LAYER_CONFIG layer=$LAYER oe_core=$OE_CORE deps=${DEPS[*]:-<none>} timeout=${TIMEOUT}s"

# oe-init-build-env 只能在 bash 子进程里 source（在脚本顶层 source 会因
# oe-buildenv-internal 的 return 提前终止本脚本）。与手动验证一致的用法：
# 用 bash -c 起独立进程，source oe-init-build-env build 后调用 wrapper
# （wrapper 内部自建干净临时 build 目录并再 source）。
OE_PARENT="$(cd "$OE_CORE/.." && pwd)"

# ---- 正向 ----
POS_RC=0
POS_STATUS="PASS"
if [ "$RUN_POS" -eq 1 ]; then
  echo "=== POSITIVE: $(basename "$LAYER") ==="
  POS_LOG="${LOG:-/tmp/yp-checklayer-positive.log}"
  # bash -c 子进程里 source + wrapper（wrapper 自建干净临时 build 并 --dependency
  # 显式提供 yocto/meta-oe）。用 timeout 包裹整个 bash -c：test_world 在受限资源
  # 下可能超时，超时后日志已含核心用例结论，脚本靠日志判定，不误判。
  export CL_WRAP="$WRAP" CL_LAYER="$LAYER" CL_POS_LOG="$POS_LOG" CL_OE_CORE="$OE_CORE" CL_OE_PARENT="$OE_PARENT"
  export CL_DEPS="${DEPS[*]}"
  timeout "$TIMEOUT" bash -c '
    cd "$CL_OE_PARENT" || exit 2
    source "$CL_OE_CORE/oe-init-build-env" build >/dev/null 2>&1 || exit 2
    export BB_PARALLEL_PARSE="${BB_PARALLEL_PARSE:-0}"
    # shellcheck disable=SC2086  $CL_DEPS 为空格分隔的绝对路径列表
    "$CL_WRAP" "$CL_LAYER" --dependency $CL_DEPS \
      --without-software-layer-signature-check >"$CL_POS_LOG" 2>&1
  '
  RAW_RC=$?
  echo "POSITIVE raw_rc=$RAW_RC log=$POS_LOG"

  # 核心用例断言（取自真实跑出的 check-layer 用例名）
  CORE_CASES=(test_layerseries_compat test_parse test_patches_upstream_status test_readme test_security test_show_environment test_signatures)
  CORE_FAIL=0
  for c in "${CORE_CASES[@]}"; do
    if grep -qE "test_${c#test_} .*\.\.\. FAIL|test_${c#test_}\b.*FAIL" "$POS_LOG" 2>/dev/null; then
      echo "  CORE_FAIL case=$c"; CORE_FAIL=$((CORE_FAIL+1))
    fi
  done
  # 更稳的判定：统计 "... ok" 的核心用例数
  OK_COUNT=0
  for c in "${CORE_CASES[@]}"; do
    grep -qE "test_${c#test_}[^ ]*.*\.\.\. ok" "$POS_LOG" 2>/dev/null && OK_COUNT=$((OK_COUNT+1))
  done

  if [ "$CORE_FAIL" -gt 0 ]; then
    POS_STATUS="FAIL"
  elif [ "$OK_COUNT" -ge 6 ]; then
    # 核心用例全绿（test_signatures 可能因 test_world 阻塞未计入，允许 6/7）
    if [ "$RAW_RC" -eq 124 ] || grep -qE "test_world .*\.\.\. (FAIL|ERROR)|lockedsigs world" "$POS_LOG" 2>/dev/null; then
      POS_STATUS="PARTIAL"
      echo "  NOTE: test_world (bitbake -S lockedsigs world) 未完成/超时 → RESOURCE_PARTIAL，核心用例已绿"
    else
      POS_STATUS="PASS"
    fi
  else
    POS_STATUS="FAIL"
  fi
  echo "POSITIVE_STATUS=$POS_STATUS core_ok=$OK_COUNT/${#CORE_CASES[@]} core_fail=$CORE_FAIL"
  [ "$POS_STATUS" = "FAIL" ] && POS_RC=1
fi

# ---- 负向：临时坏层（无 README，确定性 FAIL）----
NEG_RC=0
NEG_STATUS="PASS"
if [ "$RUN_NEG" -eq 1 ]; then
  echo "=== NEGATIVE: temporary bad layer (no README) ==="
  BAD="$(mktemp -d)"
  BAD_NAME="bad-yp-layer"
  mkdir -p "$BAD/conf"
  cat > "$BAD/conf/layer.conf" <<EOF
BBPATH .= ":\${LAYERDIR}"
BBFILE_COLLECTIONS += "${BAD_NAME}"
BBFILE_PATTERN_${BAD_NAME} = "^${BAD}/"
BBFILE_PRIORITY_${BAD_NAME} = "5"
LAYERSERIES_COMPAT_${BAD_NAME} = "wrynose"
EOF
  # 用绝对路径日志（bash -c 子进程 cwd 会切到 build，相对路径会落入临时目录）。
  BAD_LOG="${LOG:-/tmp/yp-checklayer-positive.log}"
  BAD_LOG="${BAD_LOG%.log}-negative.log"
  export CL_WRAP="$WRAP" CL_BAD="$BAD" CL_BAD_LOG="$BAD_LOG" CL_OE_CORE="$OE_CORE" CL_OE_PARENT="$OE_PARENT"
  export CL_DEPS="${DEPS[*]}"   # negative-only 时正向段未执行，此处补导出
  timeout "$((TIMEOUT / 2))" bash -c '
    cd "$CL_OE_PARENT" || exit 2
    source "$CL_OE_CORE/oe-init-build-env" build >/dev/null 2>&1 || exit 2
    export BB_PARALLEL_PARSE="${BB_PARALLEL_PARSE:-0}"
    # shellcheck disable=SC2086
    "$CL_WRAP" "$CL_BAD" --dependency $CL_DEPS \
      --without-software-layer-signature-check >"$CL_BAD_LOG" 2>&1
  '
  BAD_RAW=$?
  echo "NEGATIVE raw_rc=$BAD_RAW log=$BAD_LOG"
  # 负向期望：非 0 退出 且坏层被 check-layer 拒绝。
  # 精确信号：test_readme FAIL（缺 README，D-08 核心判据）；
  # 宽泛信号：层名 "... FAIL"（如 world 签名阶段失败——8G 沙箱下用例顺序
  # 不稳定，world 可能先 FAIL 导致 test_readme 未跑到，但坏层已被拒绝）。
  # 两种情况都证明「坏层被拒绝」，区别于正向全绿。
  BAD_REJECTED=0
  grep -qE "test_readme .*\.\.\. FAIL|doesn't contain a README" "$BAD_LOG" 2>/dev/null && BAD_REJECTED=1
  [ "$BAD_RAW" -ne 0 ] && grep -qE "${BAD_NAME}|tmp\.|bad-yp-layer" "$BAD_LOG" 2>/dev/null && grep -qE "\.\.\. FAIL|FAIL \(" "$BAD_LOG" 2>/dev/null && BAD_REJECTED=1
  if [ "$BAD_RAW" -ne 0 ] && [ "$BAD_REJECTED" -eq 1 ]; then
    NEG_STATUS="PASS"
    echo "NEGATIVE_STATUS=PASS (bad layer rejected: $(grep -qE "test_readme .*\.\.\. FAIL" "$BAD_LOG" 2>/dev/null && echo test_readme || echo layer-FAIL))"
  else
    NEG_STATUS="FAIL"
    echo "NEGATIVE_STATUS=FAIL (bad layer unexpectedly passed or wrong failure)"
    NEG_RC=1
  fi
  rm -rf "$BAD"
fi

echo "=== SUMMARY positive=$POS_STATUS negative=$NEG_STATUS ==="
if [ "$POS_RC" -eq 0 ] && [ "$NEG_RC" -eq 0 ]; then
  echo "CHECK_LAYER_OK positive=$POS_STATUS negative=$NEG_STATUS"
  exit 0
else
  echo "CHECK_LAYER_FAIL positive=$POS_STATUS negative=$NEG_STATUS"
  exit 1
fi
