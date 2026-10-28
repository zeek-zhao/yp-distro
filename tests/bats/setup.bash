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

require_215() {
    if [[ "$(hostname)" != "RSZ-ED-SVR148" ]]; then
        skip "需要 215：当前主机不是构建节点"
    fi
}

bats_version_info() {
    printf 'Bats: %s\nROOT_DIR: %s\n' "$(bats --version)" "${ROOT_DIR}"
}
