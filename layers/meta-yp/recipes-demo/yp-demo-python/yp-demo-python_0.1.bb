SUMMARY = "YP Python demo service"
DESCRIPTION = "Minimal Python PEP 517 demo managed by systemd."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Python 6.0 build key: PEP517_BUILD_API selects the PEP 517 backend.
inherit python_setuptools_build_meta yp-service

SRC_URI = "file://pyproject.toml file://yp_demo_py.py file://yp-demo-python.service"
S = "${UNPACKDIR}"

RDEPENDS:${PN} += "python3-core python3-json"

# Python uses the PEP 517 backend in 6.0; there is no do_compile task.
do_install:append() {
	install -d ${D}${bindir}
	install -m 0755 ${S}/yp_demo_py.py ${D}${bindir}/yp-demo-python
}
