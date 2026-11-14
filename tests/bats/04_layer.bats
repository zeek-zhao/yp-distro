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
    # 身份细节收敛到单一真本 include/yp-release.inc（#57），yp.conf 只负责 require。
    grep -qx 'require conf/distro/include/yp-release.inc' "${DISTRO_DIR}/yp.conf"
    grep -qx 'DISTRO_NAME = "YP (Yocto Platform)"' "${DISTRO_DIR}/include/yp-release.inc"
}

# bats test_tags=layer
@test "yp distro selects systemd before poky and requires both includes after identity" {
    run grep -vE '^[[:space:]]*(#|$)' "${DISTRO_DIR}/yp.conf"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = 'INIT_MANAGER = "systemd"' ]
    [ "${lines[1]}" = 'require conf/distro/poky.conf' ]
    [ "${lines[2]}" = 'DISTRO = "yp"' ]
    [ "${lines[3]}" = 'require conf/distro/include/yp-release.inc' ]
    [ "${lines[4]}" = 'require conf/distro/include/yp-uboot.inc' ]
    [ "${lines[5]}" = 'require conf/distro/include/yp-common.inc' ]
    [ "${lines[6]}" = 'require conf/distro/include/yp-compat.inc' ]
    # 身份与 include 之后只允许两类叠加：
    #   1) CVE 类的条件 INHERIT（必须放 distro 级，image 级会 SkipRecipe）
    #   2) virtual 提供者钉死（两种分隔符各一行）
    local extra
    extra="$(printf '%s\n' "${lines[@]:7}")"
    [[ "${extra}" == *'INHERIT += "${@bb.utils.contains'* ]]
    [[ "${extra}" == *'PREFERRED_PROVIDER_virtual/cpp-hello = "cpp-hello"'* ]]
    [[ "${extra}" == *'PREFERRED_PROVIDER:virtual/cpp-hello = "cpp-hello"'* ]]
}

# bats test_tags=layer
@test "release include is the sole source of version codename and maintainer" {
    local variable
    [ -f "${DISTRO_DIR}/include/yp-release.inc" ]
    # 版本号与仓库最新 tag 一致（#130）：忘改 DISTRO_VERSION 会红，
    # 而不是「改了才红」——门禁语义是保护一致性，不是锁死一个值
    local expected_version
    expected_version="$(git -C "${ROOT_DIR}" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//')"
    [ -n "${expected_version}" ]
    grep -qx "DISTRO_VERSION = \"${expected_version}\"" "${DISTRO_DIR}/include/yp-release.inc"
    grep -qx 'DISTRO_CODENAME = "yp-product"' "${DISTRO_DIR}/include/yp-release.inc"
    grep -Eq '^MAINTAINER = "[^"]+"' "${DISTRO_DIR}/include/yp-common.inc"
    for variable in DISTRO_VERSION DISTRO_CODENAME; do
        run grep -rlE "^${variable}[[:space:]]*=" "${LAYER_DIR}/conf"
        [ "${status}" -eq 0 ]
        [ "${output}" = "${DISTRO_DIR}/include/yp-release.inc" ]
    done
    # MAINTAINER 仍是 yp-common.inc 的唯一真本
    run grep -rlE '^MAINTAINER[[:space:]]*=' "${LAYER_DIR}/conf"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${DISTRO_DIR}/include/yp-common.inc" ]
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
@test "full image installs the cpp example by real package name" {
    grep -qx 'SUMMARY = "YP full image —— 演示与开发"' "${IMAGE_DIR}/yp-image.bb"
    grep -qx 'IMAGE_INSTALL += "cpp-hello"' "${IMAGE_DIR}/yp-image.bb"
    # IMAGE_INSTALL 里的虚拟名在 do_rootfs 阶段按 RPROVIDES 解析，而 RPROVIDES
    # 不能带 virtual/ 前缀（6.0 QA virtual-slash），3.1~5.0 也会报
    # "Nothing RPROVIDES 'virtual/cpp-hello'"。所以镜像只装真实包名。
    run grep -qE '^IMAGE_INSTALL.*virtual/cpp-hello' "${IMAGE_DIR}/yp-image.bb"
    [ "${status}" -eq 1 ]
}

# bats test_tags=layer
@test "minimal image adds only branding, no business or debug packages" {
    # minimal 的定位是「裸底 + 品牌文件」，通过 include yp-image.inc 拿到品牌（#57）。
    # 它不得直接装业务/调试工具，也不得 include runtime（那会拉 curl/tar/procps）。
    grep -qx 'require recipes-core/images/core-image-minimal.bb' "${IMAGE_DIR}/yp-image-minimal.bb"
    grep -qx 'include yp-image.inc' "${IMAGE_DIR}/yp-image-minimal.bb"
    run grep -q 'include yp-image-runtime.inc' "${IMAGE_DIR}/yp-image-minimal.bb"
    [ "${status}" -eq 1 ]
    run grep -qE '^IMAGE_INSTALL.*(cpp-hello|wget|python3|strace|gdbserver)' "${IMAGE_DIR}/yp-image-minimal.bb"
    [ "${status}" -eq 1 ]
}

# bats test_tags=layer
@test "layer configuration and core recipes have no unsupported colon overrides" {
    # 这里禁的是**变量级**冒号 override：它在 dunfell 3.1 上静默失效（不报错，整行
    # 不起作用）。任务级的 `do_install:append()` 在 3.1 上是生效的（f66f35b 用探针
    # 配方实测过 3.1.33 / BitBake 1.46），不在此列——别把两者混为一谈。
    # 因此只允许两类：
    #   1) yp-common.inc 的 DISTRO_FEATURES:remove —— 有 3.1 运行时 d.setVar 兜底；
    #   2) #57~#60 的 6.0 先行 recipe/bbappend（品牌化 / 三层镜像 / journald / 服务模板）
    #      —— D12 决策「6.0 先行，3.1/4.0 冻结为实验田」，这些文件只在 wrynose 上要求
    #      生效，3.1/4.0 的功能降级由 v0.7.0 统一补。白名单文件逐一列出，防止
    #      未经审视的新 override 混进来。
    # recipes-example/ 不在此列——那是刻意的兼容性演示（两种分隔符各写一行）。
    # yp-compat.inc 的说明性注释会引用冒号写法当例子，走注释过滤。
    local allowed
    allowed='yp-common\.inc|yp-image\.inc|yp-hello-svc\.bb|yp-branding\.bb|yp-journald-persist\.bb|base-files_%\.bbappend|os-release\.bbappend|systemd_%\.bbappend'
    run bash -c "grep -rnE ':(append|prepend|remove)\b|:[$][{]PN[}]' \
        '${LAYER_DIR}/conf' '${LAYER_DIR}/recipes-core' \
        | grep -vE ':[0-9]+:[[:space:]]*#' \
        | grep -vE '(${allowed}):[0-9]+:'"
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
    # docs/08-tasks/archive 是历史任务卡归档，保留改名史叙述，豁免 retired-names 检查。
    run git -C "${ROOT_DIR}" grep -n "${retired_names}" -- layers config tests docs ':(exclude)docs/08-tasks/archive'
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
