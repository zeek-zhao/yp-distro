#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
    ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

# 产物命名在两代 Yocto 之间不一致：
#   5.0+  -> core-image-minimal-qemux86-64.rootfs.ext4[.zst]
#   4.0-  -> core-image-minimal-qemux86-64.ext4
# 所以不能只认 "<image>-<machine>.rootfs.*"。短名优先，短名一个都没有时才退到
# 带时间戳的别名 (<image>-<machine>-<ts>.rootfs.*)，避免同一文件被算两次。
_artifact_glob() {
    [[ $# -eq 3 ]] || die "用法：_artifact_glob <deploy_dir> <image> <machine>"

    local deploy_dir="$1" image="$2" machine="$3" path
    local -a short=() dated=()
    for path in "${deploy_dir}/${image}-${machine}."*; do
        [[ -f "${path}" ]] && short+=("${path}")
    done
    if ((${#short[@]} == 0)); then
        for path in "${deploy_dir}/${image}-${machine}-"*".rootfs."*; do
            [[ -f "${path}" ]] && dated+=("${path}")
        done
    fi
    if ((${#short[@]} > 0)); then
        printf '%s\n' "${short[@]}"
    fi
    if ((${#dated[@]} > 0)); then
        printf '%s\n' "${dated[@]}"
    fi
    return 0
}

# 同名旁的元数据文件不是镜像本体，不能进校验和清单。
_artifact_is_payload() {
    case "$1" in
        *.manifest | *.testdata.json | *.spdx.* | *.json | *.qemuboot.conf) return 1 ;;
    esac
    return 0
}

_artifact_candidates() {
    [[ $# -eq 3 ]] || die "用法：_artifact_candidates <deploy_dir> <image> <machine>"

    local deploy_dir="$1" image="$2" machine="$3" path
    [[ -d "${deploy_dir}" ]] || return 1
    deploy_dir="$(cd -- "${deploy_dir}" && pwd)" || return 1
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        _artifact_is_payload "${path}" || continue
        printf '%s\n' "${path}"
    done < <(_artifact_glob "${deploy_dir}" "${image}" "${machine}")
}

artifact_list() {
    [[ $# -eq 3 ]] || die "用法：artifact_list <deploy_dir> <image> <machine>"

    local -a artifacts=()
    local path
    [[ -d "$1" ]] || return 0
    while IFS= read -r path; do
        [[ -n "${path}" ]] && artifacts+=("${path}")
    done < <(_artifact_candidates "$1" "$2" "$3")
    ((${#artifacts[@]} == 0)) && return 0
    printf '%s\n' "${artifacts[@]}" | LC_ALL=C sort
}

_artifact_newest() {
    local candidate newest=""
    for candidate in "$@"; do
        [[ -f "${candidate}" ]] || continue
        if [[ -z "${newest}" || "${candidate}" -nt "${newest}" ]]; then
            newest="${candidate}"
        fi
    done
    printf '%s' "${newest}"
}

artifact_primary() {
    [[ $# -eq 3 ]] || die "用法：artifact_primary <deploy_dir> <image> <machine>"

    local candidate primary=""
    local -a all=() exts=() tars=() anytars=()
    [[ -d "$1" ]] || return 1
    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] && all+=("${candidate}")
    done < <(_artifact_candidates "$1" "$2" "$3")
    ((${#all[@]} == 0)) && return 1

    # 优先级：ext4（含 .ext4.zst）> tar.bz2 > 其它 tar > 任意
    for candidate in "${all[@]}"; do
        case "${candidate}" in
            *.ext4*) exts+=("${candidate}") ;;
            *.tar.bz2*) tars+=("${candidate}") ;;
            *.tar.*) anytars+=("${candidate}") ;;
        esac
    done

    primary="$(_artifact_newest "${exts[@]:-}")"
    [[ -n "${primary}" ]] || primary="$(_artifact_newest "${tars[@]:-}")"
    [[ -n "${primary}" ]] || primary="$(_artifact_newest "${anytars[@]:-}")"
    [[ -n "${primary}" ]] || primary="$(_artifact_newest "${all[@]}")"
    [[ -n "${primary}" ]] || return 1
    printf '%s\n' "${primary}"
}

artifact_sha256() {
    [[ $# -eq 1 ]] || die "用法：artifact_sha256 <path>"
    [[ -f "$1" ]] || return 1
    sha256sum -- "$1" | awk '{print $1}'
}

artifact_bytes() {
    [[ $# -eq 1 ]] || die "用法：artifact_bytes <path>"
    [[ -f "$1" ]] || return 1
    stat -Lc %s -- "$1"
}
