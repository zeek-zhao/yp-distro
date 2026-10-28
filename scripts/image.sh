#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/log.sh
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/log.sh"

log() {
    log_info "$@"
}

warn() {
    log_warn "$@"
}

usage() {
    cat <<'EOF'
Usage:
  scripts/image.sh build <release>
  scripts/image.sh verify <release>
  scripts/image.sh list
  scripts/image.sh push <release> <tag>
  scripts/image.sh --release <release> [--build | --verify]
  scripts/image.sh --list
EOF
}

valid_release() {
    case "$1" in
        dunfell | kirkstone | scarthgap | wrynose) return 0 ;;
        *) return 1 ;;
    esac
}

image_name() {
    printf 'ghcr.io/zeek-zhao/yocto/%s' "$1"
}

build_image() {
    local release="$1" tag
    valid_release "${release}" || die "未知 release：${release}"
    tag="$(image_name "${release}"):local"
    log "构建 ${tag}"
    docker build \
        -f "${ROOT_DIR}/docker/${release}/Dockerfile" \
        -t "${tag}" \
        --build-arg "APT_MIRROR=${APT_MIRROR:-cn.archive.ubuntu.com}" \
        --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}" \
        "${ROOT_DIR}"
}

verify_image() {
    local release="$1" tag
    valid_release "${release}" || die "未知 release：${release}"
    tag="$(image_name "${release}"):local"
    docker run --rm "${tag}" bash -c '
        set -euo pipefail
        test "$(id -u)" -ne 0
        test "$(id -un)" = builder
        kas_version="$(kas --version)"
        if ! grep -Eq "(^|[[:space:]])4\.6(\.[0-9]+)?([[:space:]]|$)" <<<"${kas_version}"; then
            printf "Unexpected kas version: %s\n" "${kas_version}" >&2
            exit 1
        fi
        printf "kas=%s\n" "${kas_version}"
        bats --version
        shellcheck --version
        shfmt --version
        test "$(locale charmap)" = UTF-8
        if find /work -mindepth 1 -print -quit | grep -q .; then
            echo "/work is not empty" >&2
            exit 1
        fi
        shopt -s nullglob
        found=0
        for p in /home/*/.ssh /root/.ssh /root/.netrc /root/.docker/config.json; do
            if [ -e "${p}" ]; then
                printf "Credential path exists: %s\n" "${p}" >&2
                found=1
            fi
        done
        [ "${found}" -eq 0 ] || exit 1
        test "${YOCTO_RELEASE}" = "$1"
        printf "verified release=%s user=%s uid=%s\n" \
            "${YOCTO_RELEASE}" "$(id -un)" "$(id -u)"
    ' bash "${release}"
}

list_images() {
    local images
    images="$(docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}')"
    if ! printf '%s\n' "${images}" |
        grep -E '/yocto/(dunfell|kirkstone|scarthgap|wrynose):[^[:space:]]+[[:space:]]'; then
        printf '%s\n' '(无本地构建镜像)'
    fi
}

push_image() {
    local release="$1" target
    valid_release "${release}" || die "未知 release：${release}"
    target="$(image_name "${release}"):$2"
    docker tag "$(image_name "${release}"):local" "${target}"
    docker push "${target}"
}

if (($# == 0)); then
    usage >&2
    die "缺少操作"
fi

if [[ "$1" == build || "$1" == verify || "$1" == list || "$1" == push ]]; then
    action="$1"
    shift
    case "${action}" in
        build)
            (($# == 1)) || die "用法：scripts/image.sh build <release>"
            build_image "$1"
            ;;
        verify)
            (($# == 1)) || die "用法：scripts/image.sh verify <release>"
            verify_image "$1"
            ;;
        list)
            (($# == 0)) || die "用法：scripts/image.sh list"
            list_images
            ;;
        push)
            (($# == 2)) || die "用法：scripts/image.sh push <release> <tag>"
            push_image "$1" "$2"
            ;;
    esac
    exit 0
fi

release=""
action=build
action_selected=0
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die "--release 缺少参数"
            release="$2"
            shift 2
            ;;
        --build | --verify)
            ((action_selected == 0)) || die "--build/--verify 只能选一个"
            action="${1#--}"
            action_selected=1
            shift
            ;;
        --list)
            [[ $# -eq 1 && -z "${release}" ]] || die "--list 不能与其他参数组合"
            list_images
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "未知参数：$1"
            ;;
    esac
done

[[ -n "${release}" ]] || {
    usage >&2
    die "--release 必填"
}
case "${action}" in
    build) build_image "${release}" ;;
    verify) verify_image "${release}" ;;
esac
