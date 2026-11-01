# 离线 vendor

本 demo 仅使用 Rust 标准库，没有第三方 crate，`cargo vendor` 因此没有
crate 源码可导出。保留此目录供 `.cargo/config.toml` 的离线源替换使用；
不需要在构建机下载依赖。

以后添加依赖时，在可联网的开发机上更新 `Cargo.lock`，然后从项目目录运行
`cargo vendor --locked vendor`，提交完整 vendor 源码（包括
`.cargo-checksum.json`）。保持现有 source replacement 配置，并用空的
`CARGO_HOME` 执行 `cargo build --offline --frozen --release` 验证。

无依赖时 `cargo vendor` 会清空此目录；重新运行后需恢复本说明文件。
