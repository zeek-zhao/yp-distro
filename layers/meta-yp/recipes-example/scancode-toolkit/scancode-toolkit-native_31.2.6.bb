SUMMARY = "ScanCode toolkit"
DESCRIPTION = "A typical software project often reuses hundreds of third-party \
packages. License and origin information is not always easy to find and not \
normalized: ScanCode discovers and normalizes this data for you."
HOMEPAGE = "https://github.com/nexB/scancode-toolkit"
SECTION = "devel"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://NOTICE;md5=da825e8d0e20b6f71daab410ce16ba77"

SRC_URI = "https://github.com/aboutcode-org/scancode-toolkit/archive/refs/tags/v${PV}.tar.gz;downloadfilename=scancode-toolkit-${PV}.tar.gz"
SRC_URI[md5sum] = "a59ebe32689cc7c0f71adca5dfdebda7"

S = "${WORKDIR}/scancode-toolkit-${PV}"

inherit native

# Use host's scancode installation
SCANCODE_HOST_DIR ?= "/workspace/resources/scancode-toolkit-31.2.6"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${bindir}
    
    # Create wrapper scripts that call the host scancode directly
    cat > ${D}${bindir}/scancode << EOF
#!/bin/bash
exec ${SCANCODE_HOST_DIR}/scancode "\$@"
EOF
    chmod +x ${D}${bindir}/scancode
    
    cat > ${D}${bindir}/extractcode << EOF
#!/bin/bash
exec ${SCANCODE_HOST_DIR}/extractcode "\$@"
EOF
    chmod +x ${D}${bindir}/extractcode
}

INSANE_SKIP:${PN} += "file-rdeps"
