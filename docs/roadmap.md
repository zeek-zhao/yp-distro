# 工程计划（roadmap）

> 与 GitHub 上的 Milestones / Project 看板一一对应。改计划先改这里，再改 Issue。
> 需求真本：Obsidian `40-项目/YP/Yocto-多版本工程需求.md` §7。

- 看板：https://github.com/users/zeek-zhao/projects/4
- 里程碑：`v0.1.0`（P0 基线）→ `v0.2.0`（P1 打通）→ `v1.0.0`（P2 交付能力）

## P0 基线（v0.1.0）

**出口条件**：GHCR 4 镜像免登录可拉、L1 全绿、`project.sh test` 轻量用例可跑。

| # | 项 | 状态 |
|---|---|---|
| [#5](https://github.com/zeek-zhao/yp-distro/issues/5) | config/*.env 四份 + schema 校验 | ✅ `2d313dc` |
| [#6](https://github.com/zeek-zhao/yp-distro/issues/6) | 共享依赖脚本 + 4 份 Dockerfile | ✅ `75e9844` |
| [#7](https://github.com/zeek-zhao/yp-distro/issues/7) | BATS 骨架 + 报告三层 + 指纹 | ✅ `24a6da0` |
| [#8](https://github.com/zeek-zhao/yp-distro/issues/8) | L1 lint + L2 images + pull-check | ✅ `0d7ea70` |
| [#2](https://github.com/zeek-zhao/yp-distro/issues/2) | main 分支并挂默认 | ✅ |
| [#4](https://github.com/zeek-zhao/yp-distro/issues/4) | 分支模型（dev 集成 + PR 门禁） | ✅ `9140c2e` |
| [#9](https://github.com/zeek-zhao/yp-distro/issues/9) | project.sh 子命令补齐 | ✅ `9ceffdc`（10 子命令 + 5 占位 exit 2；Makefile 全 target 一行转发；`docs/cli.md`；BATS 56） |
| [#10](https://github.com/zeek-zhao/yp-distro/issues/10) | scripts/container.sh（命名/非 root/UID 映射） | ✅ `d9ed12e`（容器名 `yocto-<r>-<v>`、uid 映射 + `/etc/passwd` 注入、DL/SSTATE 落 `/work/work/`、85% 水位门禁、`--check`/`--dry-run`） |
| [#14](https://github.com/zeek-zhao/yp-distro/issues/14) | **bug**：镜像缺 kas / repo | ✅ `984e915`（kas 4.6；repo 默认不装，留 `INSTALL_REPO=1`） |
| [#15](https://github.com/zeek-zhao/yp-distro/issues/15) | **bug**：镜像构建用户不一致 | ✅ `984e915`（统一 `builder`，4 镜像 `id -un` 唯一） |
| [#11](https://github.com/zeek-zhao/yp-distro/issues/11) | meta-yp layer 升级（4 版兼容） | ✅ `eb79142`（LAYERSERIES 四值、`yp.conf`+`yp-common/yp-compat.inc`、`yp-image`/`yp-image-minimal`、全层禁冒号 override；BATS 68） |
| [#12](https://github.com/zeek-zhao/yp-distro/issues/12) | ~~source.sh~~ / [#13](https://github.com/zeek-zhao/yp-distro/issues/13) ~~worktree~~ | ⛔ 被 kas 取代（C40） |

**依赖顺序**：#10 → #9 → #11 —— **四项全部完成，P0 关闭**。#14/#15 已修；kas 层 #17 转 P1 首卡。

## P1 打通（v0.2.0）

**出口条件**：每版本 × 每 variant 一次真实构建 + QEMU 通过，报告归档。

| # | 项 | 依赖 |
|---|---|---|
| [#17](https://github.com/zeek-zhao/yp-distro/issues/17) | kas 层落地（15 个 yml + lockfile） | #14 |
| [#18](https://github.com/zeek-zhao/yp-distro/issues/18) | wrynose 全链路实跑 | #14 #17 |
| [#19](https://github.com/zeek-zhao/yp-distro/issues/19) | scarthgap 全链路实跑 | #18 |
| [#20](https://github.com/zeek-zhao/yp-distro/issues/20) | kirkstone 全链路实跑 | #19 |
| [#21](https://github.com/zeek-zhao/yp-distro/issues/21) | dunfell 全链路实跑 | #20 |
| [#22](https://github.com/zeek-zhao/yp-distro/issues/22) | general / custom 独立 distro 双 variant | #11 #18 |
| [#23](https://github.com/zeek-zhao/yp-distro/issues/23) | 缓存策略（DL_DIR / sstate + 文件锁） | #10 #22 |

实跑顺序固定为 **wrynose → scarthgap → kirkstone → dunfell**（C34：先跑构建机上已验证的 wrynose 拿第一份报告，风险后置）。

## P2 交付能力（v1.0.0）

| # | 项 |
|---|---|
| [#25](https://github.com/zeek-zhao/yp-distro/issues/25) | SDK / eSDK 产出 |
| [#26](https://github.com/zeek-zhao/yp-distro/issues/26) | 合规：SPDX / FOSS / CVE 跨版本 |
| [#27](https://github.com/zeek-zhao/yp-distro/issues/27) | arm64 machine 维度（scarthgap/wrynose） |
| [#28](https://github.com/zeek-zhao/yp-distro/issues/28) | recipe 内 do_scancode 定案（C26） |

## 未决问题（question）

| # | 问题 | 影响 |
|---|---|---|
| [#16](https://github.com/zeek-zhao/yp-distro/issues/16) | 构建机磁盘余量与 docker 镜像回收边界 | 188GB 可回收镜像属其他 Jenkins 任务，不能 `prune -a`；`DL_DIR` 落点必须显式 |
| [#24](https://github.com/zeek-zhao/yp-distro/issues/24) | wrynose 三仓库拆分在 kas 的 layers 表达未验证 | 214 上无多版本实践可参考，需构建机实测 `kas dump` |
| [#28](https://github.com/zeek-zhao/yp-distro/issues/28) | do_scancode 是否值得进构建期 | 可能让每个 recipe 的构建时间翻倍 |

## 阶段收口动作

1. 该里程碑下开放的 Issue 清零；
2. `dev` → `main` 一个 PR（描述里贴验收结论）；
3. 打 tag `vX.Y.Z`；
4. 更新本文件与 Obsidian 交接单。
