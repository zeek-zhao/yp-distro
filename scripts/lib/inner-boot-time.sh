#!/usr/bin/env bash
# =============================================================================
# scripts/lib/inner-boot-time.sh —— 容器内：起机一次，流式打点，输出三段耗时
#
# 为什么不用「等 qemu 退出后解析日志」：那样只能拿到内核自己的时间戳，
# 墙钟（用户体验的端到端口径）丢了；而墙钟正是对外解释「开机几秒」时唯一站得住的数。
#
# 由 scripts/boot-time.sh 经 project.sh shell 注入；环境变量：
#   RELEASE VARIANT IMAGE MACHINE BOOT_TIMEOUT RUN_INDEX OUT_FILE
# =============================================================================
set -uo pipefail

export TERM="${TERM:-dumb}"

RELEASE="${RELEASE:?缺少 RELEASE}"
VARIANT="${VARIANT:?缺少 VARIANT}"
IMAGE="${IMAGE:?缺少 IMAGE}"
MACHINE="${MACHINE:?缺少 MACHINE}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
OUT_FILE="${OUT_FILE:?缺少 OUT_FILE}"
RUN_INDEX="${RUN_INDEX:-1}"

MACHINE_SUFFIX=""
[[ "${MACHINE}" == "qemux86-64" ]] || MACHINE_SUFFIX="-${MACHINE}"

WORK="/work/work/kas-${RELEASE}-${VARIANT}${MACHINE_SUFFIX}"
# 仓库形态：dunfell/kirkstone/scarthgap 是 poky 组合仓库，oe-init-build-env 在
# ${WORK}/poky 下；wrynose 是三仓拆分，只有 openembedded-core 里有这个文件。
# 写成 ${WORK} 会 source 失败，之后 runqemu 不在 PATH，报 exit 127 ——
# 症状看着像「镜像起不来」，实际是环境没激活。
if [[ -d "${WORK}/poky" ]]; then
    OEC="${WORK}/poky"
else
    OEC="${WORK}/openembedded-core"
fi
BUILD="${WORK}/build"

set +u
# shellcheck disable=SC1090
source "${OEC}/oe-init-build-env" "${BUILD}" >/dev/null
set -u
cd "${BUILD}" || exit 1

LOG_DIR="/work/work/logs"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/serial-boottime-${RELEASE}-${VARIANT}-r${RUN_INDEX}.log"
FIFO="${LOG}.fifo"
MARKS="${LOG}.marks"
rm -f "${LOG}" "${MARKS}" "${MARKS}".* "${FIFO}"
mkfifo "${FIFO}"

echo "=== boot-time ${RELEASE}/${VARIANT} run#${RUN_INDEX} $(date --iso-8601=seconds)"
echo "image : ${IMAGE}"
echo "log   : ${LOG}"

# 写端：等 login 出现后再灌键盘，而不是固定 45s 猜时间点 ——
# 三层镜像的启动时间差好几秒，固定延时必然在一层上过早、在另一层上过晚。
start_writer() {
    {
        for _ in $(seq 1 240); do
            [[ -f "${MARKS}.login" ]] && break
            sleep 1
        done
        sleep 1
        printf '\r\n'
        sleep 2
        printf 'root\r\n'
        sleep 5
        printf '\r\n'
        sleep 3
        printf 'echo __BEGIN__\r\n'
        sleep 2
        printf 'systemd-analyze\r\n'
        sleep 4
        printf 'echo __END__\r\n'
        sleep 3
        printf 'poweroff -f\r\n'
        sleep 120
    } >"${FIFO}" 2>/dev/null &
    writer_pid=$!
}

# 监视端：打点写文件而不是写变量 —— 它跑在 tee 的进程替换里（子 shell），
# 变量赋值回不到父 shell（踩过，别改回变量）。
#
# 为什么不 tail -F 读日志文件：
#   1) getty 的 `... login: ` 提示末尾不带换行，按行读会一直等行尾，
#      等到 qemu 被 kill 才随最后一块输出吐出来，那时 login 早已过去；
#   2) tail 写管道走 stdio 全缓冲，容器里又没有 stdbuf，实时性没有保证。
# 改为直接消费 runqemu 的 stdout 管道：管道无缓冲，read -n 1 逐字符即可实时。
monitor_stream() {
    local buf="" ch now
    while IFS= read -r -n 1 ch; do
        buf+="${ch}"
        if [[ "${buf}" == *"[    0.000000]"* && ! -f "${MARKS}.kernel" ]]; then
            now="$(date +%s%3N)"
            echo "kernel ${now}" >>"${MARKS}"
            : >"${MARKS}.kernel"
        fi
        if [[ "${buf}" == *"Starting kernel"* && ! -f "${MARKS}.loader" ]]; then
            now="$(date +%s%3N)"
            echo "loader ${now}" >>"${MARKS}"
            : >"${MARKS}.loader"
        fi
        if [[ "${buf}" == *"U-Boot 20"* && ! -f "${MARKS}.uboot" ]]; then
            now="$(date +%s%3N)"
            echo "uboot ${now}" >>"${MARKS}"
            : >"${MARKS}.uboot"
        fi
        if [[ "${buf}" == *"login:"* && ! -f "${MARKS}.login" ]]; then
            now="$(date +%s%3N)"
            echo "login ${now}" >>"${MARKS}"
            : >"${MARKS}.login"
        fi
        # 只保留尾部：最长模式不到 20 字符，缓冲没必要越积越大
        ((${#buf} > 2048)) && buf="${buf: -64}"
    done
}

mark() {
    awk -v k="$1" '$1 == k { print $2; exit }' "${MARKS}" 2>/dev/null
}

# dunfell 的 runqemu 把第一个位置参数当 machine；kirkstone+ 反过来
if [[ "${RELEASE}" == "dunfell" ]]; then
    RUNQEMU_ARGS=("${MACHINE}" "${IMAGE}")
else
    RUNQEMU_ARGS=("${IMAGE}")
fi

t0="$(date +%s%3N)"
start_writer

# tee 把同一份输出同时写日志文件与 monitor_stream：monitor 拿到的是运行中的
# 管道数据（无缓冲），日志文件仍然完整，两边都不牺牲。
set +e
timeout --signal=TERM --kill-after=20 "${BOOT_TIMEOUT}" \
    runqemu "${RUNQEMU_ARGS[@]}" nographic slirp snapshot <"${FIFO}" 2>&1 \
    | tee >(monitor_stream) >"${LOG}"
rc=${PIPESTATUS[0]}
set -e

kill "${writer_pid}" 2>/dev/null
rm -f "${FIFO}"

case "${MACHINE}" in
    qemux86-64) qemu_proc_pattern='qemu-system-x86_64.*qemux86-64' ;;
    qemuarm64) qemu_proc_pattern='qemu-system-aarch64.*qemuarm64' ;;
    *) qemu_proc_pattern="qemu-system.*${MACHINE}" ;;
esac
pkill -f "${qemu_proc_pattern}" 2>/dev/null || true

t_kernel="$(mark kernel)"
t_uboot="$(mark uboot)"
t_loader="$(mark loader)"
t_login="$(mark login)"

# 缺 login 就是失败，不能写 0 —— 0 会被当成「极快」混进中位数
if [[ -z "${t_login}" ]]; then
    echo "FAIL: 未见到 login:（runqemu_rc=${rc}），本次不计入" >&2
    tail -15 "${LOG}" | tr -d '\r' >&2
    exit 3
fi

# mode 从容器环境读：拿不到 KVM 时 QEMU 跑的是 TCG，两种口径不可比
mode="${YP_KVM:-unknown}"
[[ "${mode}" == "ok" ]] && mode="kvm"
[[ "${mode}" == "unavailable" ]] && mode="tcg"

python3 - "${t0}" "${t_kernel}" "${t_uboot}" "${t_loader}" "${t_login}" "${mode}" "${LOG}" "${OUT_FILE}" "${RUN_INDEX}" <<'PY'
import json
import pathlib
import re
import sys

t0, t_kernel, t_uboot, t_loader, t_login, mode, log, out, run = sys.argv[1:10]
t0 = int(t0)
t_login = int(t_login)

wall = t_login - t0
kernel = (t_login - int(t_kernel)) if t_kernel else None
uboot = (int(t_loader) - int(t_uboot)) if (t_uboot and t_loader) else None

# 交叉验证：systemd 自己的分段（firmware/loader/kernel/userspace）。
# 串口打点是墙钟口径，systemd-analyze 是内部口径，两个口径对不上说明有段没被算到。
analyze = None
text = pathlib.Path(log).read_text(errors="replace").replace("\r", "")
m = re.search(r"Startup finished in ([^\n]+)", text)
if m:
    analyze = m.group(1).strip()

payload = {
    "mode": mode,
    "run": int(run),
    "wall_ms": wall,
    "kernel_ms": kernel,
    "uboot_ms": uboot,
    "systemd_analyze": analyze,
    "log": log,
}
pathlib.Path(out).write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps(payload, ensure_ascii=False))
PY
