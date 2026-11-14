# 里程碑与出口条件

> 工程计划的**单一真源**是 GitHub Milestones；本文件记录每个里程碑的**出口条件**
> （「什么叫做完」），因为 issue 列表本身不表达这一点。
>
> 最后更新：2026-11-12（#138 batch1 合并：#130/#127/#128/#129/#132/#131/#134 全关；#135 文档同步进行中）

## 总览

| 里程碑 | 主题 | 状态 | 出口条件摘要 |
|---|---|---|---|
| v0.1.0 | 基线 | 已关闭 | 配置骨架 + 容器镜像 + 报告链 |
| v0.2.0 | 打通 | 已关闭 | kas 分层 + 四发行版解析 + 自定义 local repo |
| v0.3.0 | U-Boot 启动链 + systemd 收口 | 已关闭 | 镜像能起，`init` 管理器可切换 |
| v0.4.0 | 6.0 语法组 | 已关闭 | 六构建系统配方真构建 + 装进 full 镜像 + 语法对照表 |
| v0.5.0 | 启动优化 | 已关闭（随 v1.0.0 累积发布） | 四项优化各有测量数据与成本说明 |
| v0.6.0 | 服务与 demo | 已关闭（随 v1.0.0 累积发布） | 服务可起 + 采集可见 + 服务数×耗时曲线 |
| v0.7.0 | 5.0 对齐与四版补齐 | 已关闭（随 v1.0.0 累积发布） | scarthgap 与 wrynose 能力对齐 |
| v1.0.0 | 四版收口 | 已关闭（2026-11-05，`1e1ff48`） | 四发行版全量回归 + 文档收口 + SDK 结论 |
| **v1.0.1 · 6.0 全面收口** | **6.0 单版深度收口** | **开放**（batch1 = #138 已合并 2026-11-12；余 #135 文档同步与点版本） | 26 条功能各达证据档位 + DoD 五条 |

## v0.4.0 · 6.0 语法组（已关闭）

**出口条件**

- [x] make / cmake / autotools / meson / Python3(PEP517) / Rust(cargo 离线) / Go(go-mod) 七种语法各有配方
- [x] 每配方在构建机上真构建通过（`2184 tasks all succeeded`）
- [x] 九个包进 `yp-image.bb` 的 `IMAGE_INSTALL`（仅 full 层）
- [x] full 镜像真起机，`/status` 与 `journalctl` 均有输出
- [x] `docs/02-development/syntax-matrix.md` 首版 + `15_syntax.bats` 覆盖关键差异

**留下的教训**（写进本文件是因为下次还会踩）

1. `file://` 的源只能放 `${BP}` / `${BPN}` / `files/`——放配方目录根部解析期就 halt
2. 字符串宏不要在配方里拼引号，责任下移到 Makefile（单引号包双引号）
3. 「配方能 parse」≠「配方能 build」，只有 L3 能暴露这类问题

## v0.5.0 · 启动优化（已随 v1.0.0 累积发布）

**前置**：~~#110~~ 已修（PR #113，2026-11-03）—— 根因不在打点管道（`tee >(monitor_stream)`
实测是通的），而是 `set -e` 恢复后 `kill writer_pid` 打在已退走的 writer 上，测量链在
写 json 之前静默 exit 1。三段打点链路恢复可用，`boot-baseline.md` 可以填数了。

**出口条件**——四项都要有「收益 + 代价」，不能只报收益：

- [x] #72 内核裁剪：cfg fragment + 压缩算法 + 关调试输出，给出内核体积与启动阶段耗时（boot-baseline §6；已移植 5.0/4.0，§10）
- [x] #73 systemd 精简：unit 裁剪 + `critical-chain` 分析，给出去掉了什么、为什么安全（boot-baseline §7；ttyS1 mask 已移植 5.0/4.0）
- [x] #74 rootfs 格式：ext4 vs squashfs+overlay vs cpio 的加载时间对比（boot-baseline §8，维持 ext4）
- [x] #75 对比报告：每项措施的收益与代价，**含回退成本**（docs/02-development/boot-optimization.md）

> ⚠️ #72/#73/#74 是同一组实验的三个变量。**单独做任何一个都推不出「收益与代价」**，
> 必须固定其余变量、串行测量。

## v0.6.0 · 服务与 demo（已随 v1.0.0 累积发布）

**出口条件**

- [x] #76 `yp-statusd`：C 实现 HTTP `/status`，读 procfs
- [x] #77 `yp-collectd`：采集写 journald（**不用 logrotate**）
- [x] #79 `docs/02-development/adding-a-service.md`：六节教程
- [x] #78 服务数量 × 启动耗时曲线（docs/02-development/boot-optimization.md 第三节）

## v0.7.0 · 5.0 对齐与四版补齐（已随 v1.0.0 累积发布）

**前置**：scarthgap 首次构建通过。**在此之前 #80–#84 并行等于五个一起卡住。**

- [x] #80 发行版对齐：裁特性 / 品牌化 / 三层镜像 / 运行时
- [x] #81 U-Boot 与启动时间基线（QFW 链 5.0 不可用，按预设降级，degraded.txt 登记）
- [x] #82 语法组七配方验证
- [x] #83 服务与 demo 落地
- [x] #84 四版语法对照补齐（3.1 / 4.0 配方能编；3.1/4.0 冻结口径只求能编，4.0 内核优化随移植到位）

## v1.0.0 · 四版收口（已关闭，2026-11-05 发布 `1e1ff48`）

> `v0.5.0` / `v0.6.0` / `v0.7.0` 三个里程碑的内容**全部累积进本版**，从未单独打 tag
> ——同一 commit 上挂三个 tag 等于伪造发布点。对外口径是「累积发布」，
> 见 [`engineering-overview.md`](../engineering-overview.md) §2。

| issue | 内容 | 状态 |
|---|---|---|
| #85 | 四版全兼容回归与报告归档 | ✅ 8/8 全绿（`20261104-ad7c52d*`，随 #113 关闭） |
| #86 | 文档收口与发布 | ✅ 见 [#86 结案评论](https://github.com/zeek-zhao/yp-distro/issues/86#issuecomment-6559294429) |
| #87 | SDK / eSDK 恢复评估 | ✅ 结论见 [`docs/03-build/sdk.md`](../../03-build/sdk.md) §8 |
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

## v1.0.1 · 6.0 全面收口（开放）

**这是「6.0 做完了」的唯一判定容器。** 关闭条件有两条，**两条都要满足**：

### 条件 A：功能证据矩阵全绿

`config/features.txt` 里 **26 条 feature**，每条达到自己应有的证据级别（`static` / `build` / `boot` / `runtime`），无一条低于应达档位。

矩阵在 [`verification-flow.md`](../../01-requirements/verification-flow.md) §6，逐条给出「用什么验、在哪验、现在到没到」。

**当前（2026-11-12）**：✅ 23 条 / ⚠️ 3 条 / ⬜ 0 条。原 3 条「一次性取证」缺口已由 `#132` 解决（smoke 归档进 `docs/qa/wrynose/smoke-*.md`）；3 条 ⚠️ 全是**显式降级**（`foss-scan` / `do-scancode` / `distro-backfill`，登记在 `config/degraded.txt`，有理由，不是缺陷）。

### 条件 B：五条关键路径门槛

| # | 门槛 | 当前 | 归属 |
|---|---|---|---|
| ① | 构建全绿 | ✅ `20261104-ad7c52d` 202/202/0/0 | 已达成 |
| ② | 起机到 login | ✅ 各组合串口全命中 | 已达成 |
| ③ | runtime smoke 全绿 | ✅ `#132` 已实现，归档 `docs/qa/wrynose/smoke-*.md` | 已达成（#138） |
| ④ | 只读根 `/var` 可写 | ⬜ 只有 `ro`，靠 tmpfs 兜底 | `#133` → v1.1.0 |
| ⑤ | 宣称与事实一致 | ✅ `DISTRO_VERSION=1.0.0`，`04_layer` 动态断言与 git tag 一致 | 已达成（#138） |

**A 全绿而 B 未过不算完成；B 全过而 A 有真缺口也不算。** 两条同时满足才允许打点版本 tag。

### 工作项（10 条）

| # | 内容 | 批次 | 优先级 | 状态 |
|---|---|---|---|---|
| #130 | `DISTRO_VERSION` → 1.0.0 + 断言改动态校验 | A 修正 | P0 | ✅ #138 |
| #127 | `supported-releases.txt` 单一事实源 | A 修正 | P1 | ✅ #138 |
| #128 | CI 收缩到 6.0（删四版矩阵、显式 RELEASE、拉单镜像） | A 修正 | P1 | ✅ #138 |
| #129 | 合规只保 SPDX + CVE，拆 scancode 分支 | A 修正 | P1 | ✅ #138 |
| #135 | 全工程文档同步（三分类 20 份 + 两份升级） | A 修正 | P1 | 🚧 本分支 |
| #132 | runtime smoke 三层镜像动作集（DoD ③） | B 验证 | P0 | ✅ #138 |
| #131 | `features.txt` 加证据级别列 + `99_coverage` 校验 | B 验证 | P1 | ✅ #138 |
| #134 | 新增 `design.md` | B 验证 | P1 | ✅ #138 |
| #133 | 只读根 `/var` overlay（DoD ④） | C 功能 | P1 | ⬜ v1.1.0 |
| #107 | 清除指向重写前 commit 的 PR 引用 | 外部 | — | ⬜ 外部工单 |

> **#107 是外部阻塞项**，只能走 GitHub Support 工单。它未完成**不阻塞** 6.0 完成判定，
> 但里程碑关闭前要给它明确结论（已解决 / 已确认无法解决并写明）。

### 三个发布批次（里程碑关闭时三个 tag 都应已打）

| 批次 | 内容 | tag | 性质 |
|---|---|---|---|
| A 修正 | `DISTRO_VERSION`、断言、CI、合规、文档同步（batch1 = #138 已合并 2026-11-12，余 #135） | `v1.0.1` | 零功能（patch） |
| B 验证 | 证据级别、runtime smoke、`design.md`（已随 #138 合并） | `v1.0.2` | 测试能力（patch） |
| C 功能 | 只读根 `/var` overlay | `v1.1.0` | 真功能（minor） |

**里程碑与 tag 不是 1:1，这是刻意的**：一个里程碑装全部，是为了「6.0 完成」有单一容器可判定；拆三个 tag，是为了版本号不失去信息量。`v0.5~v0.7` 的教训是「三个里程碑挤进一个 tag」，这次是「一个里程碑拆成三个 tag」——方向相反，但同样必须显式写明。

### 不做什么

- ptest（`#120`）、`--deep` 内容级扫描（`#119`）、arm64 常态化（`#121`）—— 保持 icebox
- 签名链 `#118` —— 路线一砍掉后降为可选深化
- VEX 与 SBOM 一致性 —— 非 CRA 制造商，显式不做
- 实体硬件验证 —— 永久不做，写成主动声明

## 收口动作（每次发版照做）

1. 开 PR 合入 `main`（`branch-guard` 与 ruleset 都只认 PR 合并）
2. 在 `main` 上打 **annotated tag**，tagger 必须是 `zeek.zhao <zeek.zhao@foxmail.com>`
3. 建 GitHub Release，页内引用 `docs/qa/` 对应归档
4. 关里程碑，把本文件的出口条件逐条勾上
