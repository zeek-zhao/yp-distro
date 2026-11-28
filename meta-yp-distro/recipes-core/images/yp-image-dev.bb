# YP-M1-DES-002 / M1-S1: 开发镜像 = core-image-minimal + 三个包组。
# D-01 目标镜像层：带 gdbserver/gdb/perf/strace/trace-cmd/quilt 等可运行工具。
# 宿主/eSDK 工具链（devtool 等）由 S2 的 eSDK 提供，不进本 rootfs。
SUMMARY = "YP development image with target-side debug tools"
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL += "\
    packagegroup-yp-base \
    packagegroup-yp-devtools \
    packagegroup-yp-kernel-tools \
    "

# M1-S3 / DES-004: deploy-target 走 scp/ssh，需目标侧 sshd 监听（debug-tweaks 允许空密码 root 登录）。
# gdbserver/gdb 已由 packagegroup-yp-devtools 提供（D-05-a），此处只补 SSH 部署通道（D-03）。
# 三项缺一不可：sshd 监听 22；sftp-server 供宿主 OpenSSH9 scp 的默认 SFTP 子系统；
# scp 供旧协议(-O)/目标侧自检回退。实测 dev 镜像初版只装 sshd 时 scp 报 "Subsystem sftp ... no such file"。
IMAGE_INSTALL += "openssh-sshd openssh-sftp-server openssh-scp"

IMAGE_FSTYPES = "ext4"
