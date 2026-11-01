# autotools 在 Yocto 里的关键变量是 EXTRA_OECONF，用于传递 configure 开关。
# 需要 autoconf-archive 宏时加 DEPENDS += "autoconf-archive-native"。
SUMMARY = "Minimal autotools Hello World demo"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://configure.ac \
           file://Makefile.am \
           file://demo.c \
           file://yp-demo-autotools.service \
"
S = "${YP_SRC_DIR}"

inherit autotools pkgconfig yp-service

EXTRA_OECONF = "--disable-static --enable-json"

yp_demo_autotools_prepare_m4() {
    mkdir -p ${S}/m4
}

do_configure:prepend() {
    yp_demo_autotools_prepare_m4
}

# 任务级冒号语法 3.1 也认，不需要再补下划线版（见 yp-service.bbclass 同段注释）。
do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/yp-demo-autotools ${D}${bindir}/yp-demo-autotools
}
