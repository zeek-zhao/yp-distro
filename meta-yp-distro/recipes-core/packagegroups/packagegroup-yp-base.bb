# YP-M1-DES-002 / M1-S1: 两个镜像共用的最小可用基础命令集。
# 不含任何调试/性能工具——prod 镜像只装本包组（D-04 负向对照）。
SUMMARY = "YP base package group (minimal usable command set)"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:packagegroup-yp-base = "\
    bash \
    coreutils \
    busybox \
    util-linux \
    procps \
    findutils \
    tar \
    gzip \
    "
