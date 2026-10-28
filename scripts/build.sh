#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  scripts/build.sh --release <r> --variant general|custom [--image-mode release|dev] [--dry-run]
EOF
}

invalid_args() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

release=""
variant=""
image_mode=release
dry_run=0
while (($# > 0)); do
    case "$1" in
        --release | --variant | --image-mode)
            (($# >= 2)) || invalid_args "$1 缺少参数"
            case "$1" in
                --release) release="$2" ;;
                --variant) variant="$2" ;;
                --image-mode) image_mode="$2" ;;
            esac
            shift 2
            ;;
        --dry-run)
            dry_run=1
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

cd -- "${ROOT_DIR}"
mkdir -p work
lock_file="${ROOT_DIR}/work/build.lock"
exec 9>"${lock_file}"
if ! flock -n 9; then
    printf 'ERROR: 另一个构建正在运行（锁：%s）；本工程规定串行构建\n' "${lock_file}" >&2
    exit 3
fi
# 保留锁文件的 inode，避免删除后后续构建锁住不同文件。

kas_work_dir="/work/work/kas-${release}-${variant}"
build_command="mkdir -p ${kas_work_dir} /work/work/downloads /work/work/sstate && KAS_CLONE_DEPTH=1 KAS_WORK_DIR=${kas_work_dir} kas build /work/kas/targets/${release}-${variant}.yml"
if [[ "${image_mode}" == release ]]; then
    command_args=(./project.sh shell --release "${release}" --variant "${variant}" -- bash -lc)
else
    command_args=(bash scripts/dev.sh bash -lc)
fi
if ((dry_run)); then
    printf '%s ' "${command_args[@]}"
    printf "'%s'\n" "${build_command}"
    exit 0
fi

mkdir -p work/downloads work/sstate work/logs "work/kas-${release}-${variant}"
build_log="${ROOT_DIR}/work/logs/build-${release}-${variant}.log"
build_meta="${build_log%.log}.meta"
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
