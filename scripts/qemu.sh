#!/usr/bin/env bash
# =============================================================================
# scripts/qemu.sh —— 宿主侧入口：在对应 release 容器里 headless 起镜像并抓串口日志
#
# 用法：
#   scripts/qemu.sh --release <release> [--variant <variant>] [--timeout <秒>]
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/qemu.sh --release <release> [--variant <variant>] [--timeout <seconds>]

Options:
  --release <release>  dunfell | kirkstone | scarthgap | wrynose（必填）
  --variant <variant>  general | custom（默认 general）
  --timeout <seconds>  起机超时，超时后用 SIGTERM 收尾（默认 300）
  -h, --help           显示本帮助
EOF
}

release=""
variant="general"
boot_timeout=300
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
        --timeout)
            (($# >= 2)) || die "--timeout 缺少参数"
            boot_timeout="$2"
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
[[ "${boot_timeout}" =~ ^[0-9]+$ ]] || die "--timeout 必须是整数秒"

# 镜像名以 config/variants/<variant>.env 为准（general=core-image-minimal，custom=yp-image），
# 与 kas target 的 target 字段保持一致。
variant_env="${ROOT_DIR}/config/variants/${variant}.env"
IMAGE="$(sed -n 's/^IMAGE=//p' "${variant_env}" | head -1)"
[[ -n "${IMAGE}" ]] || die "${variant_env} 缺少 IMAGE"

log_dir="${ROOT_DIR}/work/logs"
mkdir -p "${log_dir}"
log="${log_dir}/qemu-${release}-${variant}.log"

cd -- "${ROOT_DIR}" || exit 1
{
    printf '=== scripts/qemu.sh %s ===\n' "$(date --iso-8601=seconds)"
    printf 'commit  : %s (branch %s)\n' \
        "$(git rev-parse --short HEAD)" "$(git rev-parse --abbrev-ref HEAD)"
    printf 'release : %s / %s\n' "${release}" "${variant}"
    printf 'image   : %s\n\n' "${IMAGE}"

    ./project.sh shell --release "${release}" --variant "${variant}" -- \
        bash -lc "RELEASE=${release} VARIANT=${variant} IMAGE=${IMAGE} \
            BOOT_TIMEOUT=${boot_timeout} bash /work/scripts/lib/inner-qemu.sh"
} 2>&1 | tee "${log}"
