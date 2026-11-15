#!/usr/bin/env bash
# =============================================================================
# scripts/release-check.sh —— 点版本/发版全量回归编排（#115）
#
#   scripts/release-check.sh                        # 默认：两 LTS × 两 variant
#   scripts/release-check.sh --releases scarthgap --variants custom
#   scripts/release-check.sh --releases wrynose --machine qemuarm64
#
# 逐组合 build.sh → qemu.sh → report.sh（各自有超时与日志），结尾跑
# deploy-guard 并汇总。不新增任何构建逻辑——本脚本只是 #85 回归 campaign
# 的正式沉淀，点版本跟进流程见 docs/05-release/point-releases.md。
#
# 默认范围刻意只含两个受支持的 LTS（wrynose/scarthgap）；kirkstone/dunfell
# 已 EOL（D12 冻结口径），显式传参仍可跑。
# =============================================================================
set -u

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'USAGE'
用法：scripts/release-check.sh [--releases 列表] [--variants 列表] [--machine m]

  --releases  逗号分隔（默认取 config/supported-releases.txt）
  --variants  逗号分隔（默认 custom,general）
  --machine   单值（默认 qemux86-64；qemuarm64 组合目录带后缀）
  --timeout   单组合构建超时秒数（默认 3600）

逐组合执行 build.sh → qemu.sh → report.sh，日志在 /tmp/release-check-*。
退出码：0 = 全绿；1 = 任一环节失败（失败明细见日志与结尾汇总）。
USAGE
}

# 受支持 release 的单一事实源：config/supported-releases.txt（#127）
SUPPORTED_RELEASES_FILE="${ROOT_DIR}/config/supported-releases.txt"
[[ -s "${SUPPORTED_RELEASES_FILE}" ]] || die "缺少 ${SUPPORTED_RELEASES_FILE}（受支持 release 单一事实源）"
releases="$(grep -vE '^\s*(#|$)' "${SUPPORTED_RELEASES_FILE}" | paste -sd, -)"
[[ -n "${releases}" ]] || die "${SUPPORTED_RELEASES_FILE} 为空"
variants="custom,general"
machine="qemux86-64"
build_timeout=3600
while (($# > 0)); do
    case "$1" in
        --releases)
            (($# >= 2)) || die "--releases 缺少参数"
            releases="$2"
            shift 2
            ;;
        --variants)
            (($# >= 2)) || die "--variants 缺少参数"
            variants="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || die "--timeout 缺少参数"
            build_timeout="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1（--help 看用法）" ;;
    esac
done

machine_sfx=""
[[ "${machine}" == "qemux86-64" ]] || machine_sfx="-${machine}"

IFS=',' read -r -a rel_arr <<<"${releases}"
IFS=',' read -r -a var_arr <<<"${variants}"

failed=()
start="$(date --iso-8601=seconds)"
echo "release-check: ${releases} × ${variants} × ${machine}  ${start}"

for release in "${rel_arr[@]}"; do
    [[ "${release}" =~ ^(dunfell|kirkstone|scarthgap|wrynose)$ ]] ||
        die "未知 release：${release}"
    for variant in "${var_arr[@]}"; do
        [[ "${variant}" =~ ^(general|custom)$ ]] || die "未知 variant：${variant}"
        combo="${release}/${variant}${machine_sfx}"
        echo "── ${combo}  $(date --iso-8601=seconds)"

        if ! timeout "${build_timeout}" \
            bash "${ROOT_DIR}/scripts/build.sh" --release "${release}" --variant "${variant}" \
            ${machine_sfx:+'--machine' "${machine}"} \
            >"/tmp/release-check-build-${release}-${variant}${machine_sfx}.log" 2>&1; then
            echo "   BUILD FAILED（日志：/tmp/release-check-build-${release}-${variant}${machine_sfx}.log）"
            failed+=("${combo}:build")
            continue
        fi

        if ! timeout 600 \
            bash "${ROOT_DIR}/scripts/qemu.sh" --release "${release}" --variant "${variant}" \
            --machine "${machine}" \
            >"/tmp/release-check-qemu-${release}-${variant}${machine_sfx}.log" 2>&1; then
            echo "   QEMU FAILED（日志：/tmp/release-check-qemu-${release}-${variant}${machine_sfx}.log）"
            failed+=("${combo}:qemu")
        fi

        if ! timeout 900 \
            bash "${ROOT_DIR}/scripts/report.sh" "${release}" --variant "${variant}" \
            --machine "${machine}" \
            >"/tmp/release-check-report-${release}-${variant}${machine_sfx}.log" 2>&1; then
            echo "   REPORT FAILED（日志：/tmp/release-check-report-${release}-${variant}${machine_sfx}.log）"
            failed+=("${combo}:report")
        fi

        # guard 逐组合跑而不是 --all：默认范围只有两个 LTS，EOL 组合（dunfell/
        # kirkstone）的产物**有意**停在冻结口径，不该被本次检查牵连判 stale。
        if ! bash "${ROOT_DIR}/scripts/deploy-guard.sh" \
            --release "${release}" --variant "${variant}" --machine "${machine}"; then
            failed+=("${combo}:guard")
        fi
    done
done

echo "── 汇总"
if ((${#failed[@]} > 0)); then
    printf 'FAILED: %s\n' "${failed[@]}"
    die "release-check：${#failed[@]} 项失败（${start} 起，共 ${#rel_arr[@]}×${#var_arr[@]} 组合）"
fi

# 发布必刷新归档（审查纪律落地）：QA 归档必须锚定合并后的 main SHA。
# 归档文件名由 report.sh 按 <date>-<sha> 生成——若 docs/qa/<release>/ 下
# 找不到锚定当前 HEAD 的归档，说明本次运行的证据没有刷新，发布口径
# 就会引用过期或孤儿 SHA（20261112-12c831f / 20261114-7dc6206 教训）。
head_sha="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
missing=()
for release in "${rel_arr[@]}"; do
    ls "${ROOT_DIR}/docs/qa/${release}"/*-"${head_sha}"*.md >/dev/null 2>&1 ||
        missing+=("${release}")
done
if ((${#missing[@]} > 0)); then
    die "release-check：以下 release 在 docs/qa/ 缺少锚定 ${head_sha} 的归档（发布必刷新归档）：${missing[*]}"
fi

echo "release-check：全部通过（${#rel_arr[@]}×${#var_arr[@]} 组合，${start} 起）；归档已锚定 ${head_sha}"
