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
S = "${UNPACKDIR}"

inherit autotools pkgconfig yp-service

EXTRA_OECONF = "--disable-static --enable-json"

do_configure:prepend() {
    mkdir -p ${S}/m4
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/yp-demo-autotools ${D}${bindir}/yp-demo-autotools
}
