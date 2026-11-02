#!/usr/bin/env bats
# deploy 新鲜度门禁的夹具测试（#114）。
# 完整的功能路径（stale/missing-stamp/fresh）依赖构建机状态，在 CI 上没有
# work/ 构建目录——guard 对此安静放行；这里保证脚本有效、build.sh 真的盖章、
# 以及参数处理不崩溃。

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    GUARD="${ROOT_DIR}/scripts/deploy-guard.sh"
    BUILD="${ROOT_DIR}/scripts/build.sh"
}

# bats test_tags=deploy-guard
@test "deploy-guard and build scripts are syntactically valid bash" {
    run bash -n "${GUARD}"
    [ "${status}" -eq 0 ]
    run bash -n "${BUILD}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=deploy-guard
@test "build.sh stamps fingerprint on success (guard's data source exists)" {
    grep -q '\.yp-fingerprint' "${BUILD}"
    grep -q 'source_fingerprint' "${BUILD}"
    grep -q 'source_fingerprint' "${ROOT_DIR}/scripts/lib/common.sh"
}

# bats test_tags=deploy-guard
@test "deploy-guard --all runs on any machine (0=fresh/none, 1=stale, never crashes)" {
    run bash "${GUARD}" --all
    [[ "${status}" -eq 0 || "${status}" -eq 1 ]]
}

# bats test_tags=deploy-guard
@test "deploy-guard --all rejects combo flags (die -> exit 1)" {
    run bash "${GUARD}" --all --release wrynose
    [ "${status}" -eq 1 ]
}

# bats test_tags=deploy-guard
@test "deploy-guard rejects unknown flags (die -> exit 1)" {
    run bash "${GUARD}" --nonsense
    [ "${status}" -eq 1 ]
}

# bats test_tags=deploy-guard
@test "deploy-guard passes quietly for a never-built combo" {
    run bash "${GUARD}" --release nonexistent --variant custom
    [ "${status}" -eq 0 ]
    echo "${output}" | grep -q "从未构建，放行"
}
