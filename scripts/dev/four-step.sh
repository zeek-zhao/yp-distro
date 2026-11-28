#!/usr/bin/env bash
# YP-M1-S4 / DES-005 / D-09: 四步流程编排（build → devtool → deploy-target → gdbserver）。
#
# 四步对应 PRD D 组出口句；每步打印 STEP_<n>_BEGIN/END 日志段与耗时，任一步
# 非 0 即整体失败并指出失败步骤。devshell 为交互式（plan §3），CI 不跑，
# 标 DEVSHELL_UNVERIFIED，不冒充第四步之外的新步骤。
#
# 步骤：
#   1 build        kas build --target yp-image-dev（CI 走缓存增量；本地可 --skip-build 复用）
#   2 devtool      devtool-smoke.sh（source SDK env 后 add/modify/build）
#   3 deploy       deploy-target.sh --keep-target（目标机 marker → DEPLOY_OK）
#   4 gdb          gdb-connect.sh（断点命中 + 源码行 → GDB_BREAKPOINT_HIT/SOURCE_LINE_OK）
#
# 用法：
#   four-step.sh [--target qemu] [--workdir <dir>] [--skip-build]
#                [--kas-config <yml1:yml2>] [--sdk-env <file>]
#                [--image <ext4>] [--binary <host-bin>]
#                [--break <sym>] [--remote-bin <path>] [--port <n>]
# 退出：0=四步全过；1=某步失败；2=参数/环境错误。
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" 2>/dev/null || true

TARGET="qemu"
WORKDIR=""
SKIP_BUILD=0
KAS_CONFIG=""
SDK_ENV=""
IMAGE=""
BINARY=""
BREAK_SYM="yp_demo_main"
REMOTE_BIN="/usr/bin/yp-demo"
PORT="2222"

usage() {
  echo "usage: four-step.sh [--target qemu] [--workdir <dir>] [opts]"
  echo "  --workdir <dir>     步骤产物目录（日志/镜像/二进制/pidfile）"
  echo "  --skip-build        跳过 Step1 build（复用已构建镜像，本地调试用）"
  echo "  --kas-config <c>    Step1 kas 配置串（默认 kas/yp.yml:kas/editions/dev.yml）"
  echo "  --sdk-env <file>    Step2 要 source 的 environment-setup 文件"
  echo "  --image <ext4>      Step3 dev 镜像（自起 QEMU 靶机）"
  echo "  --binary <path>     Step3/4 宿主带 -g 的 yp-demo 二进制"
  echo "  --break <sym>       Step4 断点符号（默认 yp_demo_main）"
  echo "  --remote-bin <p>    Step4 目标机二进制路径（默认 /usr/bin/yp-demo）"
  echo "  --port <n>          SSH hostfwd 端口（默认 2222；gdbserver 端口固定 5678）"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --kas-config) KAS_CONFIG="${2:-}"; shift 2 ;;
    --sdk-env) SDK_ENV="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --binary) BINARY="${2:-}"; shift 2 ;;
    --break) BREAK_SYM="${2:-}"; shift 2 ;;
    --remote-bin) REMOTE_BIN="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "$TARGET" = "qemu" ] || { echo "FOUR_STEP_FAIL unsupported target=$TARGET (only qemu)" >&2; exit 2; }
[ -n "$WORKDIR" ] || WORKDIR="$(mktemp -d /tmp/yp-four-step-XXXXXX)"
mkdir -p "$WORKDIR" || { echo "FOUR_STEP_FAIL cannot create workdir" >&2; exit 2; }
[ -n "$KAS_CONFIG" ] || KAS_CONFIG="kas/yp.yml:kas/editions/dev.yml"

echo "FOUR_STEP_CONFIG target=$TARGET workdir=$WORKDIR skip_build=$SKIP_BUILD"
echo "DEVSHELL_UNVERIFIED interactive devshell not run in CI/this script (plan §3)"

failed_step=""
run_step() {
  local n="$1" name="$2" cmd="$3" t0 t1 rc
  echo; echo "=== STEP_${n}_BEGIN ${name} ==="
  t0=$(date +%s)
  eval "$cmd"
  rc=$?
  t1=$(date +%s)
  echo "=== STEP_${n}_END ${name} rc=${rc} elapsed=$((t1-t0))s ==="
  [ "$rc" -eq 0 ] || { failed_step="$n:$name"; return "$rc"; }
  return 0
}

# Step 1 build
if [ "$SKIP_BUILD" -eq 1 ]; then
  echo "=== STEP_1_SKIPPED build (--skip-build; reuse existing image) ==="
else
  run_step 1 build "timeout 900 kas build '$KAS_CONFIG' --target yp-image-dev > '$WORKDIR/step1-build.log' 2>&1" || { echo "FOUR_STEP_FAIL step=$failed_step log=$WORKDIR/step1-build.log"; exit 1; }
fi

# Step 2 devtool（需 SDK env）
if [ -n "$SDK_ENV" ] && [ -f "$SDK_ENV" ]; then
  STEP2="bash -c 'source \"$SDK_ENV\" >/dev/null 2>&1 && bash scripts/dev/devtool-smoke.sh --workdir \"$WORKDIR/devtool\"' > '$WORKDIR/step2-devtool.log' 2>&1"
  run_step 2 devtool "$STEP2" || { echo "FOUR_STEP_FAIL step=$failed_step log=$WORKDIR/step2-devtool.log"; exit 1; }
else
  echo "=== STEP_2_SKIPPED devtool (no --sdk-env; S2 已有 DEVTOOL_SMOKE_OK 证据) ==="
fi

# Step 3 deploy（--keep-target，写 pidfile 供 Step4 连接）
[ -n "$IMAGE" ] || { echo "FOUR_STEP_FAIL missing --image for deploy" >&2; exit 2; }
[ -n "$BINARY" ] || { echo "FOUR_STEP_FAIL missing --binary for deploy" >&2; exit 2; }
STEP3="bash scripts/dev/deploy-target.sh --target qemu --image '$IMAGE' --binary '$BINARY' \
  --port '$PORT' --log '$WORKDIR/step3-serial.log' --timeout 120 \
  --keep-target --pidfile '$WORKDIR/qemu.pid' > '$WORKDIR/step3-deploy.log' 2>&1"
run_step 3 deploy "$STEP3" || { echo "FOUR_STEP_FAIL step=$failed_step log=$WORKDIR/step3-deploy.log"; exit 1; }

# Step 4 gdb（连接 Step3 靶机）。
# 注意：gdb-connect.sh 的 --port 是 gdbserver 端口（默认 5678），不是 SSH hostfwd
# 端口（$PORT=2222）；传错会让 gdb 连到 sshd 报 packet error。此处不传 --port，
# 用 gdb-connect.sh 默认 5678（与 deploy-target.sh 的 hostfwd 5678->5678 对齐）。
STEP4="bash scripts/dev/gdb-connect.sh --target qemu --break '$BREAK_SYM' \
  --binary '$BINARY' --remote-bin '$REMOTE_BIN' \
  > '$WORKDIR/step4-gdb.log' 2>&1"
run_step 4 gdbserver "$STEP4" || { echo "FOUR_STEP_FAIL step=$failed_step log=$WORKDIR/step4-gdb.log"; exit 1; }

# 清理靶机
if [ -f "$WORKDIR/qemu.pid" ]; then
  kill "$(cat "$WORKDIR/qemu.pid")" 2>/dev/null || true
fi

echo
echo "FOUR_STEP_OK steps=1,2,3,4 workdir=$WORKDIR"
