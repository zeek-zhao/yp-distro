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

# ---- 管道回放（#110）：不起机，直接对 monitor_stream 喂字节流 ----

setup_marks() {
    MARKS="$(mktemp)"
    rm -f "${MARKS}" "${MARKS}".*
    # shellcheck source=scripts/lib/boot-marks.sh
    source "${ROOT_DIR}/scripts/lib/boot-marks.sh"
}

# bats test_tags=boottime
@test "monitor_stream marks login through a real tee pipe (prompt has no trailing newline)" {
    setup_marks
    printf '[    0.000000] kernel line\r\nU-Boot 2026.01\r\nyp-qemux86-64 login: ' \
        | tee >(monitor_stream) >/dev/null
    # bash 不等进程替换收尾就往下走；逐字符消费几十字节是毫秒级，给足调度时间
    for _ in $(seq 1 50); do [[ -f "${MARKS}.login" ]] && break; sleep 0.1; done
    [[ -n "$(mark login)" ]]
    [[ -n "$(mark kernel)" ]]
    [[ -n "$(mark uboot)" ]]
    rm -f "${MARKS}" "${MARKS}".*
}

# bats test_tags=boottime
@test "mark() returns empty instead of aborting under set -e when marks file is missing" {
    run bash -c 'set -euo pipefail
        MARKS=/nonexistent/boot-marks
        source "'"${ROOT_DIR}"'/scripts/lib/boot-marks.sh"
        v="$(mark login)"
        echo "v=${v}"'
    [ "${status}" -eq 0 ]
    [[ "${output}" == "v=" ]]
}
