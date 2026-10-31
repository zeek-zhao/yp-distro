#!/usr/bin/env bash
# =============================================================================
# scripts/lib/inner-boot-exec.sh —— 容器内：起机 → 串口自动登录 → 执行客户机命令
#
# 与 scripts/lib/inner-qemu.sh 的区别：那个只抓启动日志，这个会灌键盘输入，
# 用于 L3 现场取证（`ps` 看 PID 1 / systemd-udevd 之类）。
#
# 由 scripts/boot-exec.sh 经 project.sh shell 注入；环境变量：
#   RELEASE VARIANT IMAGE MACHINE BOOT_TIMEOUT GUEST_CMD_FILE
# =============================================================================
set -uo pipefail

export TERM="${TERM:-dumb}"

RELEASE="${RELEASE:?缺少 RELEASE}"
VARIANT="${VARIANT:?缺少 VARIANT}"
IMAGE="${IMAGE:?缺少 IMAGE}"
MACHINE="${MACHINE:?缺少 MACHINE}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
GUEST_CMD_FILE="${GUEST_CMD_FILE:?缺少 GUEST_CMD_FILE}"

# 命令走文件传递，避免经多层 shell 引号解析
GUEST_CMD="$(head -1 "${GUEST_CMD_FILE}")"
[[ -n "${GUEST_CMD}" ]] || GUEST_CMD="ps -ef"

MACHINE_SUFFIX=""
[[ "${MACHINE}" == "qemux86-64" ]] || MACHINE_SUFFIX="-${MACHINE}"

WORK="/work/work/kas-${RELEASE}-${VARIANT}${MACHINE_SUFFIX}"
# 仓库形态：dunfell/kirkstone/scarthgap 是 poky 组合仓库；wrynose 是三仓拆分
if [[ -d "${WORK}/poky" ]]; then
    OEC="${WORK}/poky"
else
    OEC="${WORK}/openembedded-core"
fi
BUILD="${WORK}/build"

LOG="/work/work/logs/serial-exec-${RELEASE}-${VARIANT}${MACHINE_SUFFIX}.log"
FIFO="/tmp/serial-${RELEASE}${MACHINE_SUFFIX}.fifo"
rm -f "${FIFO}" "${LOG}"
mkfifo "${FIFO}"

# oe-init-build-env 会读 $BBSERVER，本脚本带 set -u 就会 "unbound variable" 退出
# shellcheck disable=SC1091
set +u
source "${OEC}/oe-init-build-env" "${BUILD}" >/dev/null
set -u
cd "${BUILD}" || exit 1

echo "=== boot-exec ${RELEASE}/${VARIANT}/${MACHINE} $(date --iso-8601=seconds)"
echo "workdir : ${WORK}"
echo "image   : ${IMAGE}"
echo "guest   : ${GUEST_CMD}"
echo "timeout : ${BOOT_TIMEOUT}s"
echo "log     : ${LOG}"
echo

# 键盘输入时序：
#  - 45s 时大概率已到 login:，先回车唤醒 getty；
#  - 3.1~5.0 custom 有 debug-tweaks 的空密码后处理，直接进 shell；
#  - 6.0 把它拆成 allow-empty-password/allow-root-login，getty 仍弹 Password:，
#    因此补一个空行（在没有密码提示的版本上只是一次无害回车）；
#  - 末尾长时间 sleep 保持 fifo 写端不关闭，否则 qemu 读到 EOF 会提前退出。
start_writer() {
    {
        sleep 45
        printf '\n'
        sleep 3
        printf '\r\n'
        sleep 2
        printf 'root\r\n'
        sleep 6
        printf '\r\n'
        sleep 4
        printf 'echo __BEGIN__\r\n'
        sleep 3
        printf '%s\r\n' "${GUEST_CMD}"
        sleep 6
        printf 'echo __END__\r\n'
        sleep 4
        printf 'poweroff -f\r\n'
        sleep 200
    } >"${FIFO}" 2>/dev/null &
    writer_pid=$!
}

start_writer

# dunfell 的 runqemu 把第一个位置参数当 machine；kirkstone+ 反过来
if [[ "${RELEASE}" == "dunfell" ]]; then
    RUNQEMU_ARGS=("${MACHINE}" "${IMAGE}")
else
    RUNQEMU_ARGS=("${IMAGE}")
fi

set +e
timeout --signal=TERM --kill-after=20 "${BOOT_TIMEOUT}" \
    runqemu "${RUNQEMU_ARGS[@]}" nographic slirp snapshot <"${FIFO}" >"${LOG}" 2>&1
rc=$?
set -e
kill "${writer_pid}" 2>/dev/null
rm -f "${FIFO}"

# timeout 杀掉后可能留下 qemu 子进程，只匹配本容器的 qemu-system
case "${MACHINE}" in
    qemux86-64) qemu_proc_pattern='qemu-system-x86_64.*qemux86-64' ;;
    qemuarm64) qemu_proc_pattern='qemu-system-aarch64.*qemuarm64' ;;
    *) qemu_proc_pattern="qemu-system.*${MACHINE}" ;;
esac
pkill -f "${qemu_proc_pattern}" 2>/dev/null || true
sleep 1

echo
echo "end     : $(date --iso-8601=seconds)"
echo "runqemu_rc=${rc}（124 = 被 timeout 正常截断）"
if ! grep -q '__BEGIN__' "${LOG}"; then
    echo "WARN: 没有拿到 shell（未见 __BEGIN__ 标记），可能登录失败；串口尾部：" >&2
    tail -20 "${LOG}" | tr -d '\r' >&2
fi
