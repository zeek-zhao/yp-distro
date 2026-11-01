#!/usr/bin/env bash

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=../../scripts/lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"
# shellcheck source=../../scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

project() {
    "${ROOT_DIR}/project.sh" "$@"
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        skip "需要 Docker：docker daemon 不可达"
    fi
}

require_build_artifact() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        skip "需要构建产物：${path} 缺失"
    fi
}

# 构建机判定：不硬编码主机名。设 YP_BUILD_HOST=<主机名> 时按主机名比对；
# 未设就跳过——CI runner 上没有构建产物，本来也该跳过。
require_build_host() {
    local want="${YP_BUILD_HOST:-}"
    if [[ -z "${want}" ]] || [[ "$(hostname)" != "${want}" ]]; then
        skip "需要构建机：设置 YP_BUILD_HOST=<构建机主机名> 后可真跑"
    fi
}

bats_version_info() {
    printf 'Bats: %s\nROOT_DIR: %s\n' "$(bats --version)" "${ROOT_DIR}"
}
