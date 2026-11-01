#!/usr/bin/env bats

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    RECIPE="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-collectd/yp-collectd_0.1.bb"
    UNIT="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-collectd/files/yp-collectd.service"
    SOURCE="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-collectd/files/collectd.c"
    MAKEFILE="${ROOT_DIR}/layers/meta-yp/recipes-demo/yp-collectd/files/Makefile"
}

# bats test_tags=demo
@test "collectd 配方使用 yp-service 并从 UNPACKDIR 构建" {
    [ -f "${RECIPE}" ]
    run grep -q '^inherit yp-service$' "${RECIPE}"
    [ "${status}" -eq 0 ]
    run grep -Fq 'S = "${UNPACKDIR}"' "${RECIPE}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=demo
@test "collectd unit 具有默认环境配置并加入多用户目标" {
    run grep -q '^WantedBy=multi-user.target$' "${UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^EnvironmentFile=.*yp-collectd$' "${UNIT}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=demo
@test "默认配置文件明确纳入 collectd 软件包" {
    run grep -Fq 'FILES:${PN} += "${sysconfdir}/default/yp-collectd"' "${RECIPE}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=demo
@test "采集服务不引入旧式日志轮转或 init 注册机制" {
    run bash -c 'grep -En "logrotate|update-rc\.d|/etc/init\.d" "$@" | grep -vE "^[^:]+:[0-9]+:[[:space:]]*#"' _ \
        "${RECIPE}" "${UNIT}" "${SOURCE}" "${MAKEFILE}"
    [ "${status}" -ne 0 ]
}

# bats test_tags=demo
@test "采集指标写入 stdout 后立即刷新" {
    run grep -Eq 'fflush[[:space:]]*\(|setvbuf[[:space:]]*\(' "${SOURCE}"
    [ "${status}" -eq 0 ]
}
