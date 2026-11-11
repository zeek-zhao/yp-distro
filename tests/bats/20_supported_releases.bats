#!/usr/bin/env bats
# 受支持 release 单一事实源的校验（#127）。
# config/supported-releases.txt 是「哪些 release 受保障」的唯一出处：
# release-check 默认范围、03_container 遍历、CI 拉镜像都从它取值。

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    FILE="${ROOT_DIR}/config/supported-releases.txt"
    KNOWN="dunfell kirkstone scarthgap wrynose"
}

# bats test_tags=release-check
@test "supported-releases file exists and is non-empty" {
    [ -s "${FILE}" ]
}

# bats test_tags=release-check
@test "every line in supported-releases is a known release" {
    while read -r release; do
        [ -n "${release}" ] || continue
        [[ "${KNOWN}" == *"${release}"* ]]
        # 冻结口径：EOL 版本（dunfell/kirkstone）不再受保障
        ! [[ "${release}" == "dunfell" || "${release}" == "kirkstone" ]]
    done < "${FILE}"
}

# bats test_tags=release-check
@test "wrynose is in the supported list (6.0 是当前单点)" {
    grep -qx "wrynose" "${FILE}"
}

# bats test_tags=release-check
@test "release-check default scope follows the single source" {
    grep -q "config/supported-releases.txt" "${ROOT_DIR}/scripts/release-check.sh"
}
