# Rust 在 Yocto 中的关键变量是 CARGO_BUILD_FLAGS、CARGO_TARGET_SUBDIR。
# 关键点：离线 vendor + --offline；纯 Rust 静态链接体积数 MB，只进 full 镜像。
SUMMARY = "Minimal offline Rust demo with a systemd service"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://Cargo.toml \
           file://Cargo.lock \
           file://src \
           file://.cargo \
           file://vendor \
           file://yp-demo-rust.service"

S = "${UNPACKDIR}"

inherit cargo yp-service

# 使用项目的 vendored-sources，不让 cargo class 替换成 bitbake 源。
CARGO_DISABLE_BITBAKE_VENDORING = "1"
# cargo class 在 B 中构建，需显式加载 S 中的离线配置。
CARGO_BUILD_FLAGS += "--offline --config ${S}/.cargo/config.toml"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/yp-demo-rust \
        ${D}${bindir}/yp-demo-rust
}
