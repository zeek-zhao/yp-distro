#!/usr/bin/env bats
# SDK / eSDK 产出与归档（issue #25）。
# 只验证脚本契约与渲染逻辑；真构建靠 scripts/sdk.sh 在构建机上跑（需要几十 GB 磁盘）。

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    mkdir -p "${ROOT_DIR}/work"
    test_root="$(mktemp -d "${ROOT_DIR}/work/sdk-test.XXXXXX")"
    sdk_json="${test_root}/sdk.json"
    sdk_archive="${test_root}/sdk.md"
}

teardown() {
    if [[ -n "${test_root:-}" ]]; then
        rm -rf -- "${test_root}"
    fi
}

write_sdk_json() {
    local gcc="${1:-13.3.0}" devtool="${2:-ok}"
    cat >"${sdk_json}" <<JSON
{
  "release": "scarthgap",
  "variant": "custom",
  "machine": "qemux86-64",
  "tag": "yocto-5.0.20",
  "commit": "abcdef1",
  "date": "20260101",
  "build_seconds": 812,
  "sdk": {
    "file": "yp-image-qemux86-64-toolchain-5.0.20.sh",
    "relative": "work/kas-scarthgap-custom/build/tmp/deploy/sdk/yp-image-qemux86-64-toolchain-5.0.20.sh",
    "bytes": 987654321,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "installed": true,
    "gcc": "${gcc}"
  },
  "esdk": {
    "file": "yp-image-qemux86-64-toolchain-ext-5.0.20.sh",
    "relative": "work/kas-scarthgap-custom/build/tmp/deploy/sdk/yp-image-qemux86-64-toolchain-ext-5.0.20.sh",
    "bytes": 1234567890,
    "sha256": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
    "installed": true,
    "devtool": "${devtool}"
  }
}
JSON
}

# bats test_tags=sdk
@test "sdk.sh dry-run 打印工作区、产物目录与两条 bitbake 命令" {
    run bash "${ROOT_DIR}/scripts/sdk.sh" --release scarthgap --variant custom --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"work/kas-scarthgap-custom"* ]]
    [[ "${output}" == *"deploy/sdk"* ]]
    [[ "${output}" == *"bitbake -c populate_sdk"* ]]
    [[ "${output}" == *"bitbake -c populate_sdk_ext"* ]]
}

# bats test_tags=sdk
@test "sdk.sh 校验必填参数与取值" {
    run bash "${ROOT_DIR}/scripts/sdk.sh" --variant custom
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/sdk.sh" --release scarthgap --variant bogus
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/sdk.sh" --release nope --variant custom
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/sdk.sh" --release scarthgap --variant custom --machine nope
    [ "${status}" -eq 2 ]
}

# bats test_tags=sdk
@test "report.sh --sdk 在缺少 sdk.json 时给出可执行的下一步" {
    run env YP_SDK_JSON="${test_root}/missing.json" \
        bash "${ROOT_DIR}/scripts/report.sh" --release scarthgap --variant custom --sdk
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"scripts/sdk.sh"* ]]
}

# bats test_tags=sdk
@test "report.sh --sdk 渲染体积、SHA-256、gcc 版本与 PASS 结论" {
    write_sdk_json "13.3.0" "ok"
    run env YP_SDK_JSON="${sdk_json}" YP_SDK_ARCHIVE="${sdk_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release scarthgap --variant custom --sdk
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"PASS"* ]]
    run grep -F 'yp-image-qemux86-64-toolchain-5.0.20.sh' "${sdk_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '0123456789abcdef' "${sdk_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '987654321' "${sdk_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '`13.3.0`' "${sdk_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '**PASS' "${sdk_archive}"
    [ "${status}" -eq 0 ]
    # 需求 §7.3：不允许降级，所以结论里必须显式带上这条约束
    run grep -F '不允许降级' "${sdk_archive}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=sdk
@test "report.sh --sdk 在 devtool 不可用时判 FAIL 并返回非零" {
    write_sdk_json "13.3.0" "missing"
    run env YP_SDK_JSON="${sdk_json}" YP_SDK_ARCHIVE="${sdk_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release scarthgap --variant custom --sdk
    [ "${status}" -ne 0 ]
    run grep -F '**FAIL' "${sdk_archive}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=sdk
@test "report.sh --sdk 拒绝 all" {
    run bash "${ROOT_DIR}/scripts/report.sh" --release all --sdk
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"--sdk 不支持 all"* ]]
}
