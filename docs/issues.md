# 开放问题清单

> 本文件由 `scripts/plan-sync.sh` 从 GitHub Issues 生成，**请勿手改**。
> 想改内容就去改 issue；CI 会校验此文件是否与线上一致。
>
> 生成时共 10 个开放 issue、1 个开放里程碑。

## v1.0.1 · 6.0 全面收口

| Issue | 标题 | 标签 |
|---|---|---|
| [#107](https://github.com/zeek-zhao/yp-distro/issues/107) | chore(compliance): 清除指向重写前 commit 的 PR 引用 | `documentation`, `wave-1` |
| [#127](https://github.com/zeek-zhao/yp-distro/issues/127) | feat(build): 引入 supported-releases 单一事实源，收缩受保障版本 | `enhancement`, `P1`, `build-system` |
| [#128](https://github.com/zeek-zhao/yp-distro/issues/128) | ci: 收缩到 6.0 —— 删四版矩阵、显式 RELEASE 上下文、拉单镜像 | `P1`, `ci`, `build-system` |
| [#129](https://github.com/zeek-zhao/yp-distro/issues/129) | chore(compliance): 只保 SPDX + CVE，拆掉 scancode 分支 | `P1`, `distro`, `build-system` |
| [#130](https://github.com/zeek-zhao/yp-distro/issues/130) | fix(release): DISTRO_VERSION → 1.0.0 且断言改为与最近 tag 动态校验 | `bug`, `P0`, `build-system` |
| [#131](https://github.com/zeek-zhao/yp-distro/issues/131) | feat(test): features.txt 增加证据级别列，99_coverage 加校验 | `P1`, `bats`, `test` |
| [#132](https://github.com/zeek-zhao/yp-distro/issues/132) | feat(test): runtime smoke —— 三层镜像 × 动作集，出 JUnit 与归档 | `P0`, `bats`, `test` |
| [#133](https://github.com/zeek-zhao/yp-distro/issues/133) | feat(security): 只读根 /var overlay —— dm-verity 镜像从「能起机」到「可用」 | `enhancement`, `P1`, `security` |
| [#134](https://github.com/zeek-zhao/yp-distro/issues/134) | docs: 新增 design.md —— 分层、class、配方约定、配置注入点、扩展方式 | `documentation`, `P1`, `docs` |
| [#135](https://github.com/zeek-zhao/yp-distro/issues/135) | docs: 全工程文档同步 —— 三分类 20 份 + features.md 升级 + verification-flow 升级 | `documentation`, `P1`, `docs` |


---

<!-- plan-sync fingerprint: b97f990e12f4ecf4 -->
