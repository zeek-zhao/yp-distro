#!/usr/bin/env bash
# =============================================================================
# scripts/boot-exec.sh —— 宿主侧入口：起机后在客户机里执行命令并回显结果
#
# 用法：
#   scripts/boot-exec.sh --release <release> [--variant <variant>] [--machine <machine>]
#                        [--timeout <秒>] [--cmd '<客户机命令>']
#
# 与 scripts/qemu.sh 的分工：qemu.sh 只抓启动日志；本脚本经串口自动登录 root 后
# 执行一条命令，用于 L3 现场取证（例如确认 PID 1 真是 systemd、systemd-udevd 在跑）。
#
# 客户机命令的引号不参与宿主侧解析：命令先落盘到 work/logs/guest-cmd-<release>.txt，
# 容器内脚本再读文件，所以带管道/引号/重定向的命令都能原样下发。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/boot-exec.sh --release <release> [--variant <variant>] [--machine <machine>]
                       [--timeout <seconds>] [--cmd '<guest command>']

Options:
  --release <release>  dunfell | kirkstone | scarthgap | wrynose（必填）
  --variant <variant>  general | custom（默认 custom，custom 才有 debug-tweaks 免密登录）
  --machine <machine>  qemux86-64 | qemuarm64（默认 qemux86-64）
  --timeout <seconds>  起机超时（默认 240）
  --cmd '<command>'    在客户机里执行的命令（默认 `ps -ef`）
  -h, --help           显示本帮助
EOF
}

release=""
variant="custom"
machine="qemux86-64"
boot_timeout=240
guest_cmd="ps -ef"
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die "--release 缺少参数"
            release="$2"
            shift 2
            ;;
        --variant)
            (($# >= 2)) || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || die "--timeout 缺少参数"
            boot_timeout="$2"
            shift 2
            ;;
        --cmd)
            (($# >= 2)) || die "--cmd 缺少参数"
            guest_cmd="$2"
            shift 2
            ;;
        -h | --help)
            (($# == 1)) || die "--help 不接受其他参数"
            usage
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
done

[[ -n "${release}" ]] || die "--release 必填"
[[ -f "${ROOT_DIR}/config/${release}.env" ]] ||
    die "release 配置不存在：config/${release}.env"
[[ -f "${ROOT_DIR}/config/variants/${variant}.env" ]] ||
    die "variant 配置不存在：config/variants/${variant}.env"
[[ -f "${ROOT_DIR}/config/machines/${machine}.env" ]] ||
    die "machine 配置不存在：config/machines/${machine}.env"
[[ "${boot_timeout}" =~ ^[0-9]+$ ]] || die "--timeout 必须是整数秒"

variant_env="${ROOT_DIR}/config/variants/${variant}.env"
# YP_IMAGE 允许直接指定镜像配方名（三层镜像验证时用），否则取 variant 配置。
IMAGE="${YP_IMAGE:-$(sed -n 's/^IMAGE=//p' "${variant_env}" | head -1)}"
[[ -n "${IMAGE}" ]] || die "${variant_env} 缺少 IMAGE"

log_dir="${ROOT_DIR}/work/logs"
mkdir -p "${log_dir}"
machine_sfx="$(machine_suffix "${machine}")"
log="${log_dir}/boot-exec-${release}-${variant}${machine_sfx}.log"
cmd_file="${log_dir}/guest-cmd-${release}${machine_sfx}.txt"
serial="${log_dir}/serial-exec-${release}-${variant}${machine_sfx}.log"

printf '%s\n' "${guest_cmd}" >"${cmd_file}"

cd -- "${ROOT_DIR}" || exit 1
{
    printf '=== scripts/boot-exec.sh %s ===\n' "$(date --iso-8601=seconds)"
    printf 'commit  : %s (branch %s)\n' \
        "$(git rev-parse --short HEAD)" "$(git rev-parse --abbrev-ref HEAD)"
    printf 'release : %s / %s / %s\n' "${release}" "${variant}" "${machine}"
    printf 'image   : %s\n' "${IMAGE}"
    printf 'guest   : %s\n\n' "${guest_cmd}"

    ./project.sh shell --release "${release}" --variant "${variant}" --machine "${machine}" -- \
        bash -lc "RELEASE=${release} VARIANT=${variant} IMAGE=${IMAGE} \
            MACHINE=${machine} BOOT_TIMEOUT=${boot_timeout} \
            GUEST_CMD_FILE=/work/work/logs/guest-cmd-${release}${machine_sfx}.txt \
            bash /work/scripts/lib/inner-boot-exec.sh"
} 2>&1 | tee "${log}"

if [[ ! -f "${serial}" ]]; then
    die "串口日志缺失：${serial}"
fi

printf '\n=== 客户机命令输出（%s）===\n' "${guest_cmd}"
sed -n '/__BEGIN__/,/__END__/p' "${serial}" | tr -d '\r'
printf '=== 全量串口日志：%s ===\n' "${serial}"
