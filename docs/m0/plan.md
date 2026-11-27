# YP-M0-PLAN-001 · M0 阶段计划与进度

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-PLAN-001 |
| 版本 | v2.18 |
| 状态 | Approved（阶段计划；判据 1-8 全部收口） |
| 责任人 | zeek-zhao |
| 生效日期 | 2026-11-24 |
| 关联 | PRD v0.1（B 组 P0）、AGENTS.md、`docs/ai/m0-resume-prompt.md` |

> **编号说明（Stage E）**：`m0-resume-prompt.md` §9.1 要求新建 `ADR-004.md` 裁决分片发布契约，但 ADR-004 已在 Stage B 用于 kas 结构决策（Approved、已发布）。为不覆盖历史决策，分片发布契约顺延为 **YP-M0-ADR-005**（见 `docs/m0/adr/ADR-005.md`）。

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
| S7 | 缓存分片发布到容器仓库 | 完成 / 端到端已验 | YP-M0-DES-007 / DES-008 / ADR-005 / CHG-007 / CHG-008 / CHG-010 / CHG-011 | YP-M0-ISS-005 / ISS-014 / ISS-016 / ISS-017 / ISS-018 | 基线镜像匿名拉取已验（F-02 降级）；CHG-007 区分低权限 dispatch 不可用与 CI 阻断——push 可用（run `45594520683`）；CHG-008/ISS-014 修复假绿；CHG-010 PAT 具名 secret 修复 GHCR 权限；CHG-011 真实 S5 样本生产 `cache-payload` 制品；ISS-017/018 修表达式与冒号文件名；run `45607197090` 四 job success；CHG-012 全量 S5 缓存 11 GiB 分 8 资产上传、两片 GHCR tag 独立核验 digest（ISS-019/020 关闭） |
| S8 | PR 门禁 | 完成 | YP-M0-DES-009 | YP-M0-ISS-012 | `scripts/gate.sh` 五项 GATE_PASS；`m0-gate.yml` 接线（dispatch + push）；不跑 bitbake |
| S9 | 验收与变量索引 | 完成 | YP-M0-DES-009 | — | `variable-index.md` 28 变量；`check-vars.sh` 故意手改 DRIFT+exit 1；判据 8 → 通过 |

状态取值仅四种：`待开始` / `进行中` / `完成` / `阻塞`。置为 `阻塞` 必须同时存在一张未关闭的 `ISS-` 单。

### 换机链路收口追踪（S7 延伸，AI-004 → AI-005）

> 进度唯一事实源仍为本表；下表集中登记两轮换机相关实测/修复的 T/K 项与记录编号，便于审计。

| 轮次 | 工作项 | 内容 | 记录 |
|---|---|---|---|
| AI-004（新机端到端） | K-1 P1 | 非 1000 UID 默认目标错误 | ISS-022 / CHG-014（closed） |
| AI-004 | K-2 P1 | 字节数 11153397760/11153387520 错配 | ISS-023 / CHG-015（closed） |
| AI-004 | K-3~K-7 P2 | manifest 上传/trap/--parts/runbook/README | ISS-024..028 / CHG-016（closed） |
| AI-004 | K-8 P3 | ghcr digest 未用于 pull、check_target 在 11 GB 后 | 无单，留待后续 |
| AI-004 | NEW P2 | 归档布局 direct vs two-stage | ISS-029（当时 closed，AI-005 重开） |
| AI-005（direct 收口） | T1 | `check_target` 无损放行 marker-only + root OWNER_HINT | CHG-017 / RV-015 V1/V2 |
| AI-005 | T2 | runbook direct 单层 + fetch→bootstrap→preflight | CHG-017 / RV-015 |
| AI-005 | T3 | README 去两步解包 | CHG-017 / RV-015 |
| AI-005 | T4 | manifest 拆 layout/requires_reassembly + fetch 重组改读 + 一致性校验 | ISS-030 / CHG-017 / RV-015 V4/V5 |
| AI-005 | T5 | 更正 ISS-029/RV-013/RV-014/CHG-012/deviations | CHG-017 / RV-015 |
| AI-005 | T6 | 清理两份过期提示词 | CHG-017 / RV-015 V8 |
| AI-005 | T7 | 验证矩阵 V1–V10 | RV-015 |

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
| v2.9 | 2026-11-25 | T5：判据 7 拆两条结论——本地切分链路通过（4 片 merge sha256 一致、缺片/篡改 exit 1），发布端到端 UNVERIFIED（无命中 paths 的 push run、S5 载荷未上传为制品） | zeek.zhao |
| v2.10 | 2026-11-25 | T6：CHG-009/ISS-015 统一 kas 规范性写法（根级 `editions` 链接）并实测 DUMP_STABLE + 四 edition；traceability 待提交 Refs 全换真实提交号；G2/check-vars 去阈值字面量与自我豁免；CI gate run 45600235881 success | zeek.zhao |
| v2.11 | 2026-11-25 | T7：`kas shell` + `bitbake -e` 确认 `BB_HASHSERVE_DB_DIR` 为真实变量（`/work/sstate`），不删不改；归档 push run 45601074345 三 job 失败（缺 S5 制品 + GHCR 权限，ISS-016），判据 7 发布端到端保持 UNVERIFIED | zeek.zhao |
| v2.12 | 2026-11-25 | CHG-010/011 + ISS-016/017/018：PAT 具名 secret 修复 GHCR 写包权限，真实 S5 载荷样本由 release 资产生产 `cache-payload` 制品；修复裸表达式与 sstate 冒号文件名；run 45607197090 四 job success、分片 digest 经 GHCR 独立核验；判据 7 → 通过，M0 收口 | zeek.zhao |
| v2.13 | 2026-11-25 | CHG-012：全量 S5 缓存（11 GiB）分 8 个 release 资产上传并重组校验；ISS-019 修复 split.sh 大文件切片丢数据，ISS-020 全量分片 01 瞬时 unknown blob 重试成功；两片 GHCR digest 独立核验 | zeek.zhao |
| v2.14 | 2026-11-26 | 新机端到端实测（AI-004）：CHG-014/015/016 + ISS-022..029 + RV-014；K-1/K-2 先修并复跑、K-3~K-7 报告后修、K-8 留待；release 8 分片实跑 `mode=direct`、prod 两构建成功、幂等验证通过；发现归档布局与文档 two-stage 矛盾（ISS-029 当时关闭） | zeek.zhao |
| v2.15 | 2026-11-26 | 换机链路 direct 收口（AI-005）：CHG-017 + ISS-029（重开）/ISS-030 + RV-015；复现 release direct（HTTP Range）、pack.sh two-stage、marker-only 误杀、manifest layout 混用。T1 check_target 无损放行 marker-only + root OWNER_HINT；T2 runbook 改 direct 单层 + 顺序 fetch→bootstrap→preflight；T3 README 去两步解包；T4 manifest 拆 layout/requires_reassembly + fetch 重组改读后者 + 一致性校验（字节/哈希/资产不变）；T5 更正 ISS-029/RV-013/RV-014/CHG-012/deviations；T6 清理两份过期提示词；T7 验证矩阵 V1–V10；gate/vars 绿、不改发布资产 | zeek.zhao |
| v2.16 | 2026-11-26 | UID 路径与文档一致性收口（AI-006）：CHG-018 + ISS-031/ISS-032 + RV-016；uid1234 隔离探针复现默认 bootstrap exit 2（UID_MISMATCH）、显式 --uid exit 0。T1 runbook §3 步骤 5/6/7、§5.2 分路径 A(sudo --uid 1000)/B(显式当前 UID + yp-builder:local)，步骤 7 用 `$YP_BUILDER_IMAGE`；T2 测试提示词 §4.2/§7/§9/§12 判据 4 单层 mode=direct、K-5 补 CHG-017 已修；T3 GHCR 源 tar 口径统一 UNVERIFIED（runbook/CHG-012/017/ISS-029/RV-013/015/提示词/fetch 头注释）；T4 README 明确先 fetch 后 bootstrap；T5 runbook §4 DEST_PARENT、ASSET_OK name= 字段、bootstrap:4 注释、closeout-prompt errata；T6 ISS-029 关闭 + traceability 拆分；V1–V11、gate/vars 绿、不改发布资产/不下载 11 GiB | zeek.zhao |
| v2.17 | 2026-11-26 | README/宿主依赖/路径 B 文档收口（AI-007）：CHG-019 + ISS-033/034/035 + RV-017；uid1234 探针默认 exit 2、显式 exit 0、root --uid 1000 exit 0。T1 README 第 2 步拆路径 A/B 两个独立代码块二选一、第 1 步路径 B 可跳过 GHCR pull；T2 README/runbook 改「Docker + git/bash/python3/curl/tar/sha256sum，不需 kas」，runbook §1 加宿主工具行，verify-env.sh 加 0) 宿主依赖段（缺 python3 首行 FAIL DEP_MISSING、非 registry 401，退出码语义不变），并移除文件尾部历史误留的 `EOF`/命令行；T3 路径 B 镜像变量自包含（runbook 步骤 7 跨 shell 注、test prompt §5 用 `$IMAGE`、§4.2 重新 export 说明）；T4 runbook §4 DEST_PARENT 仅手工边界；T5 RV-016 文首更正块回填 V11（gate/publish 均 success）、V3/V4 措辞，plan v2.17、traceability 本轮行、deviations #6；V1–V10、gate/vars 绿、不改发布资产/不下载 11 GiB | zeek.zhao |
| v2.18 | 2026-11-26 | M0.0 冻结 + CI 记录更正（AI-007 v1.1，只动记录/文档，不动脚本）：RV-017 文首更正块（50893a9 gate run 45803774082 success、publish 因 paths 未触发仍 UNVERIFIED、旧 publish 45799521429 与本轮无关）；CHG-019 errata；RV-016 补 AI-007 CI 指针；traceability 末行状态改 V9 gate success/publish 未触发；deviations #7（纯文档提交不触发 publish 为 paths 设计结果，非异常）；sudo 文档缺口（README/runbook/test prompt 路径 A 需 sudo、root 可去、无 sudo 走 B）。tag `m0.0` 指向本轮更正提交，建 `release-m0.0` 与 `feat-m0.1-evidence`；不改 Step 表既有状态、不下载 11 GiB、M0.1（§6）未开工 | zeek.zhao |
