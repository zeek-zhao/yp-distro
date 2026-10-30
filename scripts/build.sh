#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# machine 后缀规则与 report.sh / qemu.sh 共用同一实现，避免两处各写一份。
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/build.sh --release <r> --variant general|custom [--machine <m>]
                   [--image-mode release|dev] [--cve] [--spdx] [--dry-run]

--cve  额外打开 custom variant 的 CVE 检查（issue #48/#26），并隐含 --spdx。
       前三版需要先用 scripts/cve-db.sh sync 把离线 NVD 库放进
       work/downloads/CVE_CHECK/；wrynose 没有 cve-check，CVE 由构建后的
       sbom-cve-check CLI 读 SBOM 得出，只需 scripts/cve-db.sh --release wrynose。

--spdx 打开 create-spdx（issue #26），两个 variant 都可用；产物落在
       deploy/spdx/ 与 deploy/images/<machine>/*.spdx.json。
EOF
}

invalid_args() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

release=""
variant=""
machine=qemux86-64
image_mode=release
dry_run=0
with_cve=0
with_spdx=0
while (($# > 0)); do
    case "$1" in
        --release | --variant | --machine | --image-mode)
            (($# >= 2)) || invalid_args "$1 缺少参数"
            case "$1" in
                --release) release="$2" ;;
                --variant) variant="$2" ;;
                --machine) machine="$2" ;;
                --image-mode) image_mode="$2" ;;
            esac
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --cve)
            with_cve=1
            shift
            ;;
        --spdx)
            with_spdx=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) invalid_args "未知参数：$1" ;;
    esac
done

case "${release}" in
    dunfell | kirkstone | scarthgap | wrynose)
        [[ -f "${ROOT_DIR}/config/${release}.env" ]] ||
            invalid_args "release 配置不存在：${release}"
        ;;
    *) invalid_args "--release 必须是 dunfell|kirkstone|scarthgap|wrynose" ;;
esac
case "${variant}" in
    general | custom) ;;
    *) invalid_args "--variant 必须是 general|custom" ;;
esac
case "${image_mode}" in
    release | dev) ;;
    *) invalid_args "--image-mode 必须是 release|dev" ;;
esac
[[ "${machine}" =~ ^[[:alnum:]_-]+$ ]] ||
    invalid_args "--machine 名称非法：${machine}"
[[ -f "${ROOT_DIR}/config/machines/${machine}.env" ]] ||
    invalid_args "machine 配置不存在：config/machines/${machine}.env"

# CVE 检查只有 custom variant 能开（general 用 poky distro，没有那条 INHERIT），
# 而且它需要的离线库必须事先建好 —— 否则 bitbake 会在
# cve-update-nvd2-native 上等 4 小时（#48）。
#
# 6.0 是另一条路：没有 cve-check.bbclass，用构建后的 sbom-cve-check CLI 读 SBOM
# 出清单（见 docs/compliance.md），所以这里只需要 SBOM 与 nvd-fkie 的 git 缓存。
cve_db=""
if ((with_cve)); then
    [[ "${variant}" == "custom" ]] ||
        invalid_args "--cve 只能用于 --variant custom"
    # --cve 隐含 --spdx：6.0 的 CVE 结论来自 SBOM，前三版报告也要 SBOM 一节。
    with_spdx=1
    if cve_db="$(cve_db_filename "${release}")"; then
        dir_cve_db="${ROOT_DIR}/work/downloads/CVE_CHECK/${cve_db}"
        [[ -f "${dir_cve_db}" ]] || invalid_args "缺少离线 NVD 库 ${dir_cve_db#"${ROOT_DIR}/"}；先跑 scripts/cve-db.sh sync"
    elif [[ "${release}" == "wrynose" ]]; then
        dir_sbom_db="${ROOT_DIR}/work/cve-cache/sbom/nvd-fkie"
        [[ -d "${dir_sbom_db}/.git" ]] ||
            invalid_args "缺少 nvd-fkie 缓存 ${dir_sbom_db#"${ROOT_DIR}/"}；先跑 scripts/cve-db.sh --release wrynose"
    else
        invalid_args "${release} 不支持 CVE 检查"
    fi
fi

cd -- "${ROOT_DIR}"
mkdir -p work
lock_file="${ROOT_DIR}/work/build.lock"
exec 9>"${lock_file}"
if ! flock -n 9; then
    printf 'ERROR: 另一个构建正在运行（锁：%s）；本工程规定串行构建\n' "${lock_file}" >&2
    exit 3
fi
# 保留锁文件的 inode，避免删除后后续构建锁住不同文件。

# machine 维度用 kas 多配置叠加：target 里 include 的是默认 machine 的 yml，
# 非默认 machine 再追加一个 yml，靠顶层 machine: 字段覆盖 —— 无需为每个
# machine 复制 8 份 target 文件（复制会立刻产生漂移）。
machine_sfx="$(machine_suffix "${machine}")"
kas_configs="/work/kas/targets/${release}-${variant}.yml"
[[ "${machine}" == "qemux86-64" ]] ||
    kas_configs+=":/work/kas/machines/${machine}.yml"
# CVE 用一层小 overlay 追加，不把开关写死进 8 份 target：
# 同一份 target 既能出「标准构建」也能出「合规构建」，两者只差这一个文件。
((with_spdx == 0)) || kas_configs+=":/work/kas/features/spdx.yml"
((with_cve == 0)) || kas_configs+=":/work/kas/features/cve.yml"
kas_work_dir="/work/work/kas-${release}-${variant}${machine_sfx}"
build_command="mkdir -p ${kas_work_dir} /work/work/downloads /work/work/sstate && KAS_CLONE_DEPTH=1 KAS_WORK_DIR=${kas_work_dir} kas build ${kas_configs}"
if [[ "${image_mode}" == release ]]; then
    command_args=(./project.sh shell --release "${release}" --variant "${variant}" --machine "${machine}" -- bash -lc)
else
    command_args=(bash scripts/dev.sh bash -lc)
fi
if ((dry_run)); then
    printf '%s ' "${command_args[@]}"
    printf "'%s'\n" "${build_command}"
    exit 0
fi

mkdir -p work/downloads work/sstate work/logs "work/kas-${release}-${variant}${machine_sfx}"
build_log="${ROOT_DIR}/work/logs/build-${release}-${variant}${machine_sfx}.log"
build_meta="${build_log%.log}.meta"
# 报告要区分「标准构建」与「合规构建」：meta 只放秒数（report.sh 按纯数字解析），
# 开关单独放 .flags，避免把 meta 的格式搞坏。
build_flags="${build_log%.log}.flags"
printf 'release=%s\nvariant=%s\nmachine=%s\nimage_mode=%s\ncve=%s\nspdx=%s\n' \
    "${release}" "${variant}" "${machine}" "${image_mode}" "${with_cve}" "${with_spdx}" >"${build_flags}"
start_seconds="$(date +%s)"
printf 'Build start: %s\n' "$(date --iso-8601=seconds)" | tee "${build_log}"
if "${command_args[@]}" "${build_command}" 2>&1 | tee -a "${build_log}"; then
    build_status=0
else
    build_status=$?
fi
end_seconds="$(date +%s)"
printf '%s\n' "$((end_seconds - start_seconds))" >"${build_meta}"
printf 'Build end: %s (exit %s)\n' "$(date --iso-8601=seconds)" "${build_status}" |
    tee -a "${build_log}"
if ((build_status != 0)); then
    printf 'ERROR: 构建失败（exit %s）；日志：%s\n' "${build_status}" "${build_log}" >&2
fi
exit "${build_status}"
