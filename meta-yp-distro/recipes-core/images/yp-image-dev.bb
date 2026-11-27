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

IMAGE_FSTYPES = "ext4"
