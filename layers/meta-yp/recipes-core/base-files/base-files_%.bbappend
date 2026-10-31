FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://yp-issue file://yp-motd"

# file:// 的落点各版本不同：6.0 解到 UNPACKDIR（${WORKDIR}/sources），
# 3.1~5.0 没有这个变量、直接解到 WORKDIR。用一个变量兜住两种布局，
# 不去改上游 SRC_URI 的既定行为。
YP_BRAND_SRC = "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"

# hostname 默认就是裸 MACHINE（qemux86-64），登录后看不出这是 YP 的镜像。
hostname = "yp-${MACHINE}"

# /etc/issue、/etc/issue.net、/etc/motd 三个文件本来都由 base-files 自己装。
# 不另起一个 yp-branding 包往同一路径装东西 —— 两个包提供同一个文件，
# do_rootfs 会直接报 file conflict。所以在同一个 recipe 内重写内容。
do_install:append() {
	for f in issue issue.net motd; do
		tmpl="${YP_BRAND_SRC}/yp-${f}"
		# issue.net 没有独立模板，沿用 issue 的内容
		[ -f "${tmpl}" ] || tmpl="${YP_BRAND_SRC}/yp-issue"
		sed -e 's|@DISTRO_NAME@|${DISTRO_NAME}|g' \
		    -e 's|@DISTRO_VERSION@|${DISTRO_VERSION}|g' \
		    -e 's|@DISTRO_CODENAME@|${DISTRO_CODENAME}|g' \
		    -e 's|@MACHINE@|${MACHINE}|g' \
		    -e 's|@VARIANT@|${YP_BRAND_VARIANT}|g' \
		    -e 's|@DATE@|${YP_BRAND_DATE}|g' \
		    "${tmpl}" > "${D}${sysconfdir}/${f}"
		chmod 0644 "${D}${sysconfdir}/${f}"
	done
}

# motd/issue 里带构建日期，排除出 vardeps，否则同样的源码会因日期不同被判成新任务。
do_install[vardepsexclude] += "DATE YP_BRAND_DATE"
