# 上游 os-release 只输出 ID/NAME/VERSION/VERSION_ID/VERSION_CODENAME 等标准字段。
# BUILD_VARIANT 是本项目要的：同一个 6.0 有 general / custom 两种 variant，
# 启动时间与镜像体积的对比要能对上号，不能只靠目录名猜。
BUILD_VARIANT = "${YP_BRAND_VARIANT}"
OS_RELEASE_FIELDS:append = " BUILD_VARIANT"

# 3.1 不认冒号 override，且 `_append` 下划线版在 4.0+ 是致命解析错误，
# 不能双写兜底 → 3.1 的追加只能用 python 补（同 yp-common.inc 手法）。
python __anonymous() {
    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("OS_RELEASE_FIELDS_append", " BUILD_VARIANT")
}
