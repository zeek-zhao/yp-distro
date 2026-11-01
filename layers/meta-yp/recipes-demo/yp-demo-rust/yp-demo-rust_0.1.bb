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

S = "${YP_SRC_DIR}"

inherit cargo yp-service

# 使用项目的 vendored-sources，不让 cargo class 替换成 bitbake 源。
CARGO_DISABLE_BITBAKE_VENDORING = "1"

# 只加 --offline，不要用 `--config <file>`：那个开关 cargo 1.63 才稳定，
# kirkstone(4.0) 自带的 cargo 1.59 直接拒绝
# （"the --config flag is unstable, pass -Z unstable-options"），而 1.59 的
# stable 通道根本不接受 -Z。改成把配置放进 ${B}/.cargo/config.toml：cargo
# class 在 ${B} 里执行编译，cargo 会从 CWD 逐级向上找 .cargo/config.toml。
CARGO_BUILD_FLAGS += "--offline"

do_compile:prepend() {
    install -d ${B}/.cargo
    # `directory` 相对「.cargo 的父目录」解析：原样抄过去会指向 ${B}/vendor
    # （不存在），必须换成 ${S}/vendor 的绝对路径。
    # 这段 prepend 不需要给 3.1 补 python 版 —— dunfell 上本配方被 BBMASK 掉了。
    sed "s|^directory = \"vendor\"$|directory = \"${S}/vendor\"|" \
        ${S}/.cargo/config.toml > ${B}/.cargo/config.toml
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/yp-demo-rust \
        ${D}${bindir}/yp-demo-rust
}
