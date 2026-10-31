DISTRO_VERSION = "0.1.0"
DISTRO_CODENAME = "yp-phase0"
MAINTAINER = "YP maintainers"

# QEMU 无图形/蜂窝/蓝牙/NFS/服务发现需求。
# 只用冒号语法：`DISTRO_FEATURES_remove`（下划线）在 4.0+ 是**致命解析错误**
# （bitbake: "contains an operation using the old override syntax"），
# 不是可叠加的冗余保险 —— 实测在 wrynose 上直接 Unable to parse。
# 3.1 只认下划线，走单独的 conf（见 yp-dunfell.conf），不能塞进本文件。
DISTRO_FEATURES:remove = "x11 wayland opengl 3g bluetooth nfs zeroconf"

# BitBake 6.x rejects even inactive legacy _remove assignments, so set it only on 3.1.
python __anonymous () {
    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("DISTRO_FEATURES_remove", "x11 wayland opengl 3g bluetooth nfs zeroconf")
}

# Future DISTRO_FEATURES additions belong here and must use +=.
