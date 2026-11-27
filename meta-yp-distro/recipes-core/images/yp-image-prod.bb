# YP-M1-DES-002 / M1-S1: 生产镜像 = core-image-minimal + base 包组（D-04 负向对照）。
# 不装 devtools/kernel-tools，故无 gdbserver/perf/strace/trace-cmd 残留。
SUMMARY = "YP production image without debug tools"
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

IMAGE_INSTALL += "packagegroup-yp-base"

IMAGE_FSTYPES = "ext4"
