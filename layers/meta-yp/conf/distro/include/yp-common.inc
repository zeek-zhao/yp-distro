# 版本与代号已移到 include/yp-release.inc（单一真本）。
MAINTAINER = "YP maintainers"

# QEMU 无图形/蜂窝/蓝牙/NFS/服务发现需求。
# 只用冒号语法：`DISTRO_FEATURES_remove`（下划线）在 4.0+ 是**致命解析错误**
# （bitbake: "contains an operation using the old override syntax"），
# 不是可叠加的冗余保险 —— 实测在 wrynose 上直接 Unable to parse。
# 3.1 只认下划线，走单独的 conf（见 yp-dunfell.conf），不能塞进本文件。
DISTRO_FEATURES:remove = "x11 wayland opengl 3g bluetooth nfs zeroconf ptest"

# BitBake 6.x rejects even inactive legacy _remove assignments, so set it only on 3.1.
python __anonymous () {
    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("DISTRO_FEATURES_remove", "x11 wayland opengl 3g bluetooth nfs zeroconf ptest")
}

# Future DISTRO_FEATURES additions belong here and must use +=.

# ---- 运行时配套（#59）----
# locale 只留 C.UTF-8。poky 默认生成一长串，镜像里九成用不到，
# 而 `locale -a` 的输出长度会让「这是不是我的发行版」变成猜谜。
# 只动 GLIBC_GENERATE_LOCALES，不动 IMAGE_LINGUAS：后者决定 locale-base-* 分包，
# 置空会让 gawk/tcl8/bash 的 -ptest 子包 rdepends 落空，do_package_qa 直接判
# build-deps 致命错误（实测）。前者只控制 libc-package 生成哪些 locale 数据，
# 足以让 locale -a 收敛到 C / C.utf8 / POSIX。
GLIBC_GENERATE_LOCALES = "C.UTF-8"

# 时区固定 UTC：日志时间戳与宿主对得上，跨机器比对串口日志时不用换算。
# 写 UTC 而不是 Etc/UTC —— 两者等价，但验收脚本 grep 的是 UTC。
DEFAULT_TIMEZONE = "UTC"

# ---- 远端登录面（#59）----
# 默认 dropbear：core-image-minimal 的 packagegroup 已经按 VIRTUAL-RUNTIME_ssh
# 装它，换 openssh 必须同时排掉 packagegroup-core-ssh-dropbear，否则 rpm 直接
# 报 package conflicts —— 所以不做自动切换，只把这个前置条件写在这里。
# 想换：YP_SSH=openssh-sshd，并在镜像里去掉 ssh-server-dropbear。
YP_SSH ??= "dropbear"
VIRTUAL-RUNTIME_ssh = "${YP_SSH}"

# ---- systemd 启动精简（#73）----
# runqemu 的串口布局是 `-serial mon:stdio -serial null`：ttyS0 接打点/登录链路，
# ttyS1 是 null 设备，永远不会有输入。但 serial-getty@ttyS1.service 默认 enabled，
# 且它等的是 dev-ttyS1.device —— 实测 dev-ttyS1.device @8.406s 是 multi-user
# 关键链上最后一个激活项（systemd-analyze critical-chain，见
# docs/qa/boot-baseline.md 第 7 节）。等一个没人用的串口，纯浪费。
# mask（/dev/null 链接）而不是删除文件：unit 文件属于 systemd 包，删了会在
# do_rootfs 后的 systemd 校验里丢属主；mask 是 systemd 官方语义。
# 6.0 已实测；其余版本的关键链未测，不盲推（#83 起 5.0 对齐时单独验证）。
python __anonymous () {
    if "wrynose" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("YP_MASKED_UNITS", "serial-getty@ttyS1.service")
}

YP_MASK_UNITS() {
    for u in ${YP_MASKED_UNITS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${systemd_system_unitdir}/$u
    done
}
ROOTFS_POSTPROCESS_COMMAND:append = " YP_MASK_UNITS;"
