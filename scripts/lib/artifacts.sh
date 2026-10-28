#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
    ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
# shellcheck source=common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

artifact_list() {
    [[ $# -eq 3 ]] || die "用法：artifact_list <deploy_dir> <image> <machine>"

    local deploy_dir="$1" image="$2" machine="$3" path name
    local -a artifacts=()
    [[ -d "${deploy_dir}" ]] || return 0
    deploy_dir="$(cd -- "${deploy_dir}" && pwd)" || return 0
    for path in "${deploy_dir}/${image}-${machine}.rootfs."*; do
        [[ -f "${path}" ]] || continue
        name="${path##*/}"
        [[ "${name}" == *.manifest || "${name}" == *.testdata.json ||
            "${name}" == *.spdx.* || "${name}" == *.json ]] && continue
        artifacts+=("${path}")
    done
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

    local deploy_dir="$1" image="$2" machine="$3" primary="" candidate
    local -a candidates=()
    [[ -d "${deploy_dir}" ]] || return 1
    deploy_dir="$(cd -- "${deploy_dir}" && pwd)" || return 1
    for candidate in "${deploy_dir}/${image}-${machine}.rootfs.ext4"*; do
        [[ -f "${candidate}" ]] && candidates+=("${candidate}")
    done
    primary="$(_artifact_newest "${candidates[@]}")"
    if [[ -z "${primary}" ]]; then
        candidates=()
        for candidate in "${deploy_dir}/${image}-${machine}.rootfs.tar.bz2"*; do
            [[ -f "${candidate}" ]] && candidates+=("${candidate}")
        done
        primary="$(_artifact_newest "${candidates[@]}")"
    fi
    if [[ -z "${primary}" ]]; then
        candidates=()
        for candidate in "${deploy_dir}/${image}-${machine}.rootfs."*; do
            [[ -f "${candidate}" ]] || continue
            [[ "${candidate}" == *.manifest || "${candidate}" == *.testdata.json ||
                "${candidate}" == *.spdx.* || "${candidate}" == *.json ]] && continue
            candidates+=("${candidate}")
        done
        primary="$(_artifact_newest "${candidates[@]}")"
    fi
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
    stat -c %s -- "$1"
}
