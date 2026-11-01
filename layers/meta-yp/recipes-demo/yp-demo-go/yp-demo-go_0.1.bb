# Go 的关键变量是 GO_IMPORT；go-mod + GOSUMDB=off + vendor + -trimpath
# 分别提供模块构建、禁用联网校验、离线依赖和移除宿主路径。
SUMMARY = "Minimal Go module demo with a systemd service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit go-mod yp-service

GO_IMPORT = "example.com/yp/demo"
SRC_URI = "file://go.mod;subdir=src/${GO_IMPORT} \
           file://main.go;subdir=src/${GO_IMPORT} \
           file://vendor;subdir=src/${GO_IMPORT} \
           file://yp-demo-go.service"
S = "${YP_SRC_DIR}"

export GOSUMDB = "off"
export GOPROXY = "off"
GOBUILDFLAGS:append = " -mod=vendor -trimpath"

# 3.1 不认冒号 override；`_append` 下划线版在 4.0+ 是致命解析错误，不能双写。
# 漏了这句在 3.1 上就是 go 缺 -mod=vendor：GOPROXY=off 已断网，构建直接失败。
python __anonymous() {
    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("GOBUILDFLAGS_append", " -mod=vendor -trimpath")
}
GO_INSTALL = "${GO_IMPORT}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/${GO_BUILD_BINDIR}/demo ${D}${bindir}/yp-demo-go
}
