#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    LAYER_DIR="${ROOT_DIR}/layers/meta-yp"
    DISTRO_DIR="${LAYER_DIR}/conf/distro"
    IMAGE_DIR="${LAYER_DIR}/recipes-core/images"
}

# bats test_tags=layer
@test "layer declares exactly the four supported release series" {
    run grep '^LAYERSERIES_COMPAT_meta-yp' "${LAYER_DIR}/conf/layer.conf"
    [ "${status}" -eq 0 ]
    [ "${output}" = 'LAYERSERIES_COMPAT_meta-yp = "dunfell kirkstone scarthgap wrynose"' ]
}

# bats test_tags=layer
@test "yp distro declares the agreed identity" {
    [ -f "${DISTRO_DIR}/yp.conf" ]
    grep -qx 'DISTRO = "yp"' "${DISTRO_DIR}/yp.conf"
    grep -qx 'DISTRO_NAME = "YP (Yocto Platform)"' "${DISTRO_DIR}/yp.conf"
}

# bats test_tags=layer
@test "yp distro selects systemd before poky and requires both includes after identity" {
    run grep -vE '^[[:space:]]*(#|$)' "${DISTRO_DIR}/yp.conf"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = 'INIT_MANAGER = "systemd"' ]
    [ "${lines[1]}" = 'require conf/distro/poky.conf' ]
    [ "${lines[2]}" = 'DISTRO = "yp"' ]
    [ "${lines[3]}" = 'DISTRO_NAME = "YP (Yocto Platform)"' ]
    [ "${lines[4]}" = 'require conf/distro/include/yp-common.inc' ]
    [ "${lines[5]}" = 'require conf/distro/include/yp-compat.inc' ]
    # 身份与 include 之后只允许两类叠加：
    #   1) CVE 类的条件 INHERIT（必须放 distro 级，image 级会 SkipRecipe）
    #   2) virtual 提供者钉死（两种分隔符各一行）
    local extra
    extra="$(printf '%s\n' "${lines[@]:6}")"
    [[ "${extra}" == *'INHERIT += "${@bb.utils.contains'* ]]
    [[ "${extra}" == *'PREFERRED_PROVIDER_virtual/cpp-hello = "cpp-hello"'* ]]
    [[ "${extra}" == *'PREFERRED_PROVIDER:virtual/cpp-hello = "cpp-hello"'* ]]
}

# bats test_tags=layer
@test "common include is the sole source of version codename and maintainer" {
    local variable
    [ -f "${DISTRO_DIR}/include/yp-common.inc" ]
    grep -qx 'DISTRO_VERSION = "0.1.0"' "${DISTRO_DIR}/include/yp-common.inc"
    grep -qx 'DISTRO_CODENAME = "yp-phase0"' "${DISTRO_DIR}/include/yp-common.inc"
    grep -Eq '^MAINTAINER = "[^"]+"' "${DISTRO_DIR}/include/yp-common.inc"
    for variable in DISTRO_VERSION DISTRO_CODENAME MAINTAINER; do
        run grep -rlE "^${variable}[[:space:]]*=" "${LAYER_DIR}/conf"
        [ "${status}" -eq 0 ]
        [ "${output}" = "${DISTRO_DIR}/include/yp-common.inc" ]
    done
}

# bats test_tags=layer
@test "compat include is currently comments only and documents all releases" {
    [ -f "${DISTRO_DIR}/include/yp-compat.inc" ]
    run grep -nvE '^[[:space:]]*(#|$)' "${DISTRO_DIR}/include/yp-compat.inc"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        grep -q "${release}" "${DISTRO_DIR}/include/yp-compat.inc"
    done
}

# bats test_tags=layer
@test "yp images both require the oe-core minimal image" {
    local image
    for image in yp-image yp-image-minimal; do
        [ -f "${IMAGE_DIR}/${image}.bb" ]
        grep -qx 'require recipes-core/images/core-image-minimal.bb' "${IMAGE_DIR}/${image}.bb"
    done
}

# bats test_tags=layer
@test "reference image installs the cpp example by real package name" {
    grep -qx 'SUMMARY = "YP reference image"' "${IMAGE_DIR}/yp-image.bb"
    grep -qx 'IMAGE_INSTALL += "cpp-hello"' "${IMAGE_DIR}/yp-image.bb"
    # IMAGE_INSTALL 里的虚拟名在 do_rootfs 阶段按 RPROVIDES 解析，而 RPROVIDES
    # 不能带 virtual/ 前缀（6.0 QA virtual-slash），3.1~5.0 也会报
    # "Nothing RPROVIDES 'virtual/cpp-hello'"。所以镜像只装真实包名。
    run grep -qE '^IMAGE_INSTALL.*virtual/cpp-hello' "${IMAGE_DIR}/yp-image.bb"
    [ "${status}" -eq 1 ]
}

# bats test_tags=layer
@test "minimal image adds no packages or features to the baseline" {
    run grep -nvE '^(SUMMARY = "[^"]+"|require recipes-core/images/core-image-minimal\.bb|[[:space:]]*(#.*)?)$' \
        "${IMAGE_DIR}/yp-image-minimal.bb"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "layer configuration and core recipes have no unsupported colon overrides" {
    # 只查真正的代码行：yp-compat.inc 的说明性注释会引用冒号写法当例子。
    # recipes-example/ 不在此列——那是刻意的兼容性演示（两种分隔符各写一行）。
    run bash -c "grep -rnE ':(append|prepend|remove)\b|:[$][{]PN[}]' \
        '${LAYER_DIR}/conf' '${LAYER_DIR}/recipes-core' \
        | grep -vE ':[0-9]+:[[:space:]]*#|yp-common\\.inc:[0-9]+:DISTRO_FEATURES:remove = \"x11 wayland opengl 3g bluetooth nfs zeroconf\"$'"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "general variant leaves the oe-core image untouched" {
    # C27：general 直接用 core-image-minimal，所有差异都落在 custom 的 yp-image 上。
    # 曾经挂过 core-image-minimal.bbappend（EXTRA_IMAGEDEPENDS += cpp-hello-scancode），
    # #22 已删除；do_scancode 属 P2 未决能力（C26），不能重新挂回镜像。
    [ ! -f "${IMAGE_DIR}/core-image-minimal.bbappend" ]
    run grep -rn 'cpp-hello-scancode' "${IMAGE_DIR}"
    [ "${status}" -eq 1 ]
}

# bats test_tags=layer
@test "active layer config tests and docs contain no retired names" {
    local retired_names='meta-''zeek\|zeek-''distro\|core-image-''zeek'
    run git -C "${ROOT_DIR}" grep -n "${retired_names}" -- layers config tests docs
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "yp distro and images do not overwrite inherited feature baselines" {
    run grep -rnE '^[[:space:]]*(DISTRO_FEATURES|IMAGE_FEATURES)[[:space:]]*=' \
        "${LAYER_DIR}/conf" "${LAYER_DIR}/recipes-core"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}
