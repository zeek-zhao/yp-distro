SUMMARY = "YP service template example (daemon, journal-logged)"
DESCRIPTION = "验证 yp-service.bbclass 的最小常驻服务：每 10 秒往 journal 打一条，\
用来确认 unit 注册、开机自启、日志归属三件事都成立。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# 只认 .service：见 yp-service.bbclass 顶部关于 6.0 无兼容层的说明。
inherit yp-service

# 6.0 把 file:// 解到 UNPACKDIR（${WORKDIR}/sources），3.1~5.0 直接解到 WORKDIR。
YP_SRC_DIR ?= "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"

SRC_URI = "file://yp-hello-svc file://yp-hello-svc.service"

YP_SERVICE_NAME = "yp-hello-svc"

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${YP_SRC_DIR}/yp-hello-svc ${D}${bindir}/yp-hello-svc
}

FILES:${PN} = "${bindir}/yp-hello-svc"
