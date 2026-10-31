SUMMARY = "Persistent journald quota for the full image layer"
DESCRIPTION = "覆盖 systemd 主配置里的 volatile，让 full 层把日志落盘并封顶。\
minimal / base 不装这个包：那两层的定位是「最快起来」与「最小可用」，\
不需要跨重启保留日志。"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# 6.0 把 file:// 解到 UNPACKDIR（${WORKDIR}/sources），3.1~5.0 直接解到 WORKDIR。
YP_SRC_DIR ?= "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"

SRC_URI = "file://90-persist.conf"

do_install() {
	install -d ${D}${sysconfdir}/systemd/journald.conf.d
	install -m 0644 ${YP_SRC_DIR}/90-persist.conf ${D}${sysconfdir}/systemd/journald.conf.d/90-persist.conf
}

FILES:${PN} = "${sysconfdir}/systemd/journald.conf.d/90-persist.conf"
