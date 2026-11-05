#!/usr/bin/env bash
# =============================================================================
# scripts/deploy-guard.sh —— 构建产物新鲜度门禁（#114）
#
#   scripts/deploy-guard.sh --all
#   scripts/deploy-guard.sh --release <r> --variant <v> [--machine <m>]
#
# 检查 work/kas-* 构建目录里的指纹戳（build.sh 构建成功时写入 .yp-fingerprint）
# 是否等于当前源码指纹。不匹配 = 产物是旧代码构建的，用它起机/出报告会把
# 旧状态的数据当成新状态（两次真实事故：#109 的 deploy 新旧 rpm 混存把
# do_rootfs 冲突伪装成配方问题；kas feature overlay 残留 qemuboot.conf 让
# boot-exec 掉进 U-Boot shell）。
#
# 边界（有意为之）：
#   * 构建目录不存在 → 安静通过（CI 上没有构建机状态）。
#   * 指纹材料不含 kas/：overlay 是实验开关，overlay 构建后的产物会被判成
#     stale——正确行为，残留的 qemuboot.conf 正是该拦的东西。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'USAGE'
用法：
  scripts/deploy-guard.sh --all
  scripts/deploy-guard.sh --release <r> --variant <v> [--machine <m>]

  --all                      检查所有 work/kas-* 构建目录
  --release/--variant/--machine  只检查指定组合（machine 缺省 qemux86-64，
                             非 qemux86-64 的组合目录带 machine 后缀）

退出码：0 = 全部新鲜或无构建目录；1 = 存在 stale 目录或用法错误（die 惯例）
USAGE
}

release="" variant="" machine=""
all=0
while (($# > 0)); do
    case "$1" in
        --all)
            all=1
            shift
            ;;
        --release)
            [[ $# -ge 2 ]] || die "--release 缺少参数"
            release="$2"
            shift 2
            ;;
        --variant)
            [[ $# -ge 2 ]] || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --machine)
            [[ $# -ge 2 ]] || die "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1（--help 看用法）" ;;
    esac
done

if ((all)) && [[ -n "${release}${variant}${machine}" ]]; then
    die "--all 不能与 --release/--variant/--machine 同用"
fi
if ((all == 0)); then
    [[ -n "${release}" && -n "${variant}" ]] || {
        usage
        die "必须指定 --release 和 --variant（或 --all）"
    }
    machine="${machine:-qemux86-64}"
fi

current="$(source_fingerprint)"
work_dir="${ROOT_DIR}/work"

# 参照 build.sh 的 kas_work_dir 命名：非默认 machine 加后缀
combo_dirs=()
if ((all)); then
    for d in "${work_dir}"/kas-*; do
        [[ -d "${d}" && -f "${d}/.yp-fingerprint" ]] && combo_dirs+=("${d}")
    done
else
    suffix=""
    [[ "${machine}" == "qemux86-64" ]] || suffix="-${machine}"
    d="${work_dir}/kas-${release}-${variant}${suffix}"
    if [[ -d "${d}" ]]; then
        combo_dirs+=("${d}")
    else
        echo "deploy-guard: kas-${release}-${variant}${suffix} 不存在——从未构建，放行"
        exit 0
    fi
fi

if ((${#combo_dirs[@]} == 0)); then
    echo "deploy-guard: 没有带指纹戳的构建目录——CI 或未构建过，放行"
    exit 0
fi

stale=0
for d in "${combo_dirs[@]}"; do
    combo="${d#"${work_dir}"/}"
    stamp="$(cat "${d}/.yp-fingerprint" 2>/dev/null || true)"
    if [[ -z "${stamp}" ]]; then
        echo "STALE  ${combo}：构建目录存在但没有指纹戳（旧版 build.sh 或手工 kas 构建），按 stale 处理"
        stale=$((stale + 1))
    elif [[ "${stamp}" != "${current}" ]]; then
        echo "STALE  ${combo}：指纹 ${stamp:0:12}… ≠ 当前 ${current:0:12}… —— 产物是旧代码构建的，先重建再取证"
        stale=$((stale + 1))
    else
        echo "FRESH  ${combo}（${stamp:0:12}…）"
    fi
done

if ((stale > 0)); then
    die "deploy-guard：${stale} 个构建目录 stale（见上）"
fi
echo "deploy-guard：全部新鲜"
