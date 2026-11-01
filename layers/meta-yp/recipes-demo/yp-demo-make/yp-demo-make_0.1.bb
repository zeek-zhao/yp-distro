SUMMARY = "YP demo: plain make (C 系构建系统参照实现)"
DESCRIPTION = "手写 Makefile 的 C 程序，作为 cmake/autotools/meson 的参照实现。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# 6.0 的 file:// 源解包到 UNPACKDIR（${WORKDIR}/sources）；沿用 ${WORKDIR} 会找不到 demo.c。
S = "${YP_SRC_DIR}"

SRC_URI = "file://demo.c file://Makefile file://yp-demo-make.service"

# 关键变量：CC/CFLAGS/LDFLAGS 必须从 bitbake 经 oe_runmake 转发，
# 写死 gcc/-O2 会让交叉编译与 DEBUG_BUILD/-D_FORTIFY_SOURCE 失效。
inherit yp-service

do_compile() {
    # 引号由 files/Makefile 加，这里传裸值（否则 gcc 看到 'make' 未声明）。
    oe_runmake CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" YP_DEMO_VARIANT="make"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 yp-demo-make ${D}${bindir}/
}
