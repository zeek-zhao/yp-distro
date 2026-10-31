#!/usr/bin/env bats
# yp-service.bbclass 的结构断言。真机行为（is-enabled / is-active / journalctl）
# 在 docs/qa/ 的验收记录里，这里只保证「机制本身没有退化」。

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    BBCLASS="${ROOT_DIR}/layers/meta-yp/classes/yp-service.bbclass"
    SAMPLE_RECIPE="${ROOT_DIR}/layers/meta-yp/recipes-core/yp-hello-svc/yp-hello-svc.bb"
    SERVICE_UNIT="${ROOT_DIR}/layers/meta-yp/recipes-core/yp-hello-svc/files/yp-hello-svc.service"
    FULL_IMAGE="${ROOT_DIR}/layers/meta-yp/recipes-core/images/yp-image.bb"
}

# bats test_tags=service
@test "yp-service bbclass exists and inherits the systemd class" {
    [ -f "${BBCLASS}" ]
    run grep -qE '^inherit systemd$' "${BBCLASS}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=service
@test "bbclass declares SYSTEMD_SERVICE with both override separators" {
    # 3.1 只认下划线、4.0+ 只认冒号；缺一行就会有版本静默不注册
    run grep -q 'SYSTEMD_SERVICE_${PN}' "${BBCLASS}"
    [ "${status}" -eq 0 ]
    run grep -q 'SYSTEMD_SERVICE:${PN}' "${BBCLASS}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=service
@test "bbclass never falls back to sysvinit registration" {
    # 反向断言：6.0 没有 systemd-compat-units，init 脚本不会被接管
    # 只看代码行：bbclass 顶部注释里提到 /etc/init.d 是在解释「为什么不给兼容路径」
    run bash -c "grep -E 'update-rc\.d|/etc/init\.d' '${BBCLASS}' | grep -vE '^[[:space:]]*#'"
    [ "${status}" -ne 0 ]
}

# bats test_tags=service
@test "sample recipe inherits yp-service and ships a unit file" {
    [ -f "${SAMPLE_RECIPE}" ]
    run grep -q 'inherit yp-service' "${SAMPLE_RECIPE}"
    [ "${status}" -eq 0 ]
    [ -f "${SERVICE_UNIT}" ]
}

# bats test_tags=service
@test "sample unit targets multi-user and logs to journal" {
    run grep -q '^WantedBy=multi-user.target' "${SERVICE_UNIT}"
    [ "${status}" -eq 0 ]
    run grep -q '^StandardOutput=journal' "${SERVICE_UNIT}"
    [ "${status}" -eq 0 ]
    # default.target 不是三层镜像的统一目标，出现即为漂移
    run grep -q '^WantedBy=default.target' "${SERVICE_UNIT}"
    [ "${status}" -ne 0 ]
}

# bats test_tags=service
@test "full image installs the sample service" {
    run grep -q 'IMAGE_INSTALL += "yp-hello-svc"' "${FULL_IMAGE}"
    [ "${status}" -eq 0 ]
}
