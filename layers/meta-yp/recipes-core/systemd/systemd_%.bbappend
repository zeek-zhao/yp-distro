# journald 自己管容量，不引 logrotate。
# logrotate 处理不了 journal 的二进制文件，还得额外养一个 cron/timer 去调它；
# 而 journald 原生就有 SystemMaxUse / RuntimeMaxUse。
#
# 主配置取 volatile：镜像容量小，日志落盘会在「跑几天之后」把分区写满，
# 这种症状排查成本高、收益为零。full 层另有 90-persist.conf 的 drop-in
# 覆盖成 persistent + 封顶（见 yp-journald-persist）。
yp_systemd_journald_conf() {
	conf="${D}${sysconfdir}/systemd/journald.conf"
	if [ -f "${conf}" ]; then
		sed -i \
		    -e 's|^#\?Storage=.*|Storage=volatile|' \
		    -e 's|^#\?RuntimeMaxUse=.*|RuntimeMaxUse=4M|' \
		    -e 's|^#\?RuntimeMaxFileSize=.*|RuntimeMaxFileSize=1M|' \
		    "${conf}"
	fi
}

do_install:append() {
	yp_systemd_journald_conf
}

# 任务级冒号语法 3.1 也认，不需要再补下划线版（见 yp-service.bbclass 同段注释）。
