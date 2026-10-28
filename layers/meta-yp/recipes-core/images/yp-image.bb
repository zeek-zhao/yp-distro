SUMMARY = "YP reference image"
require recipes-core/images/core-image-minimal.bb
IMAGE_INSTALL += " virtual/cpp-hello"

# CVE 检查只在 custom variant 打开（YP_CVE_ENABLE=1）。
# 类名按 release 不同：dunfell/kirkstone/scarthgap 用 cve-check，
# wrynose 已把它换成 sbom-cve-check，所以不能在这里写死。
inherit ${@bb.utils.contains('YP_CVE_ENABLE', '1', d.getVar('YP_CVE_CLASS'), '', d)}
