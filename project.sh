#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
用法：
  ./project.sh <cmd> [--release R] [--variant V] [--machine M]

命令：
  config   解析并打印配置
  doctor   检查 release/variant 组合与磁盘水位
  test     运行 BATS 测试
  report   运行测试并生成报告
  image    构建、校验或列出 Yocto 构建镜像
  source | build | qemu | review | e2e
           暂未实现
EOF
}

[[ $# -gt 0 ]] || die "缺少命令；使用 --help 查看用法"
command_name="$1"
shift

case "${command_name}" in
    -h | --help | help)
        usage
        exit 0
        ;;
    image)
        exec bash "${ROOT_DIR}/scripts/image.sh" "$@"
        ;;
    test | report | config | doctor) ;;
    source | build | qemu | review | e2e)
        printf 'not implemented yet: %s\n' "${command_name}" >&2
        exit 2
        ;;
    *) die "未知命令：${command_name}；使用 --help 查看用法" ;;
esac

release=""
variant=""
machine=""
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
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
done

case "${command_name}" in
    test)
        exec bats -r "${ROOT_DIR}/tests/bats"
        ;;
    report)
        exec "${ROOT_DIR}/scripts/report.sh" "${release:-all}" \
            --variant "${variant:-general}"
        ;;
    config)
        [[ -n "${release}" ]] || die "config 必须指定 --release"
        load_release "${release}"
        [[ -n "${variant}" ]] || die "config 必须指定 --variant"
        [[ -n "${machine}" ]] || die "config 必须指定 --machine"
        resolve_all "${release}" "${variant}" "${machine}"
        printf '%s\n' \
            "DISTRO=${DISTRO}" \
            "IMAGE=${IMAGE}" \
            "MACHINE=${MACHINE}" \
            "RELEASE=${RELEASE}" \
            "REPO_MODE=${REPO_MODE}" \
            "TAG=${TAG}" \
            "VARIANT=${VARIANT}" | LC_ALL=C sort
        ;;
    doctor)
        printf '# release variant repo_mode distro image\n'
        for release in dunfell kirkstone scarthgap wrynose; do
            for variant in general custom; do
                resolve_all "${release}" "${variant}" qemux86-64
                printf '%s %s %s %s %s\n' \
                    "${RELEASE}" "${VARIANT}" "${REPO_MODE}" "${DISTRO}" "${IMAGE}"
            done
        done
        disk_status=0
        check_disk_watermark || disk_status=$?
        exit "${disk_status}"
        ;;
esac
