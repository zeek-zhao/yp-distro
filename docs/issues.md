# 开放问题清单

> 本文件由 `scripts/plan-sync.sh` 从 GitHub Issues 生成，**请勿手改**。
> 想改内容就去改 issue；CI 会校验此文件是否与线上一致。
>
> 生成时共 17 个开放 issue、4 个开放里程碑。

## v1.0.0 · 四版收口

| Issue | 标题 | 标签 |
|---|---|---|
| [#85](https://github.com/zeek-zhao/yp-distro/issues/85) | chore(release): 四版全兼容回归与报告归档 | `ci`, `P3`, `wave-1` |
| [#109](https://github.com/zeek-zhao/yp-distro/issues/109) | fix(dunfell): full 镜像 do_rootfs 目录属性冲突（7/8 组合的唯一阻塞项） | `bug`, `P1` |

## v0.5.0 · 6.0 启动优化

| Issue | 标题 | 标签 |
|---|---|---|
| [#72](https://github.com/zeek-zhao/yp-distro/issues/72) | perf(kernel): 内核裁剪 —— cfg fragment + 压缩算法 + 关调试输出 | `enhancement`, `P3`, `boot-time`, `wave-2` |
| [#73](https://github.com/zeek-zhao/yp-distro/issues/73) | perf(boot): systemd 启动精简 —— unit 裁剪 / critical-chain / udev 收敛 | `enhancement`, `P3`, `boot-time`, `wave-2` |
| [#74](https://github.com/zeek-zhao/yp-distro/issues/74) | perf(rootfs): ext4 vs squashfs+overlay vs cpio 的加载时间对比 | `enhancement`, `P3`, `boot-time`, `wave-2` |
| [#75](https://github.com/zeek-zhao/yp-distro/issues/75) | docs(boot): 启动优化对比报告 —— 每项措施的收益与代价 | `docs`, `P3`, `boot-time`, `wave-2` |
| [#110](https://github.com/zeek-zhao/yp-distro/issues/110) | fix(boot-time): 真实起机模式拿不到 login 打点（基线测不出来） | `bug`, `P2` |

## v0.6.0 · 6.0 服务与 demo

| Issue | 标题 | 标签 |
|---|---|---|
| [#78](https://github.com/zeek-zhao/yp-distro/issues/78) | perf(demo): 服务数量 × 启动耗时评估 | `P3`, `boot-time`, `demo`, `wave-2` |

## v0.7.0 · 5.0 对齐与四版补齐

| Issue | 标题 | 标签 |
|---|---|---|
| [#80](https://github.com/zeek-zhao/yp-distro/issues/80) | feat(scarthgap): 5.0 发行版对齐 —— 裁特性 / 品牌化 / 三层镜像 / 运行时 | `enhancement`, `P3`, `distro`, `wave-3` |
| [#81](https://github.com/zeek-zhao/yp-distro/issues/81) | feat(scarthgap): 5.0 U-Boot 与启动时间基线 | `enhancement`, `P3`, `boot-time`, `wave-3` |
| [#82](https://github.com/zeek-zhao/yp-distro/issues/82) | feat(scarthgap): 5.0 语法组七配方验证 | `enhancement`, `P3`, `build-system`, `wave-3` |
| [#83](https://github.com/zeek-zhao/yp-distro/issues/83) | feat(scarthgap): 5.0 服务与 demo 落地 | `enhancement`, `P3`, `demo`, `wave-3` |
| [#84](https://github.com/zeek-zhao/yp-distro/issues/84) | docs(syntax): 四版语法对照补齐（3.1/4.0 配方能编） | `bats`, `P3`, `build-system`, `wave-3` |

## 未归入里程碑

| Issue | 标题 | 标签 |
|---|---|---|
| [#107](https://github.com/zeek-zhao/yp-distro/issues/107) | chore(compliance): 清除指向重写前 commit 的 PR 引用 | `documentation`, `wave-1` |
| [#114](https://github.com/zeek-zhao/yp-distro/issues/114) | chore(build): deploy 产物新鲜度防呆 —— 指纹戳 + guard 快速失败 | `P2`, `build-system` |
| [#115](https://github.com/zeek-zhao/yp-distro/issues/115) | chore(release): LTS 点版本跟进流程 —— release-check.sh + 流程文档 | `P2`, `build-system` |
| [#116](https://github.com/zeek-zhao/yp-distro/issues/116) | feat(security): dm-verity 只读根可行性验证（CRA secure defaults 第一步） | `enhancement`, `P3`, `security` |


---

<!-- plan-sync fingerprint: 48eb159e204b806f -->
