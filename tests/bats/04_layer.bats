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
@test "yp distro requires poky before identity and both includes after it" {
    run grep -vE '^[[:space:]]*(#|$)' "${DISTRO_DIR}/yp.conf"
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 5 ]
    [ "${lines[0]}" = 'require conf/distro/poky.conf' ]
    [ "${lines[1]}" = 'DISTRO = "yp"' ]
    [ "${lines[2]}" = 'DISTRO_NAME = "YP (Yocto Platform)"' ]
    [ "${lines[3]}" = 'require conf/distro/include/yp-common.inc' ]
    [ "${lines[4]}" = 'require conf/distro/include/yp-compat.inc' ]
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
@test "reference image installs the cpp example" {
    grep -qx 'SUMMARY = "YP reference image"' "${IMAGE_DIR}/yp-image.bb"
    grep -qx 'IMAGE_INSTALL += " virtual/cpp-hello"' "${IMAGE_DIR}/yp-image.bb"
}

# bats test_tags=layer
@test "minimal image adds no packages or features to the baseline" {
    run grep -nvE '^(SUMMARY = "[^"]+"|require recipes-core/images/core-image-minimal\.bb|[[:space:]]*(#.*)?)$' \
        "${IMAGE_DIR}/yp-image-minimal.bb"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "layer configuration and core recipes have no colon overrides" {
    run grep -rnE ':(append|prepend|remove)\b|:[$][{]PN[}]' \
        "${LAYER_DIR}/conf" "${LAYER_DIR}/recipes-core"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "core minimal bbappend retains the general variant example" {
    [ -f "${IMAGE_DIR}/core-image-minimal.bbappend" ]
    grep -qx 'EXTRA_IMAGEDEPENDS += "cpp-hello-scancode"' "${IMAGE_DIR}/core-image-minimal.bbappend"
    grep -qx 'IMAGE_INSTALL += "virtual/cpp-hello"' "${IMAGE_DIR}/core-image-minimal.bbappend"
}

# bats test_tags=layer
@test "active layer config tests and docs contain no retired names" {
    local retired_names='meta-''zeek\|zeek-''distro\|core-image-''zeek'
    run git -C "${ROOT_DIR}" grep -n "${retired_names}" -- layers config tests docs
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# bats test_tags=layer
@test "yp distro and images leave poky features and init manager untouched" {
    run grep -rnE '^[[:space:]]*(DISTRO_FEATURES[^[:space:]]*|IMAGE_FEATURES|INIT_MANAGER)[[:space:]]*[?+.:=-]*=' \
        "${LAYER_DIR}/conf" "${LAYER_DIR}/recipes-core"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}
