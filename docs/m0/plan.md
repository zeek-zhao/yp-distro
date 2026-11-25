# YP-M0-PLAN-001 · M0 阶段计划与进度

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-PLAN-001 |
| 版本 | v2.4 |
| 状态 | Approved（阶段计划；判据 1-8 全部收口） |

> **编号说明（Stage E）**：`m0-resume-prompt.md` §9.1 要求新建 `ADR-004.md` 裁决分片发布契约，但 ADR-004 已在 Stage B 用于 kas 结构决策（Approved、已发布）。为不覆盖历史决策，分片发布契约顺延为 **YP-M0-ADR-005**（见 `docs/m0/adr/ADR-005.md`）。
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
| S4 | 下载与缓存分卷挂载 | 完成 | YP-M0-DES-004（+ CHG-002） | — | 见提交 `Refs: YP-M0-DES-004`（容器验收 WRITE_OK/PERSIST_OK + 幂等 + 错属主 exit 2） |
| S5 | 首次构建与缓存命中 | 完成 | YP-M0-DES-005 | YP-M0-RV-005 | CHG-003/004/005、ISS-008/009/010/011/013；measure.sh 已入库（T1） |
| S6 | 缓存打包与切分（80% 阈值） | 完成（Stage E 接线 + 契约收紧） | YP-M0-DES-006 / DES-008 | YP-M0-ISS-006 | 见提交 `43b14d3`；Stage E：gen-meta.sh、split 阈值唯一源、manifest source_sha256、sha256 一致 |
| S7 | 缓存分片发布到容器仓库 | 完成（接线）/ 端到端待验 | YP-M0-DES-007 / DES-008 / ADR-005 / CHG-007 / CHG-008 | YP-M0-ISS-005 / ISS-014 | 基线镜像匿名拉取已验（F-02 降级：载荷待 S5）；CHG-007 区分 dispatch 不可用与 CI 阻断——push 可用（run `45594520683`）；CHG-008/ISS-014：载荷改为 S5 具名制品、删除 `push-ok` 假绿、manifest 作为制品上传；端到端由真实 push run 决定 |
| S8 | PR 门禁 | 完成 | YP-M0-DES-009 | YP-M0-ISS-012 | `scripts/gate.sh` 五项 GATE_PASS；`m0-gate.yml` 接线（dispatch + push）；不跑 bitbake |
| S9 | 验收与变量索引 | 完成 | YP-M0-DES-009 | — | `variable-index.md` 28 变量；`check-vars.sh` 故意手改 DRIFT+exit 1；判据 8 → 通过 |

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
| v2.1 | 2026-11-25 | Stage C：S4 挂载完成（DES-004/RV-004/CHG-002），容器内 WRITE_OK/PERSIST_OK、三次 bootstrap 幂等、sstate 独立清空、错属主 exit 2/空间不足 exit 3/挂错卷 exit 1；判据 3/4 → 通过 | zeek.zhao |
| v2.2 | 2026-11-25 | Stage D：S5 首次构建与缓存命中完成（DES-005/RV-005/CHG-003/004/005、ISS-008/009/010/011）；容器内两次构建 rc=0，wall 7096s→214s、二次 sstate 99% 命中、`fetching_lines=0`；prod 补跑一条命令出裸 ext4（wall 10253s、file 识别）；判据 1/ B-12/B-13 → 通过 | zeek.zhao |
| v2.3 | 2026-11-25 | Stage E：S6/S7 接线完成（DES-008/RV-008/ADR-005/CHG-006）；gen-meta 从 threshold.conf 生成、split 去 --max-bytes + 清理 SHA256SUMS.slice + manifest source_sha256、merge 源比对、workflow 新增 publish-cache-slices、空壳镜像结论降级；本地切分链路 5 片合并 sha256 一致、缺片/篡改 exit 1、阈值联动；判据 7 → 通过（本地链路；发布端到端因 L-01 未验）；ADR 顺延编号记录 | zeek.zhao |
| v2.4 | 2026-11-25 | Stage F：S8/S9 完成（DES-009/RV-009/ISS-012）；`gate.sh` 五项门禁 GATE_PASS、`m0-gate.yml` 接线、`variable-index.md` 28 变量、`check-vars.sh` 手改检出（DRIFT+exit 1）；判据 8 → 通过，判据 1-8 全部收口；S8 恢复「PR 门禁」名称 | zeek.zhao |
| v2.5 | 2026-11-25 | T1：CI run 45594520683 判据 8 红灯定位为 `scripts/build/measure.sh` 未入库（`.gitignore` 的 `build/` 误匹配 `scripts/build/`），开 ISS-013 并按 DES-005 §3.5 正式入库；`.gitignore` 改根锚定 `/build/`；干净检出 `VARS_OK drift=0`、`GATE_PASS`；判据 8 结论保持「通过」，事实证据修正 | zeek.zhao |
| v2.6 | 2026-11-25 | T2：CHG-007 修正 CI 触发口径——`workflow_dispatch` 在孤立分支不可用，但 push 可用（run 45594520683）；`m0.yml` 增加受限 push（分支 + paths）；同步 DES-007/ISS-005 §6/plan S7/判据 7，不再称「CI 全部阻断」 | zeek.zhao |
| v2.7 | 2026-11-25 | T3：CHG-008/ISS-014 修发布链路两处硬缺陷——S5 载荷改由 `cache-payload` 制品提供且缺载荷即 fail；删除 `push-ok` 兜底，digest 仅取 inspect；manifest 以 `yp-cache-slices-manifest` 上传；本地静态+分支模拟通过，GH 端到端待 push run | zeek.zhao |
| v2.8 | 2026-11-25 | T4：判据 5 按静态判据收口——配置层 grep 仅 `BB_HASHSERVE = "auto"`、无 `SSTATE_MIRRORS` 远程地址，结论改「通过」并注明非端到端；traceability B-07 同步 | zeek.zhao |
