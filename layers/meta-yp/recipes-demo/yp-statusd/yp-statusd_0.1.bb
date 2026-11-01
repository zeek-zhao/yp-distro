SUMMARY = "YP HTTP 状态服务"
DESCRIPTION = "读取 Linux procfs 并通过 HTTP 提供 JSON 状态信息"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://statusd.c file://Makefile file://yp-statusd.service"
S = "${YP_SRC_DIR}"

inherit yp-service

do_compile() {
    # 字符串宏的引号由 files/Makefile 负责，这里只传裸值：
    # 在 CFLAGS 里拼 \" 会被 make/sh 吃掉一层，gcc 收到裸数字（见 Makefile 注释）。
    oe_runmake CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" \
        YP_VERSION="${DISTRO_VERSION}" \
        YP_BUILD="${DISTRO}-${MACHINE}" \
        YP_MACHINE="${MACHINE}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 yp-statusd ${D}${bindir}/yp-statusd
}
