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

yp_service_install_unit() {
	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${YP_SRC_DIR}/${YP_SERVICE_UNIT} \
	    ${D}${systemd_system_unitdir}/${YP_SERVICE_UNIT}
}

do_install:append() {
	yp_service_install_unit
}

# 任务级的冒号语法 3.1 也认（实测 3.1.33：只留这一份 `do_install:append()`，
# dunfell 上生成的 do_install 里确实带上了 yp_service_install_unit）。不认冒号
# 的是**变量**赋值（`IMAGE_INSTALL:append` 那一类，见 images/yp-image.inc 里的
# python 补丁）——两者别混为一谈。
#
# 所以这里只留冒号一份，绝不并列写 `do_install_append() {}`：4.0+ 会把那个变量名
# 判成 "old override syntax" 直接 fatal，而报错会挂到所有求值到同名变量的 recipe
# 上（实测连上游 base-files / systemd 一起红）。
#
# 也别改成「独立任务 + addtask」：自定义任务不在 PSEUDO_TASKS 里，不经 pseudo，
# 装出来的 unit 属主是真实宿主 uid，do_package_qa 立刻判 host-user-contaminated。
# 必须挂在 do_install 上，才能借到 pseudo 的 fake root。
