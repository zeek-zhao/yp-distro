#!/usr/bin/env bats
# 启动时间解析的夹具测试：不起机，只验「能不能正确认出来」。
# 真机数字在 docs/qa/boot-baseline.md，这里保证的是判定逻辑不退化。

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${ROOT_DIR}/scripts/boot-time.sh"
    FIXTURES="${BATS_TEST_DIRNAME}/../fixtures/boottime"
}

# bats test_tags=boottime
@test "boot-time script is syntactically valid bash" {
    run bash -n "${SCRIPT}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=boottime
@test "parses a normal serial log with uboot, kernel and login" {
    run bash "${SCRIPT}" --from-log "${FIXTURES}/normal.log"
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q '"login": true'
    echo "${output}" | grep -q '"uboot": true'
    echo "${output}" | grep -q '"kernel": true'
}

# bats test_tags=boottime
@test "ignores runqemu INFO noise before the kernel line" {
    run bash "${SCRIPT}" --from-log "${FIXTURES}/runqemu-noise.log"
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q '"kernel": true'
}

# bats test_tags=boottime
@test "a log without login is a failure, not a zero" {
    run bash "${SCRIPT}" --from-log "${FIXTURES}/no-login.log"
    [ "${status}" -eq 3 ]
    echo "${output}" | grep -q '"login": false'
}

# bats test_tags=boottime
@test "kernel-only log (no bootloader) still reports login and kernel" {
    run bash "${SCRIPT}" --from-log "${FIXTURES}/kernel-only.log"
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q '"kernel": true'
    echo "${output}" | grep -q '"uboot": false'
}

# bats test_tags=boottime
@test "wall clock is never fabricated in replay mode" {
    run bash "${SCRIPT}" --from-log "${FIXTURES}/normal.log"
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q '"wall_ms": null'
}
