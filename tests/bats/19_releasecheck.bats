#!/usr/bin/env bats
# release-check 编排脚本的夹具测试（#115）。真跑 8 组合是点版本流程的事，
# 这里保证脚本有效、默认范围正确（只含两个受支持的 LTS）、参数处理不崩溃。

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${ROOT_DIR}/scripts/release-check.sh"
}

# bats test_tags=release-check
@test "release-check is syntactically valid bash" {
    run bash -n "${SCRIPT}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=release-check
@test "default scope is the two supported LTS only" {
    grep -q 'releases="wrynose,scarthgap"' "${SCRIPT}"
    grep -q 'wrynose/scarthgap）' "${SCRIPT}"
    ! grep -q 'releases="dunfell' "${SCRIPT}"
}

# bats test_tags=release-check
@test "unknown release is rejected before any build runs" {
    run bash "${SCRIPT}" --releases nosuchrelease --variants general
    [ "${status}" -ne 0 ]
    echo "${output}" | grep -q "未知 release"
}

# bats test_tags=release-check
@test "help describes scope and machine dimension" {
    run bash "${SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--machine"* ]]
    [[ "${output}" == *"qemuarm64"* ]]
}
