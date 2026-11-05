# 里程碑与出口条件

> 工程计划的**单一真源**是 GitHub Milestones；本文件记录每个里程碑的**出口条件**
> （「什么叫做完」），因为 issue 列表本身不表达这一点。
>
> 最后更新：2026-11-03（v0.5~v0.7 出口条件达成，随 PR #113 合并生效）

## 总览

| 里程碑 | 主题 | 状态 | 出口条件摘要 |
|---|---|---|---|
| v0.1.0 | 基线 | 已关闭 | 配置骨架 + 容器镜像 + 报告链 |
| v0.2.0 | 打通 | 已关闭 | kas 分层 + 四发行版解析 + 自定义 local repo |
| v0.3.0 | U-Boot 启动链 + systemd 收口 | 已关闭 | 镜像能起，`init` 管理器可切换 |
| v0.4.0 | 6.0 语法组 | 已关闭 | 六构建系统配方真构建 + 装进 full 镜像 + 语法对照表 |
| v0.5.0 | 启动优化 | 出口条件达成（待合并） | 四项优化各有测量数据与成本说明 |
| v0.6.0 | 服务与 demo | 出口条件达成（待合并） | 服务可起 + 采集可见 + 服务数×耗时曲线 |
| v0.7.0 | 5.0 对齐与四版补齐 | 出口条件达成（待合并） | scarthgap 与 wrynose 能力对齐 |
| v1.0.0 | 四版收口 | 开放（回归 8/8，剩 #85 归档） | 四发行版全量回归 + 文档收口 + SDK 结论 |

## v0.4.0 · 6.0 语法组（已关闭）

**出口条件**

- [x] make / cmake / autotools / meson / Python3(PEP517) / Rust(cargo 离线) / Go(go-mod) 七种语法各有配方
- [x] 每配方在构建机上真构建通过（`2184 tasks all succeeded`）
- [x] 九个包进 `yp-image.bb` 的 `IMAGE_INSTALL`（仅 full 层）
- [x] full 镜像真起机，`/status` 与 `journalctl` 均有输出
- [x] `docs/syntax-matrix.md` 首版 + `15_syntax.bats` 覆盖关键差异

**留下的教训**（写进本文件是因为下次还会踩）

1. `file://` 的源只能放 `${BP}` / `${BPN}` / `files/`——放配方目录根部解析期就 halt
2. 字符串宏不要在配方里拼引号，责任下移到 Makefile（单引号包双引号）
3. 「配方能 parse」≠「配方能 build」，只有 L3 能暴露这类问题

## v0.5.0 · 启动优化（出口条件达成，随 PR #113 合并生效）

**前置**：~~#110~~ 已修（PR #113，2026-11-03）—— 根因不在打点管道（`tee >(monitor_stream)`
实测是通的），而是 `set -e` 恢复后 `kill writer_pid` 打在已退走的 writer 上，测量链在
写 json 之前静默 exit 1。三段打点链路恢复可用，`boot-baseline.md` 可以填数了。

**出口条件**——四项都要有「收益 + 代价」，不能只报收益：

- [x] #72 内核裁剪：cfg fragment + 压缩算法 + 关调试输出，给出内核体积与启动阶段耗时（boot-baseline §6；已移植 5.0/4.0，§10）
- [x] #73 systemd 精简：unit 裁剪 + `critical-chain` 分析，给出去掉了什么、为什么安全（boot-baseline §7；ttyS1 mask 已移植 5.0/4.0）
- [x] #74 rootfs 格式：ext4 vs squashfs+overlay vs cpio 的加载时间对比（boot-baseline §8，维持 ext4）
- [x] #75 对比报告：每项措施的收益与代价，**含回退成本**（docs/boot-optimization.md）

> ⚠️ #72/#73/#74 是同一组实验的三个变量。**单独做任何一个都推不出「收益与代价」**，
> 必须固定其余变量、串行测量。

## v0.6.0 · 服务与 demo（出口条件达成，随 PR #113 合并生效）

**出口条件**

- [x] #76 `yp-statusd`：C 实现 HTTP `/status`，读 procfs
- [x] #77 `yp-collectd`：采集写 journald（**不用 logrotate**）
- [x] #79 `docs/adding-a-service.md`：六节教程
- [x] #78 服务数量 × 启动耗时曲线（docs/boot-optimization.md 第三节）

## v0.7.0 · 5.0 对齐与四版补齐（出口条件达成，随 PR #113 合并生效）

**前置**：scarthgap 首次构建通过。**在此之前 #80–#84 并行等于五个一起卡住。**

- [x] #80 发行版对齐：裁特性 / 品牌化 / 三层镜像 / 运行时
- [x] #81 U-Boot 与启动时间基线（QFW 链 5.0 不可用，按预设降级，degraded.txt 登记）
- [x] #82 语法组七配方验证
- [x] #83 服务与 demo 落地
- [x] #84 四版语法对照补齐（3.1 / 4.0 配方能编；3.1/4.0 冻结口径只求能编，4.0 内核优化随移植到位）

## v1.0.0 · 四版收口（开放，剩 #85）

| issue | 内容 | 状态 |
|---|---|---|
| #85 | 四版全兼容回归与报告归档 | 8/8 已恢复（2026-11-03），待全量回归与归档 |
| #86 | 文档收口与发布 | ✅ 见 [#86 结案评论](https://github.com/zeek-zhao/yp-distro/issues/86#issuecomment-6559294429) |
| #87 | SDK / eSDK 恢复评估 | ✅ 结论见 [`docs/sdk.md`](../sdk.md) §8 |
| #109 | dunfell full 镜像 `do_rootfs` 目录属性冲突 | ✅ 根因是 11-01 实验期遗留 rpm 的 0700 目录污染（含 python3 全系），配方无罪；重建后全绿，见 [issue 结案讨论](https://github.com/zeek-zhao/yp-distro/issues/109#issuecomment-6583071229) |

**#85 的实测口径**（`f66f35b`，2026-11-01）

| release | general | custom |
|---|---|---|
| wrynose 6.0 | ✅ 194/194/0/0 | ✅ 194/194/0/0 |
| scarthgap 5.0 | ✅ 194/194/0/0 | ✅ 194/194/0/0 |
| kirkstone 4.0 | ✅ 194/194/0/0 | ✅ 194/194/0/0 |
| dunfell 3.1 | ✅ 194/194/0/0 | ❌ `do_rootfs` 失败（#109，当时） |

七份归档在 `docs/qa/{wrynose,scarthgap,kirkstone,dunfell}/20261101-f66f35b*.md`，
每份同目录附 `artifacts-*.sha256`。dunfell custom 已于 2026-11-03 重建恢复
（2944 tasks 全绿 + `boot-exec` 起机取证），#85 收口时补一份 8/8 的回归归档即可。

> 注意：「四版全绿」不等于「每一版都跑过 full 镜像起机」。dunfell general 的
> `core-image-minimal` 能起能测，full 层在 2026-11-03 之前从未真正装成过
> （见上表与 #109）——本次重建后已补上起机取证。

## 收口动作（每次发版照做）

1. 开 PR 合入 `main`（`branch-guard` 与 ruleset 都只认 PR 合并）
2. 在 `main` 上打 **annotated tag**，tagger 必须是 `zeek.zhao <zeek.zhao@foxmail.com>`
3. 建 GitHub Release，页内引用 `docs/qa/` 对应归档
4. 关里程碑，把本文件的出口条件逐条勾上
