# YP-M0-PLAN-001 · M0 阶段计划与进度

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-PLAN-001 |
| 版本 | v2.0 |
| 状态 | Approved（阶段计划） |
| 责任人 | zeek-zhao |
| 生效日期 | 2026-11-24 |
| 关联 | PRD v0.1（B 组 P0）、AGENTS.md、`docs/ai/m0-resume-prompt.md` |

## 0. 记录补链（F-09）

按 RV-010 F-09 核查历史提交的 `Doc:` 完整性；**不改写历史提交**，仅在此登记核查结论：

| 提交 | 主题 | `Doc:` 状态 | 对应文档 / 处置 |
|---|---|---|---|
| `ee5377d` | bootstrap 孤立分支 | 缺 | 初始提交，引入 `README.md`、`docs/ai/m0-prompt.md`；为分支起点、无更早基线可补链，豁免 |
| `484fb64` | 记录 PR 工作流阻塞 | 不缺（审计举例有误） | 实际带 `Doc: docs/m0/issues/ISS-002.md`，复核确认合规 |

其余提交均带 `Doc:` 路径。今后新增提交必须带 `Doc:`，由 S8 门禁脚本静态校验（F 阶段落地）。

## 1. 进度表（本表是进度的唯一事实源）

| Step | 内容 | 状态 | 设计文档 | 问题单 | 提交 |
|---|---|---|---|---|---|
| S0 | 空分支、提示词、AI 入口 | 完成 | — | — | `ee5377d` |
| S1 | 发行版层骨架 | 完成 | YP-M0-DES-001 | YP-M0-ISS-001 | 见提交 `Refs: YP-M0-DES-001` |
| S2 | kas 入口与层锁定 | 完成 | YP-M0-DES-002 | YP-M0-ISS-007 | 见提交 `Refs: YP-M0-DES-002`（容器验收 DUMP_STABLE + 4 EDITION_OK） |
| S3 | Ubuntu 容器镜像（jenkins 用户） | 完成 | YP-M0-DES-003 | YP-M0-ISS-003 | 见提交 `Refs: YP-M0-DES-003` |
| S4 | 下载与缓存分卷挂载 | 待开始 | YP-M0-DES-004 | — | — |
| S5 | 首次构建与缓存命中 | 待开始 | YP-M0-DES-005 | — | — |
| S6 | 缓存打包与切分（80% 阈值） | 完成 | YP-M0-DES-006 | YP-M0-ISS-006 | 见提交 `43b14d3` `Refs: YP-M0-DES-006` |
| S7 | 预热镜像发布到容器仓库 | 完成 | YP-M0-DES-007 | YP-M0-ISS-005 | 公共 GHCR 匿名拉取验证通过（方案 B 网页改 public）；见提交 `43b14d3` |
| S8 | PR 门禁 | 待开始 | YP-M0-DES-008 | — | — |
| S9 | 验收与变量索引 | 待开始 | YP-M0-DES-009 | — | — |

状态取值仅四种：`待开始` / `进行中` / `完成` / `阻塞`。置为 `阻塞` 必须同时存在一张未关闭的 `ISS-` 单。

## 2. 阶段出口判据

M0 结束需同时满足：入口能解析、容器能构建、挂载能复用、缓存能切片、门禁能拦截、记录能审计。逐条证据写入 `docs/m0/acceptance.md`。

## 3. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 建立阶段计划与 Step 表 | zeek-zhao |
| v1.1 | 2026-11-24 | 增加文档先行门禁与记录列 | zeek-zhao |
| v1.2 | 2026-11-24 | S1 发行版层骨架完成；登记 DES-001/RV-001/ADR-001/ISS-001 | zeek.zhao |
| v1.3 | 2026-11-24 | 人类批准方案 A：关闭 ISS-002、新增 ADR-002、工作流改为 commit diff + RV 评审 + workflow_dispatch CI | zeek.zhao |
| v1.4 | 2026-11-24 | S3 容器镜像设计完成（DES-003/RV-003/ADR-003），记录 Ubuntu 24.04 依据 | zeek.zhao |
| v1.5 | 2026-11-24 | S3 完成并验证（镜像构建 + jenkins 身份 + entrypoint 校验）；新增 ISS-003 用户冲突修复 | zeek.zhao |
| v1.6 | 2026-11-24 | 镜像分发验证：GHCR push 因 token 缺 packages 权限被拒（ISS-004），用 save/load 闭环验证可移植性 | zeek.zhao |
| v1.7 | 2026-11-24 | 独立 TOKEN 成功推送 builder/cache 镜像到 GHCR；workflow 孤立分支不可 dispatch、包默认 private 不可匿名拉取（ISS-005，待决策） | zeek.zhao |
| v1.8 | 2026-11-24 | 网页改 public 后匿名拉取双镜像并验证功能（B-08 已验证）；ISS-006 修复 cache 卷属主与 builder jenkins UID 对齐，端到端组合通过 | zeek.zhao |
| v1.9 | 2026-11-25 | Stage A 记录一致性修正：补记录补链（F-09）、S8 名称恢复为「PR 门禁」（F-08）；判据 3/4 回退 UNVERIFIED、lessons 补齐（F-03/F-10） | zeek.zhao |
| v2.0 | 2026-11-25 | Stage B：S2 kas 入口完成（DES-002/RV-002/ADR-004/CHG-001/ISS-007），容器内 DUMP_STABLE + 4 edition + commit pin 4；判据 6 → 通过 | zeek.zhao |
