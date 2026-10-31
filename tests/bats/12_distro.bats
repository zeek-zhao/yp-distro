#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    LAYER_DIR="${ROOT_DIR}/layers/meta-yp"
    DISTRO_DIR="${LAYER_DIR}/conf/distro"
    COMMON_INC="${DISTRO_DIR}/include/yp-common.inc"
}

# bats test_tags=distro
@test "systemd is selected before poky consumes INIT_MANAGER" {
    local init_line poky_line
    init_line="$(awk '$0 == "INIT_MANAGER = \"systemd\"" { print NR; exit }' "${DISTRO_DIR}/yp.conf")"
    poky_line="$(awk '$0 == "require conf/distro/poky.conf" { print NR; exit }' "${DISTRO_DIR}/yp.conf")"
    [ -n "${init_line}" ]
    [ -n "${poky_line}" ]
    [ "${init_line}" -lt "${poky_line}" ]
}

# bats test_tags=distro
@test "distro removes only the selected features with both override syntaxes" {
    # ptest 是 #59 加的：镜像不带 ptest 子包，否则 -ptest 的 locale-base-* 依赖会判致命 QA
    local remove_list='x11 wayland opengl 3g bluetooth nfs zeroconf ptest'
    grep -qx "DISTRO_FEATURES:remove = \"${remove_list}\"" "${COMMON_INC}"
    grep -Fqx "        d.setVar(\"DISTRO_FEATURES_remove\", \"${remove_list}\")" "${COMMON_INC}"
    grep -Fqx '    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():' "${COMMON_INC}"
    run grep -rnE '^[[:space:]]*(DISTRO_FEATURES|IMAGE_FEATURES)[[:space:]]*=' \
        "${LAYER_DIR}/conf" "${LAYER_DIR}/recipes-core"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=distro
@test "distro does not explicitly remove systemd or sysvinit as a feature" {
    run grep -nE '^[[:space:]]*DISTRO_FEATURES(:remove|_remove).*([[:space:]]|^)(systemd|sysvinit)([[:space:]]|")' "${COMMON_INC}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}
