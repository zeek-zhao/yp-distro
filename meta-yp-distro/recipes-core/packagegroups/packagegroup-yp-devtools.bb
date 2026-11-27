# YP-M1-DES-002 / M1-S1: 目标侧可运行的开发/调试工具（D-01 目标镜像层）。
# gdbserver 是 gdb_17.2.bb 显式切出的 package（PACKAGES =+ "gdbserver"），单独列出。
# 不塞 devtool/recipetool/devshell/qemu/qemu-user 等宿主/eSDK 工具（归 S2）。
SUMMARY = "YP target-side developer tools package group"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:packagegroup-yp-devtools = "\
    gdb \
    gdbserver \
    strace \
    quilt \
    "
