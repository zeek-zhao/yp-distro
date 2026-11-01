#!/usr/bin/env bats

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    RECIPE="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-statusd/yp-statusd_0.1.bb"
    SERVICE_UNIT="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-statusd/files/yp-statusd.service"
}

# bats test_tags=demo
@test "yp-statusd 配方使用服务模板和 6.0 解包目录" {
    [ -f "${RECIPE}" ]
    run grep -Fq 'inherit yp-service' "${RECIPE}"
    [ "${status}" -eq 0 ]
    run grep -Fq 'S = "${UNPACKDIR}"' "${RECIPE}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=demo
@test "yp-statusd unit 配置启动、重启和自启" {
    [ -f "${SERVICE_UNIT}" ]
    run grep -q '^ExecStart=' "${SERVICE_UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^Restart=' "${SERVICE_UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^WantedBy=multi-user.target' "${SERVICE_UNIT}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=demo
@test "配方和 unit 不使用 SysV init 注册" {
    run bash -c "grep -hE 'update-rc\\.d|/etc/init\\.d' '${RECIPE}' '${SERVICE_UNIT}' | grep -vE '^[[:space:]]*#'"
    [ "${status}" -ne 0 ]
}
