#!/usr/bin/env bash
# M1-S3（DES-004）：把宿主已编译的二进制部署到 QEMU 靶机（dev 镜像，含 sshd），
# 经 scp/ssh 走 slirp hostfwd 端口，执行目标机二进制并采集 marker。
# 成功 DEPLOY_OK；失败 DEPLOY_FAIL 非 0。仅 --target qemu；凭证走 debug-tweaks 空密码。
set -uo pipefail

TARGET="qemu"
BINARY=""
USER_NAME="root"
PORT="2222"
DEST="/usr/bin"
IMAGE=""
LOG=""
TIMEOUT=180
QEMU="$(command -v qemu-system-x86_64 2>/dev/null || true)"
HOST="127.0.0.1"
KEEP_TARGET=0
PIDFILE=""

usage() {
  echo "usage: deploy-target.sh --target qemu --binary <path> [--image <ext4>] [opts]"
  echo "  --binary   <path>  宿主已编译二进制（必填）"
  echo "  --image    <ext4>  dev 镜像；给定则脚本自起带 slirp hostfwd 的 QEMU 靶机"
  echo "  --user     <u>     目标用户（默认 root）"
  echo "  --port     <p>     宿主 SSH 端口（默认 2222，hostfwd 到目标 22）"
  echo "  --dest     <dir>   目标部署目录（默认 /usr/bin）"
  echo "  --log      <path>  串口日志（自备靶机时可选）"
  echo "  --timeout  <n>     sshd 就绪轮询超时（默认 180s）"
  echo "  --host     <h>     目标/hostfwd 地址（默认 127.0.0.1）"
  echo "  --keep-target      部署后保持 QEMU 靶机运行（供 gdb-connect 连接）"
  echo "  --pidfile  <path>  把自起 QEMU 的 PID 写入文件（配合 --keep-target）"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="${2:-}"; shift 2 ;;
    --binary)  BINARY="${2:-}"; shift 2 ;;
    --image)   IMAGE="${2:-}"; shift 2 ;;
    --user)    USER_NAME="${2:-}"; shift 2 ;;
    --port)    PORT="${2:-}"; shift 2 ;;
    --dest)    DEST="${2:-}"; shift 2 ;;
    --log)     LOG="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --host)    HOST="${2:-}"; shift 2 ;;
    --keep-target) KEEP_TARGET=1; shift ;;
    --pidfile) PIDFILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "DEPLOY_FAIL reason=$*"; exit 1; }
step() { echo; echo "=== $* ==="; }

[ "$TARGET" = "qemu" ] || fail "unsupported --target: $TARGET（仅 qemu）"
[ -n "$BINARY" ] || fail "missing --binary"
[ -f "$BINARY" ] || fail "binary not found: $BINARY"
[ -x "$BINARY" ] || fail "binary not executable: $BINARY"
case "$TIMEOUT" in ''|*[!0-9]*) fail "invalid --timeout: $TIMEOUT" ;; esac
case "$PORT" in ''|*[!0-9]*) fail "invalid --port: $PORT" ;; esac

command -v ssh >/dev/null 2>&1 || fail "ssh not in PATH"
command -v scp >/dev/null 2>&1 || fail "scp not in PATH"

# ---- SSH 非交互选项：debug-tweaks 下空密码 root 登录 ----
# 优先 BatchMode（none 认证即可成功）；失败时由 SSH_ASKPASS + setsid 喂空密码。
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ConnectTimeout=10 -o PreferredAuthentications=none,password \
  -o NumberOfPasswordPrompts=1 -p "$PORT")
SSH_ADDR="${USER_NAME}@${HOST}"

ssh_cmd() {
  # $*: 远程命令；stdin 继承。先在 BatchMode 下试，失败用 SSH_ASKPASS 空密码兜底。
  local rc
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$SSH_ADDR" "$@" && return 0
  rc=$?
  if [ "$rc" -eq 255 ] || [ "$rc" -eq 1 ]; then
    # 空密码兜底：一次性 askpass 脚本回显空串，setsid 脱离 tty 触发 SSH_ASKPASS
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

scp_cmd() {
  local src="$1" dst="$2" rc
  local SCP_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 -P "$PORT")
  scp -o BatchMode=yes "${SCP_OPTS[@]}" "$src" "${SSH_ADDR}:${dst}" && return 0
  rc=$?
  local askpass
  askpass="$(mktemp /tmp/yp-askpass.XXXXXX)" || return "$rc"
  printf '#!/bin/sh\nprintf "%%s\\n" ""\n' > "$askpass"
  chmod +x "$askpass"
  SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
    setsid scp "${SCP_OPTS[@]}" "$src" "${SSH_ADDR}:${dst}"
  rc=$?
  rm -f "$askpass"
  return "$rc"
}

# ---- 可选：自备 QEMU 靶机（slirp hostfwd :PORT->:22, :5678->:5678） ----
QEMU_PID=""
cleanup() {
  if [ -n "$QEMU_PID" ] && [ "$KEEP_TARGET" -eq 0 ]; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ -n "$IMAGE" ]; then
  [ -f "$IMAGE" ] || fail "image not found: $IMAGE"
  [ -n "$QEMU" ] || fail "qemu-system-x86_64 not in PATH"
  LOGFILE="${LOG:-/tmp/s3-deploy-serial.log}"
  : > "$LOGFILE" || fail "cannot write log: $LOGFILE"
  # 内核从 ext4 /boot 提取（沿用 S0 qemu-run.sh 的探测结论）
  DEBUGFS="$(command -v debugfs 2>/dev/null || true)"
  [ -n "$DEBUGFS" ] || fail "debugfs not in PATH (need to extract kernel)"
  TMPD="$(mktemp -d /tmp/s3-deploy.XXXXXX)" || fail "mktemp failed"
  KPATH="$(debugfs -R 'ls -l /boot' "$IMAGE" 2>/dev/null | awk '$NF ~ /^bzImage-[0-9]/ {print $NF}' | head -1)"
  [ -n "$KPATH" ] || fail "no bzImage-<ver> in ext4 /boot"
  KERNEL="$TMPD/bzImage"
  debugfs -R "dump /boot/$KPATH $KERNEL" "$IMAGE" >/dev/null 2>&1 || fail "kernel extract failed"
  [ -s "$KERNEL" ] || fail "kernel empty"

  step "start QEMU target (TCG, slirp hostfwd ::${PORT}->22, ::5678->5678)"
  # hostfwd 语法：tcp::HOSTPORT-:GUESTPORT（双冒号省略 host addr）；单冒号 tcp:5678-:5678 被 QEMU 8.2 拒绝。
  # ip=dhcp 必须：本镜像 /etc/network/interfaces 只有 lo，guest 无 eth0 IP 时 slirp hostfwd
  # 转发到 guest:22 失败（ssh banner 超时）。内核参数 ip=dhcp 让 slirp 给 eth0 分 10.0.2.15。
  echo "QEMU_CMD $QEMU -m 512 -smp 2 -nographic -no-reboot -cpu max -kernel $KERNEL -append 'console=ttyS0 root=/dev/vda rw init=/sbin/init ip=dhcp' -drive file=$IMAGE,format=raw,if=none,id=hd0 -device virtio-blk-pci,drive=hd0 -netdev user,id=n0,hostfwd=tcp::${PORT}-:22,hostfwd=tcp::5678-:5678 -device virtio-net-pci,netdev=n0"
  "$QEMU" -m 512 -smp 2 -nographic -no-reboot -cpu max \
    -kernel "$KERNEL" \
    -append "console=ttyS0 root=/dev/vda rw init=/sbin/init ip=dhcp" \
    -drive file="$IMAGE",format=raw,if=none,id=hd0 \
    -device virtio-blk-pci,drive=hd0 \
    -netdev user,id=n0,hostfwd=tcp::${PORT}-:22,hostfwd=tcp::5678-:5678 \
    -device virtio-net-pci,netdev=n0 \
    > "$LOGFILE" 2>&1 &
  QEMU_PID=$!
  echo "SERIAL_LOG=$LOGFILE QEMU_PID=$QEMU_PID"

  step "wait sshd on 127.0.0.1:${PORT} (timeout ${TIMEOUT}s)"
  # 不能只用 nc：sshd 首次启动要生成 host key，端口已 LISTEN 但 SSH 握手会 reset。
  # 用真实 ssh 握手探测就绪（BatchMode，空密码 root），握手成功才算 READY。
  READY=0
  for ((i=0; i<TIMEOUT; i++)); do
    if ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$SSH_ADDR" 'true' >/dev/null 2>&1; then READY=1; break; fi
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 1
  done
  [ "$READY" -eq 1 ] || { echo "--- serial tail ---" >&2; tail -20 "$LOGFILE" >&2; fail "sshd not ready on ${HOST}:${PORT} within ${TIMEOUT}s"; }
  echo "SSHD_READY elapsed=${i}s"
else
  step "external target mode (no --image): assume QEMU already running"
fi

BIN_NAME="$(basename "$BINARY")"
REMOTE_PATH="${DEST%/}/${BIN_NAME}"

step "scp $BINARY -> ${SSH_ADDR}:${REMOTE_PATH}"
scp_cmd "$BINARY" "$REMOTE_PATH" || fail "scp failed (dev image has sshd? debug-tweaks empty password?)"
echo "SCP_OK"

step "chmod + execute on target"
ssh_cmd "chmod +x '$REMOTE_PATH'" || fail "chmod failed on target"
# 远端执行加 timeout 兜底：YP_DEMO_STAY 未设时 yp-demo 打印 marker 即退出；
# 自定义二进制若长驻，timeout 20s 后取已输出 marker，不永久阻塞。
TARGET_OUT="$(ssh_cmd "timeout 20 '$REMOTE_PATH'" 2>&1)"
TARGET_RC=$?
echo "$TARGET_OUT"
[ "$TARGET_RC" -eq 0 ] || fail "remote execution failed (rc=$TARGET_RC)"

# marker 断言：目标输出含 YP_DEMO_MARKER（yp-demo 样例）；若调用方自带二进制无 marker，
# 以执行 rc=0 为准并提示 marker 未提供。
if echo "$TARGET_OUT" | grep -q 'YP_DEMO_MARKER'; then
  echo "TARGET_MARKER_OK marker=YP_DEMO_MARKER"
else
  echo "TARGET_MARKER_NOTE no YP_DEMO_MARKER in output (custom binary); execution rc=0"
fi

if [ "$KEEP_TARGET" -eq 1 ] && [ -n "$PIDFILE" ]; then
  echo "$QEMU_PID" > "$PIDFILE"
  echo "TARGET_PIDFILE=$PIDFILE pid=$QEMU_PID"
fi

echo
echo "DEPLOY_OK target=${SSH_ADDR} port=${PORT} binary=${REMOTE_PATH}"
