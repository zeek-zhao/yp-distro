# 开放问题清单

> 本文件由 `scripts/plan-sync.sh` 从 GitHub Issues 生成，**请勿手改**。
> 想改内容就去改 issue；CI 会校验此文件是否与线上一致。
>
> 生成时共 14 个开放 issue、4 个开放里程碑。

## v1.0.0 · 四版收口

| Issue | 标题 | 标签 |
|---|---|---|
| [#85](https://github.com/zeek-zhao/yp-distro/issues/85) | chore(release): 四版全兼容回归与报告归档 | `ci`, `P3` |
| [#86](https://github.com/zeek-zhao/yp-distro/issues/86) | docs(release): 文档收口与发布 | `docs`, `P3` |
| [#87](https://github.com/zeek-zhao/yp-distro/issues/87) | chore(sdk): SDK / eSDK 恢复评估（源自 #25） | `docs`, `P3` |

## v0.5.0 · 6.0 启动优化

| Issue | 标题 | 标签 |
|---|---|---|
| [#72](https://github.com/zeek-zhao/yp-distro/issues/72) | perf(kernel): 内核裁剪 —— cfg fragment + 压缩算法 + 关调试输出 | `enhancement`, `P3`, `boot-time` |
| [#73](https://github.com/zeek-zhao/yp-distro/issues/73) | perf(boot): systemd 启动精简 —— unit 裁剪 / critical-chain / udev 收敛 | `enhancement`, `P3`, `boot-time` |
| [#74](https://github.com/zeek-zhao/yp-distro/issues/74) | perf(rootfs): ext4 vs squashfs+overlay vs cpio 的加载时间对比 | `enhancement`, `P3`, `boot-time` |
| [#75](https://github.com/zeek-zhao/yp-distro/issues/75) | docs(boot): 启动优化对比报告 —— 每项措施的收益与代价 | `docs`, `P3`, `boot-time` |

## v0.6.0 · 6.0 服务与 demo

| Issue | 标题 | 标签 |
|---|---|---|
| [#78](https://github.com/zeek-zhao/yp-distro/issues/78) | perf(demo): 服务数量 × 启动耗时评估 | `P3`, `boot-time`, `demo` |

## v0.7.0 · 5.0 对齐与四版补齐

| Issue | 标题 | 标签 |
|---|---|---|
| [#80](https://github.com/zeek-zhao/yp-distro/issues/80) | feat(scarthgap): 5.0 发行版对齐 —— 裁特性 / 品牌化 / 三层镜像 / 运行时 | `enhancement`, `P3`, `distro` |
| [#81](https://github.com/zeek-zhao/yp-distro/issues/81) | feat(scarthgap): 5.0 U-Boot 与启动时间基线 | `enhancement`, `P3`, `boot-time` |
| [#82](https://github.com/zeek-zhao/yp-distro/issues/82) | feat(scarthgap): 5.0 语法组七配方验证 | `enhancement`, `P3`, `build-system` |
| [#83](https://github.com/zeek-zhao/yp-distro/issues/83) | feat(scarthgap): 5.0 服务与 demo 落地 | `enhancement`, `P3`, `demo` |
| [#84](https://github.com/zeek-zhao/yp-distro/issues/84) | docs(syntax): 四版语法对照补齐（3.1/4.0 配方能编） | `bats`, `P3`, `build-system` |

## 未归入里程碑

| Issue | 标题 | 标签 |
|---|---|---|
| [#107](https://github.com/zeek-zhao/yp-distro/issues/107) | chore(compliance): 清除指向重写前 commit 的 PR 引用 | `documentation` |
