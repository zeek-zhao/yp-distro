SUMMARY = "YP CMake build-system demo"
DESCRIPTION = "Minimal CMake-built demo service for Yocto."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# For the CMake class, configure with EXTRA_OECMAKE and OECMAKE_C_FLAGS, not CFLAGS.
inherit cmake yp-service

S = "${UNPACKDIR}"
SRC_URI = "file://demo.c file://CMakeLists.txt file://yp-demo-cmake.service"

EXTRA_OECMAKE = "-DYP_DEMO_VARIANT=cmake"

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${B}/yp-demo-cmake ${D}${bindir}/yp-demo-cmake
}
