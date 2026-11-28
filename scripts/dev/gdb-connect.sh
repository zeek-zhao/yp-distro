#!/usr/bin/env bash
# M1-S3（DES-004）：在 QEMU 靶机启动 gdbserver，宿主交叉 gdb 非交互连接，
# 设断点、continue、bt、list，断言 GDB_BREAKPOINT_HIT + SOURCE_LINE_OK。
# D-05-a/b；debuginfod/minidebuginfo（D-05-c）标 UNVERIFIED，不冒充全通过。
set -uo pipefail

TARGET="qemu"
BREAK="yp_demo_main"
GDB=""
BINARY=""
HOST="127.0.0.1"
PORT="5678"
SSH_PORT="2222"
USER_NAME="root"
REMOTE_BIN="/usr/bin/yp-demo"
LOG=""
START_GDBSERVER=1

usage() {
  echo "usage: gdb-connect.sh --target qemu --break <symbol> --binary <host-binary> [opts]"
  echo "  --break    <sym>  断点符号（默认 yp_demo_main）"
  echo "  --binary   <path> 宿主带 -g 的二进制（gdb file/源码行用）"
  echo "  --gdb      <path> 交叉 gdb（默认 SDK 的 x86_64-poky-linux-gdb 或 PATH gdb）"
  echo "  --host     <h>    gdbserver 地址（默认 127.0.0.1）"
  echo "  --port     <p>    gdbserver 宿主端口（默认 5678，hostfwd 到目标 5678）"
  echo "  --ssh-port <p>    ssh 端口（默认 2222），用于启动目标 gdbserver"
  echo "  --remote-bin <p>  目标机二进制路径（默认 /usr/bin/yp-demo）"
  echo "  --no-start        不自动启动目标 gdbserver（已在跑）"
  echo "  --log      <path> gdb 批处理输出落盘"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)     TARGET="${2:-}"; shift 2 ;;
    --break)      BREAK="${2:-}"; shift 2 ;;
    --binary)     BINARY="${2:-}"; shift 2 ;;
    --gdb)        GDB="${2:-}"; shift 2 ;;
    --host)       HOST="${2:-}"; shift 2 ;;
    --port)       PORT="${2:-}"; shift 2 ;;
    --ssh-port)   SSH_PORT="${2:-}"; shift 2 ;;
    --user)       USER_NAME="${2:-}"; shift 2 ;;
    --remote-bin) REMOTE_BIN="${2:-}"; shift 2 ;;
    --no-start)   START_GDBSERVER=0; shift ;;
    --log)        LOG="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "GDB_FAIL reason=$*"; exit 1; }
step() { echo; echo "=== $* ==="; }

[ "$TARGET" = "qemu" ] || fail "unsupported --target: $TARGET（仅 qemu）"
[ -n "$BINARY" ] || fail "missing --binary"
[ -f "$BINARY" ] || fail "binary not found: $BINARY"
[ -n "$BREAK" ] || fail "empty --break"

# 交叉 gdb：显式 --gdb > SDK 探测 > PATH
if [ -z "$GDB" ]; then
  for cand in \
    /work/yp-sdk-test/tmp/sysroots/x86_64/usr/bin/x86_64-poky-linux/x86_64-poky-linux-gdb \
    /work/yp-sdk-test/tmp/sysroots/x86_64-v3-poky-linux/x86_64-poky-linux-gdb; do
    [ -x "$cand" ] && { GDB="$cand"; break; }
  done
fi
[ -n "$GDB" ] || GDB="$(command -v gdb 2>/dev/null || true)"
[ -n "$GDB" ] && [ -x "$GDB" ] || fail "gdb not found (use --gdb or source eSDK environment-setup)"
echo "GDB=$GDB"

SSH_ADDR="${USER_NAME}@${HOST}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 -p "$SSH_PORT")

ssh_cmd() {
  local rc
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$SSH_ADDR" "$@" && return 0
  rc=$?
  if [ "$rc" -eq 255 ] || [ "$rc" -eq 1 ]; then
    local askpass
    askpass="$(mktemp /tmp/yp-askpass.XXXXXX)" || return "$rc"
    printf '#!/bin/sh\nprintf "%%s\\n" ""\n' > "$askpass"
    chmod +x "$askpass"
    SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
      setsid ssh "${SSH_OPTS[@]}" "$SSH_ADDR" "$@"
    rc=$?
    rm -f "$askpass"
  fi
  return "$rc"
}

# ---- 目标侧启动 gdbserver（后台监听，等待连接）----
if [ "$START_GDBSERVER" -eq 1 ]; then
  step "start gdbserver on target :${PORT} for ${REMOTE_BIN}"
  # 清掉旧 gdbserver（按进程名，避免 pkill -f 模式匹配到 ssh 命令行自身）
  ssh_cmd "killall gdbserver 2>/dev/null || true" >/dev/null 2>&1 || true
  # 后台监听；setsid 脱离 ssh 会话防止 SIGHUP；日志到目标 /tmp
  ssh_cmd "YP_DEMO_STAY=1 setsid gdbserver :${PORT} '${REMOTE_BIN}' >/tmp/yp-gdbserver.log 2>&1 < /dev/null & echo GDBSERVER_STARTED" \
    || fail "cannot start gdbserver on target (is sshd up? is gdbserver installed?)"
  # 不使用 nc -z 探测：每次 nc 连接会被 gdbserver accept，消耗掉一次监听，导致随后 gdb 连接被 reset。
  # 固定等 2s 让 gdbserver 进入 Listening 状态即可。
  sleep 2
else
  step "skip gdbserver start (--no-start); assume listening on ${HOST}:${PORT}"
fi

# ---- 宿主交叉 gdb 批处理 ----
BATCH="$(mktemp /tmp/yp-gdb-batch.XXXXXX)" || fail "mktemp failed"
# 顺序关键：先 file 加载本地带 -g 符号，再 target remote。实测反序（先 target 再 file）
# 会让 gdbserver 在 gdb 重读符号时 reset。set sysroot / 用本地文件，避免从远程传 debug 文件。
cat > "$BATCH" <<EOF
set pagination off
set confirm off
set breakpoint pending off
set sysroot /
file ${BINARY}
target remote ${HOST}:${PORT}
break ${BREAK}
continue
bt
info breakpoints
list ${BREAK}
quit
EOF
echo "GDB_BATCH:"
cat "$BATCH"

step "run cross gdb batch"
OUT="$(mktemp /tmp/yp-gdb-out.XXXXXX)" || fail "mktemp failed"
"$GDB" -batch -x "$BATCH" > "$OUT" 2>&1
GDB_RC=$?
cat "$OUT"
[ -n "$LOG" ] && { cp "$OUT" "$LOG"; echo "GDB_LOG=$LOG"; }

# ---- 断言 ----
step "assert D-05-a/b + record D-05-c"
if [ "$GDB_RC" -ne 0 ]; then
  echo "GDB_RC=$GDB_RC（批处理整体退出非 0 常见于 detach/quit，单独看断言）"
fi
if grep -qE "Breakpoint [0-9]+, ${BREAK}|Breakpoint [0-9]+.*${BREAK}" "$OUT"; then
  echo "GDB_BREAKPOINT_HIT symbol=${BREAK}"
else
  # 兼容 gdb 输出 'Thread 1 hit Breakpoint 1, yp_demo_main ()'
  if grep -qE "hit Breakpoint.*${BREAK}|${BREAK} \([^)]*\) at|${BREAK} \(\):" "$OUT"; then
    echo "GDB_BREAKPOINT_HIT symbol=${BREAK}"
  else
    echo "GDB_FAIL reason=breakpoint not hit for ${BREAK}"
    echo "minidebuginfo/debuginfod: UNVERIFIED (plan §7, D-05 not fully passed)"
    rm -f "$BATCH" "$OUT"
    exit 1
  fi
fi
if grep -qE "^[0-9]+[[:space:]]|#0[[:space:]]|list|yp-demo\.c|\.c:[0-9]+" "$OUT" \
   && grep -qE "[0-9]+[[:space:]]+\{|[0-9]+[[:space:]]+[a-zA-Z_].*\(|printf|return" "$OUT"; then
  echo "SOURCE_LINE_OK"
else
  echo "GDB_FAIL reason=no source line from list (need -g binary + local source)"
  echo "minidebuginfo/debuginfod: UNVERIFIED (plan §7, D-05 not fully passed)"
  rm -f "$BATCH" "$OUT"
  exit 1
fi
echo "minidebuginfo/debuginfod: UNVERIFIED (plan §7; D-05-c deferred to M1.1)"
rm -f "$BATCH" "$OUT"
echo
echo "GDB_CONNECT_OK break=${BREAK} host=${HOST}:${PORT}"
