SUMMARY = "YP HTTP 状态服务"
DESCRIPTION = "读取 Linux procfs 并通过 HTTP 提供 JSON 状态信息"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://statusd.c file://Makefile file://yp-statusd.service"
S = "${UNPACKDIR}"

inherit yp-service

do_compile() {
    # 版本信息来自发行版变量，CFLAGS 则沿用 BitBake 的交叉编译参数。
    oe_runmake CC="${CC}" CFLAGS="${CFLAGS} -DYP_VERSION=\"${DISTRO_VERSION}\" -DYP_BUILD=\"${DISTRO}-${MACHINE}\" -DYP_MACHINE=\"${MACHINE}\"" LDFLAGS="${LDFLAGS}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 yp-statusd ${D}${bindir}/yp-statusd
}
