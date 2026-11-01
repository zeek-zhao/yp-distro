SUMMARY = "Hello World application built with Meson"
SECTION = "examples"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Meson's key Yocto variables are EXTRA_OEMESON and MESON_BUILDTYPE.
SRC_URI = "file://meson.build file://meson_options.txt file://demo.c file://yp-demo-meson.service"

S = "${UNPACKDIR}"

inherit meson pkgconfig yp-service

MESON_BUILDTYPE = "release"
EXTRA_OEMESON = "-Djson=true"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/yp-demo-meson ${D}${bindir}/yp-demo-meson
}
