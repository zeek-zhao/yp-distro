# 发行版身份的唯一真本。
# 这里曾有第二处：yp-common.inc 里的 0.1.0 —— 两个地方各写一份必然漂移，
# 已合并到本文件。版本号跟仓库最新 tag 走（v1.0.0 = 四版收口发布）；
# 04_layer.bats 的断言保护「版本号与 git tag 一致」，不是某个具体值。
DISTRO_NAME = "YP (Yocto Platform)"
DISTRO_VERSION = "1.0.2"
DISTRO_CODENAME = "yp-product"

# 品牌文案要的 variant 与构建日期。
# 日期用 DATE 而不是实时 date：DATE 在 poky.conf 里已按构建时间生成，
# 且 base-files 的 issue/motd 写入在配方里 vardepsexclude 掉了它，
# 不会把「同一份源码两次构建」判成不同产物。
YP_BRAND_VARIANT = "${YP_VARIANT}"
YP_BRAND_DATE = "${DATE}"
