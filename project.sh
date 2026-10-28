#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
用法：
  ./project.sh <cmd> [选项]

命令：
  config       解析并打印最终配置
  doctor       检查 release/variant 组合与磁盘水位
  kas          静态校验 kas 配置（不检出上游仓库）
  test         运行 BATS 测试
  report       生成测试报告
  lint         运行静态检查
  secret-scan  扫描仓库机密
  ci-tools     安装 CI 工具
  hooks        安装仓库级 git 钩子
  image        构建、校验或列出 Yocto 构建镜像
  shell        在 release 构建容器中执行命令
  source | build | qemu | review | e2e
               暂未实现
EOF
}

command_usage() {
    case "$1" in
        config)
            printf '用法：./project.sh config --release R --variant V --machine M\n'
            ;;
        doctor)
            printf '用法：./project.sh doctor\n'
            ;;
        kas)
            printf '用法：./project.sh kas [--release R --variant V]\n'
            ;;
        test)
            printf '用法：./project.sh test [--tags TAG]\n'
            ;;
        report)
            printf '用法：./project.sh report [--release R] [--variant V]\n'
            ;;
        lint)
            printf '用法：./project.sh lint [lint.sh 参数...]\n'
            ;;
        secret-scan)
            printf '用法：./project.sh secret-scan [secret-scan.sh 参数...]\n'
            ;;
        ci-tools)
            printf '用法：./project.sh ci-tools [install-tools.sh 参数...]\n'
            ;;
        hooks)
            printf '用法：./project.sh hooks\n'
            ;;
        image)
            printf '用法：./project.sh image [image.sh 参数...]\n'
            ;;
        shell)
            cat <<'EOF'
用法：./project.sh shell --release R [--variant V] [--machine M] [--dry-run | --check] [-- <cmd>...]
  --release R  必填 Yocto release
  --variant V  构建变体（默认：general）
  --machine M  目标 machine（默认：qemux86-64）
  --dry-run    打印 docker 命令，不启动容器
  --check      执行预检，不启动容器
  -- <cmd>     容器内命令；省略时运行 bash -l
EOF
            ;;
    esac
}

die_unknown_option() {
    die "未知参数：$1"
}

option_allowed() {
    local allowed="$1" option="$2"
    [[ " ${allowed} " == *" ${option} "* ]]
}

OPT_RELEASE=""
OPT_VARIANT=""
OPT_MACHINE=""
OPT_TAGS=""
OPT_DRY_RUN=0
OPT_CHECK=0
OPT_COMMAND_ARGS=()

parse_options() {
    local allowed="$1"
    shift
    while (($# > 0)); do
        case "$1" in
            --release | --variant | --machine | --tags)
                local option="${1#--}"
                option_allowed "${allowed}" "${option}" ||
                    die_unknown_option "$1"
                (($# >= 2)) || die "$1 缺少参数"
                case "${option}" in
                    release) OPT_RELEASE="$2" ;;
                    variant) OPT_VARIANT="$2" ;;
                    machine) OPT_MACHINE="$2" ;;
                    tags) OPT_TAGS="$2" ;;
                esac
                shift 2
                ;;
            --dry-run | --check)
                local option="${1#--}"
                option_allowed "${allowed}" "${option}" ||
                    die_unknown_option "$1"
                if [[ "$1" == --dry-run ]]; then
                    ((OPT_CHECK == 0)) || die "--check 与 --dry-run 只能选一个"
                    OPT_DRY_RUN=1
                else
                    ((OPT_DRY_RUN == 0)) || die "--check 与 --dry-run 只能选一个"
                    OPT_CHECK=1
                fi
                shift
                ;;
            --)
                option_allowed "${allowed}" command ||
                    die_unknown_option "$1"
                shift
                OPT_COMMAND_ARGS=("$@")
                break
                ;;
            -h | --help)
                command_usage "${COMMAND_NAME}"
                exit 0
                ;;
            *) die_unknown_option "$1" ;;
        esac
    done
}

not_implemented() {
    local command_name="$1" reason
    case "${command_name}" in
        source) reason="C40 已改由 kas checkout 取代" ;;
        build) reason="P1 #17 kas 落地后接管" ;;
        qemu | review | e2e) reason="P2 阶段" ;;
        *) die "未知命令：${command_name}" ;;
    esac
    printf 'not implemented yet: %s（%s）\n' "${command_name}" "${reason}" >&2
    exit 2
}

run_doctor() {
    local release_name variant_name disk_status=0
    printf '# release variant repo_mode distro image\n'
    for release_name in dunfell kirkstone scarthgap wrynose; do
        for variant_name in general custom; do
            resolve_all "${release_name}" "${variant_name}" qemux86-64
            printf '%s %s %s %s %s\n' \
                "${RELEASE}" "${VARIANT}" "${REPO_MODE}" "${DISTRO}" "${IMAGE}"
        done
    done
    check_disk_watermark || disk_status=$?
    exit "${disk_status}"
}

[[ $# -gt 0 ]] || die "缺少命令；使用 --help 查看用法"
case "$1" in
    -h | --help | help)
        usage
        exit 0
        ;;
esac

COMMAND_NAME="$1"
shift

case "${COMMAND_NAME}" in
    source | build | qemu | review | e2e) not_implemented "${COMMAND_NAME}" ;;
    config | doctor | kas | test | report | lint | secret-scan | ci-tools | hooks | image | shell) ;;
    *) die "未知命令：${COMMAND_NAME}；使用 --help 查看用法" ;;
esac

if [[ "$#" -eq 1 && ("$1" == -h || "$1" == --help) ]]; then
    command_usage "${COMMAND_NAME}"
    exit 0
fi

case "${COMMAND_NAME}" in
    config) parse_options "release variant machine" "$@" ;;
    kas) parse_options "release variant" "$@" ;;
    doctor | hooks) parse_options "" "$@" ;;
    test) parse_options "tags" "$@" ;;
    report) parse_options "release variant" "$@" ;;
    shell) parse_options "release variant machine dry-run check command" "$@" ;;
    lint | secret-scan | ci-tools | image)
        case "${COMMAND_NAME}" in
            lint) exec bash "${ROOT_DIR}/scripts/ci/lint.sh" "$@" ;;
            secret-scan) exec bash "${ROOT_DIR}/scripts/ci/secret-scan.sh" "$@" ;;
            ci-tools) exec bash "${ROOT_DIR}/scripts/ci/install-tools.sh" "$@" ;;
            image) exec bash "${ROOT_DIR}/scripts/image.sh" "$@" ;;
        esac
        ;;
esac

case "${COMMAND_NAME}" in
    kas)
        kas_args=()
        [[ -z "${OPT_RELEASE}" ]] || kas_args+=(--release "${OPT_RELEASE}")
        [[ -z "${OPT_VARIANT}" ]] || kas_args+=(--variant "${OPT_VARIANT}")
        exec bash "${ROOT_DIR}/scripts/dev.sh" python3 \
            "${ROOT_DIR}/scripts/kas-verify.py" "${kas_args[@]}"
        ;;
    test)
        test_args=(-r "${ROOT_DIR}/tests/bats")
        if [[ -n "${OPT_TAGS}" ]]; then
            test_args+=(--filter-tags "${OPT_TAGS}")
        fi
        exec bats "${test_args[@]}"
        ;;
    report)
        exec "${ROOT_DIR}/scripts/report.sh" "${OPT_RELEASE:-all}" \
            --variant "${OPT_VARIANT:-general}"
        ;;
    config)
        [[ -n "${OPT_RELEASE}" ]] || die "config 必须指定 --release"
        [[ -n "${OPT_VARIANT}" ]] || die "config 必须指定 --variant"
        [[ -n "${OPT_MACHINE}" ]] || die "config 必须指定 --machine"
        resolve_all "${OPT_RELEASE}" "${OPT_VARIANT}" "${OPT_MACHINE}"
        printf '%s\n' \
            "DISTRO=${DISTRO}" \
            "IMAGE=${IMAGE}" \
            "MACHINE=${MACHINE}" \
            "RELEASE=${RELEASE}" \
            "REPO_MODE=${REPO_MODE}" \
            "TAG=${TAG}" \
            "VARIANT=${VARIANT}" | LC_ALL=C sort
        ;;
    doctor) run_doctor ;;
    hooks)
        git -C "${ROOT_DIR}" config core.hooksPath .githooks
        chmod +x "${ROOT_DIR}"/.githooks/*
        printf 'core.hooksPath = %s\n' \
            "$(git -C "${ROOT_DIR}" config core.hooksPath)"
        ;;
    shell)
        [[ -n "${OPT_RELEASE}" ]] || die "shell 必须指定 --release"
        shell_args=(--release "${OPT_RELEASE}"
            --variant "${OPT_VARIANT:-general}"
            --machine "${OPT_MACHINE:-qemux86-64}")
        ((OPT_DRY_RUN == 0)) || shell_args+=(--dry-run)
        ((OPT_CHECK == 0)) || shell_args+=(--check)
        if ((${#OPT_COMMAND_ARGS[@]} > 0)); then
            shell_args+=(-- "${OPT_COMMAND_ARGS[@]}")
        else
            shell_args+=(-- bash -l)
        fi
        exec bash "${ROOT_DIR}/scripts/container.sh" "${shell_args[@]}"
        ;;
esac
