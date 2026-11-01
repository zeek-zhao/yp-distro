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
S = "${UNPACKDIR}"

export GOSUMDB = "off"
export GOPROXY = "off"
GOBUILDFLAGS:append = " -mod=vendor -trimpath"
GO_INSTALL = "${GO_IMPORT}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/${GO_BUILD_BINDIR}/demo ${D}${bindir}/yp-demo-go
}
