# YP 服务模板：只产出 .service，不提供 /etc/init.d 兼容路径。
#
# 为什么不给 init 脚本留退路：6.0 的 VIRTUAL-RUNTIME_initscripts 是空串，
# 没有 systemd-compat-units，老式 init 脚本在这个版本上根本不会运行；
# 3.1~5.0 虽然能靠 systemd-sysv-generator 接管，但那些服务排不进
# systemd-analyze 的关键路径，启动时间就没法按段归因。四版统一 unit 才一致。
inherit systemd

YP_SERVICE_NAME ?= "${PN}"
YP_SERVICE_UNIT ?= "${YP_SERVICE_NAME}.service"

# 注册必须走 systemd.bbclass：它在 do_rootfs 阶段用 `systemctl --root=${D} enable`
# 处理离线 rootfs，手写不带 --root 的 systemctl enable 会作用到构建宿主、
# 或者在 rootfs 阶段静默失败。
SYSTEMD_SERVICE:${PN} = "${YP_SERVICE_UNIT}"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# 3.1 只认下划线语法，4.0+ 只认冒号语法。两行都写，未命中的那行是惰性变量。
# （包名不会撞上 bitbake 的已知 override 名，所以不会触发 4.0+ 的 old-syntax 报错。）
SYSTEMD_SERVICE_${PN} = "${YP_SERVICE_UNIT}"
SYSTEMD_AUTO_ENABLE_${PN} = "enable"

# file:// 的落点各版本不同：6.0 解到 UNPACKDIR（${WORKDIR}/sources），
# 3.1~5.0 直接解到 WORKDIR。??= 让 recipe 侧可以覆盖。
YP_SRC_DIR ?= "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"

do_install:append() {
	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${YP_SRC_DIR}/${YP_SERVICE_UNIT} \
	    ${D}${systemd_system_unitdir}/${YP_SERVICE_UNIT}
}
