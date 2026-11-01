SUMMARY = "定时采集系统运行指标并输出到日志"
DESCRIPTION = "读取 procfs 指标并输出 JSON，由 journald 负责日志容量管理。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# 6.0 将 file:// 源解到 UNPACKDIR，因此源码目录不能沿用 WORKDIR。
S = "${YP_SRC_DIR}"
SRC_URI = "file://collectd.c file://Makefile file://yp-collectd.service file://yp-collectd.default"

inherit yp-service

do_compile() {
    oe_runmake CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/yp-collectd ${D}${bindir}/yp-collectd
    install -d ${D}${sysconfdir}/default
    install -m 0644 ${S}/yp-collectd.default ${D}${sysconfdir}/default/yp-collectd
}

FILES:${PN} += "${sysconfdir}/default/yp-collectd"
