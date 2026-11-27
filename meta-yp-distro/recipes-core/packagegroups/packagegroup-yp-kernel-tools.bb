# YP-M1-DES-002 / M1-S1: 目标侧性能/追踪工具（D-01 目标镜像层）。
# trace-cmd 来自 meta-openembedded/meta-oe（base.yml 已加载该层）。
SUMMARY = "YP target-side kernel tracing tools package group"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:packagegroup-yp-kernel-tools = "\
    perf \
    trace-cmd \
    "
