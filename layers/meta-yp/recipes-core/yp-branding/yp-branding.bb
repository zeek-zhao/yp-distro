SUMMARY = "YP distribution identity file"
DESCRIPTION = "机器可读的发行版身份（/etc/yp-release），供脚本与验收命令读取。\
issue / motd / hostname 由 base-files 的 bbappend 负责 —— 那三个路径原本就\
属于 base-files，另起包安装会撞 file conflict。"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://yp-release"

# 同 base-files 的 bbappend：6.0 解到 UNPACKDIR，3.1~5.0 解到 WORKDIR。
YP_BRAND_SRC = "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"

do_install() {
	install -d ${D}${sysconfdir}
	sed -e 's|@DISTRO_NAME@|${DISTRO_NAME}|g' \
	    -e 's|@DISTRO_VERSION@|${DISTRO_VERSION}|g' \
	    -e 's|@DISTRO_CODENAME@|${DISTRO_CODENAME}|g' \
	    -e 's|@MACHINE@|${MACHINE}|g' \
	    -e 's|@VARIANT@|${YP_BRAND_VARIANT}|g' \
	    -e 's|@DATE@|${YP_BRAND_DATE}|g' \
	    ${YP_BRAND_SRC}/yp-release > ${D}${sysconfdir}/yp-release
	chmod 0644 ${D}${sysconfdir}/yp-release
}

do_install[vardepsexclude] += "DATE YP_BRAND_DATE"

FILES:${PN} = "${sysconfdir}/yp-release"
