SUMMARY = "YP base image —— 能日常用的最小集合"
DESCRIPTION = "minimal + 日常运维工具，不含业务与调试器。用于测量\
「装上工具之后慢多少」，也是将来对接真实设备的起点。"

require recipes-core/images/core-image-minimal.bb
include yp-image.inc
include yp-image-runtime.inc
