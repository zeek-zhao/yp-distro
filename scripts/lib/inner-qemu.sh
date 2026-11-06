#!/usr/bin/env bash
# =============================================================================
# scripts/lib/inner-qemu.sh —— 在 release 容器内执行：headless 启动镜像并抓串口日志
#
# 由 scripts/qemu.sh 通过 project.sh shell 注入；下列变量由调用方传入：
#   RELEASE VARIANT IMAGE MACHINE [BOOT_TIMEOUT]
# =============================================================================
set -uo pipefail

# tmux 以脚本方式拉起时没有 TERM，runqemu 内部的 tput 会报 "No value for $TERM"
export TERM="${TERM:-dumb}"

RELEASE="${RELEASE:?缺少 RELEASE}"
VARIANT="${VARIANT:?缺少 VARIANT}"
IMAGE="${IMAGE:?缺少 IMAGE}"
MACHINE="${MACHINE:?缺少 MACHINE}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"

# 与 build.sh 的命名规则一致：默认 machine 不加后缀。
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
ART_DIR="/work/work/artifacts/${RELEASE}/${VARIANT}${MACHINE_SUFFIX}"
LOG="${ART_DIR}/qemu-serial.log"

mkdir -p "${ART_DIR}"
rm -f "${LOG}"

echo "=== QEMU 启动 ==="
echo "hostname: $(hostname)"
echo "workdir : ${WORK}"
echo "image   : ${IMAGE}"
echo "machine : ${MACHINE}"
echo "timeout : ${BOOT_TIMEOUT}s"
echo "log     : ${LOG}"
echo "start   : $(date --iso-8601=seconds)"
echo

# runqemu 需要 qemu-native / qemu-helper-native 在 native sysroot 里。
# oe-init-build-env 第 29 行会读 $BBSERVER，本脚本带 set -u 就会直接
# "BBSERVER: unbound variable" 退出，所以 source 前后临时关掉 -u。
# shellcheck disable=SC1091
set +u
source "${OEC}/oe-init-build-env" "${BUILD}" >/dev/null
set -u
cd "${BUILD}" || exit 1

if ! bitbake qemu-helper-native >"${ART_DIR}/qemu-helper.log" 2>&1; then
    echo "ERROR: bitbake qemu-helper-native 失败，见 ${ART_DIR}/qemu-helper.log" >&2
    tail -20 "${ART_DIR}/qemu-helper.log" >&2
    exit 1
fi
echo "qemu-helper-native: OK"

# 三个实测约束：
#  1) dunfell(3.1) 的 runqemu 把第一个位置参数当 machine，必须写成
#     `runqemu qemux86-64 <image> ...`；
#  2) kirkstone(4.0)+ 反过来：多传 machine 会让 IMAGE_LINK_NAME 取不到（见 docs/qa）；
#  3) wrynose 的 IMAGE_FSTYPES 是 ext4.zst / tar.zst，runqemu 对 .zst 只支持 snapshot 模式。
if [[ "${RELEASE}" == "dunfell" ]]; then
    RUNQEMU_ARGS=("${MACHINE}" "${IMAGE}")
else
    RUNQEMU_ARGS=("${IMAGE}")
fi
# YP_RUNQEMU_EXTRA：宿主侧可透传 runqemu 位置参数（如 dm-verity 路线一的
# "ovmf"——runqemu 原生支持，自动找 ovmf.qcow2 并挂 pflash，见 #117）
set +e
timeout --signal=TERM --kill-after=30 "${BOOT_TIMEOUT}" \
    runqemu "${RUNQEMU_ARGS[@]}" nographic snapshot slirp ${YP_RUNQEMU_EXTRA:-} 2>&1 | tee "${LOG}"
rc=$?
set -e

# timeout 杀掉后可能留下 qemu 子进程，清干净（只匹配本容器的 qemu-system）
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
if grep -qi 'login:' "${LOG}"; then
    echo "LOGIN_PROMPT=yes"
    grep -i -m1 'login:' "${LOG}"
else
    echo "LOGIN_PROMPT=no"
fi
echo "serial_bytes=$(stat -c %s "${LOG}" 2>/dev/null || echo 0)"
