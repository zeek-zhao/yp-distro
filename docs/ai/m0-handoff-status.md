# M0 交接现状与执行指令（2026-11-25）

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-003 |
| 版本 | v1.0 |
| 状态 | Approved |
| 用途 | 交接给外部 AI 编码代理：现状 + 遗留 + 本轮该做什么 |
| 配套文档 | `docs/ai/m0-resume-prompt.md`（A→F 阶段详细验收）、`docs/m0/reviews/RV-010.md`（审计发现） |
| 仓库 / 分支 | `https://github.com/zeek-zhao/yp-distro` · `feat-m0-kas-bootstrap` @ `f0ffd41` |

> 本文件是自包含的：AI 只读这一份也能开工；但涉及具体验收命令时以 `docs/ai/m0-resume-prompt.md` 为准。

---

## 1. 一句话现状

骨架、容器镜像、缓存切分脚本、公共分发路径都已可用；但 **kas 入口、分卷挂载、首次构建三件核心事没做**，且 **CI 自动发布因分支形态无法触发**。M0 当前判定：**有条件通过**（RV-010）。

---

## 2. 完成度矩阵（截至 `f0ffd41`）

| Step | 状态 | 说明 |
|---|---|---|
| S0 空分支 + AI 入口 | 完成 | `AGENTS.md`、`docs/ai/*`、`scripts/ai-entry.sh` |
| S1 发行版层骨架 | 完成 | `meta-yp-distro/conf/{layer.conf,distro/yp-wrynose.conf}`，`LAYERSERIES_COMPAT` 单值 `wrynose` |
| S2 kas 入口与层锁定 | **未开始** | **无 `kas/` 目录**，B-01/B-02 无法验收 |
| S3 Ubuntu 24.04 构建镜像 | 完成 | `docker/Dockerfile`：ubuntu:24.04 + kas + `jenkins` 非 root，UID 可配 |
| S4 下载/缓存分卷挂载 | **未开始** | 缺 `scripts/bootstrap.sh`、`scripts/preflight.sh` |
| S5 首次构建与缓存命中 | **未开始** | 无产物、无耗时、无命中率 |
| S6 缓存打包与切分 | 部分完成 | 脚本可用（本环境实跑通过），**未接入发布链路** |
| S7 预热镜像发布 | 部分完成 | 公共分发可用，但推的是**空壳布局镜像**；Actions 自动发布未实跑 |
| S8 CI 门禁 | 未开始 | `m0.yml` 只有发布，无门禁 |
| S9 验收与变量索引 | 未开始 | 无 `variable-index.md`，验收未闭环 |

需求侧（B 组 12 条）：已验证 3 条（B-03、B-04、B-08 中 B-08 需降级）、进行中 2 条（B-01、B-02）、未开始 7 条。

---

## 3. 已验证、可直接复用的资产

| 资产 | 证据 |
|---|---|
| builder 镜像 | `ghcr.io/zeek-zhao/yp-builder:wrynose-m0`，digest `sha256:ef28c044…`，589 MB，`whoami`→`jenkins`，root 启动被 entrypoint 拒绝（exit 1） |
| cache 布局镜像 | `ghcr.io/zeek-zhao/yp-cache:wrynose-m0`，修复版 digest `sha256:1eaf38f5…`，卷属主 `1000:1000` |
| 匿名拉取 | 包设为 public 后，未登录 `docker pull` 成功（ISS-005 方案 B） |
| 切分/合并 | 20 MiB 按 6 MiB 切 4 片，合并 sha256 与源一致（`965776f8…`）；缺片时 `merge.sh` 拒绝并 `exit 1`（RV-010 §3） |
| 阈值集中 | `SLICE_MAX_BYTES=8589934592`、`UPLOAD_TIMEOUT_SEC=480`，仅定义在 `scripts/cache/threshold.conf` |

---

## 4. 已知遗留与阻塞（必须逐条交接，不许当已完成）

| 编号 | 遗留 | 影响 | 当前处理方式 |
|---|---|---|---|
| L-01 | **孤立分支上的 workflow 不被 Actions 注册，`workflow_dispatch` 无法手动触发** | `m0.yml` 处于"文件存在但不可执行"状态，自动发布从未实跑 | 已作为遗留项写入 DES-007 / ISS-005（ISS-005 §6：关闭条件达成于方案 B，Actions 自动发布为遗留项）；**将来 M0 并入 main 后，`m0.yml` 随合并生效** |
| L-02 | 公共分发当前依赖**手工步骤**：独立 TOKEN 推送 + 网页把包改 public | 换机器或换人复现需重新走一遍 | 已完整验证可用；并入 main 后由 `GITHUB_TOKEN` 发布，包自动链接仓库继承 public 可见性，不再需要网页手改 |
| L-03 | 孤立分支与 `main` 无共同祖先，**无法开 PR** | 无在线评审界面，CI 只能 dispatch（又受 L-01 限制） | ADR-002 方案 A：commit diff + `RV-` 记录评审 |
| L-04 | **S2/S4/S5 未做** | 判据 1/3/4/6 悬空，S6/S7 的"完成"建立在不存在的缓存之上 | 本轮 A→F 阶段解决 |

> 对 AI 的明确要求：**不许把 L-01/L-02 写成"已自动化"**。如果要改变触发方式，走 CHG + ADR，不要偷偷改 `on:`。

---

## 5. 本轮执行指令（A → F，一次一个 Stage）

| Stage | 做什么 | 关键验收 | 完成后更新 |
|---|---|---|---|
| A | 记录修正：`lessons.md` 补 7 条；判据 3/4/5 临时回退 `UNVERIFIED` | 文档无自相矛盾 | `lessons.md`、`acceptance.md` |
| B | **S2 kas**：`kas/yp.yml`+`base.yml`+`machines/qemux86-64.yml`+4 个 edition；repos 全部 pin SHA；kas 版本固定 | 两次 `kas dump` diff 为空、4 个 edition 可解析 | 判据 6 → 通过；B-01/B-02/B-07 |
| C | **S4 挂载**：`preflight.sh`（只读、exit 2/3 语义）+ `bootstrap.sh`（幂等） | 删容器后新容器数据仍在；错属主被拒 | 判据 3/4 → 通过；B-05/B-06 |
| D | **S5 构建**：空卷首次 + 保留缓存第二次；统计 `from sstate` 原始行 | 两次耗时、产物路径、复用行数 | 判据 1 → 通过；B-12/B-13 |
| E | S6/S7 接线：ADR-004 定分片发布形态；`gen-meta.sh` 从 `threshold.conf` 生成；`split.sh` 去 `--max-bytes`；发布链 pack→split→上传 | 合并 sha256 相等、缺片 exit 1 | 判据 7 → 通过；B-08 降级为"基线已验证/载荷待 D 阶段" |
| F | S8 门禁（脚本语法、阈值唯一、无缓存服务器、提交身份、文档一致性）+ S9 `variable-index.md` | 判据 8 有"故意手改被检出"样例 | 判据 1–8 全部收口 |

**关于 L-01 的可选动作（放在 E 阶段，需人类先批准）**：

- 方案 C：`m0.yml` 增加 `on: push`（限定 `branches: [feat-m0-kas-bootstrap]` + `paths` 过滤到 `docker/**`、`scripts/cache/**`），保留 `workflow_dispatch` 供并入 main 后使用。这样孤立分支上也能自动发布，不改变分支拓扑。
- 若采用，先出 `CHG-00N`（CI 触发契约变更）+ 更新 ADR-002/004，**不得直接改 `on:` 就推**。

---

## 6. 全局红线（违反即打回）

1. 只用 `zeek.zhao <zeek.zhao@foxmail.com>` 提交；禁止任何 AI 署名 trailer。
2. **没跑过的命令不许写"通过"**；跑不了写 `UNVERIFIED` + 原因。
3. 阈值只在 `scripts/cache/threshold.conf`；`cache-meta.json` 必须由脚本生成，不许写死。
4. 容器内禁止 root；固定 `jenkins` 用户。
5. 禁止远程 `SSTATE_MIRRORS` / hashserv；不引入 `bitbake-setup`。
6. 不开 PR；不新增 PRD 外需求；偏离写 `deviations.md`。
7. 一次一个 Stage，提交后停。
8. 任何非预期现象先开 `ISS-` 单再修，贴验证输出才可 Close。

提交格式：

```text
<type>(m0): 一句话动作
Refs: YP-M0-DES-0NN / YP-M0-ISS-0NN / YP-M0-CHG-0NN
Doc: docs/m0/design/S<N>-xxx.md
```

---

## 7. 每个 Stage 结束必须回报六项

1. 改动文件清单（新增/修改分开）
2. 执行过的命令清单（含失败的）
3. 已验证项（贴关键输出行）
4. 未验证项及原因
5. 新增记录编号（DES/ISS/CHG/RV）
6. 下一步建议

**禁止用"已完成"三个字代替证据。**

---

## 8. 直接粘贴给 AI

```text
仓库：https://github.com/zeek-zhao/yp-distro，分支 feat-m0-kas-bootstrap（@f0ffd41，孤立分支，与 main 无共同祖先，不开 PR）。
先读：AGENTS.md → docs/ai/m0-prompt.md → docs/ai/m0-resume-prompt.md → docs/m0/plan.md → docs/m0/handoff.md → docs/m0/reviews/RV-010.md → docs/ai/m0-handoff-status.md（本文件）。

现状：S0/S1/S3 完成；S6/S7 部分完成（脚本可用、发布是空壳镜像）；S2 kas、S4 挂载、S5 首次构建、S8 门禁、S9 变量索引均未开始。RV-010 结论"有条件通过"，原因是顺序倒置导致判据 1/3/4/6 悬空。
遗留：孤立分支上的 workflow 不被 Actions 注册，workflow_dispatch 无法触发；公共分发目前依赖"独立 TOKEN 推送 + 网页改 public + 匿名拉取"的手工路径；这两项已如实记在 DES-007/ISS-005，不许写成"已自动化"。

按 A→F 逐 Stage 推进，一次只做一个，做完提交并停下等我确认：
A 记录修正（lessons 7 条、判据 3/4/5 回退 UNVERIFIED）
B S2 kas：kas/{yp.yml,base.yml,machines/qemux86-64.yml,editions/{dev,prod,dev-kernel,ci}.yml}，repos 全部用 git ls-remote 取真实 SHA pin，Dockerfile 固定 kas 版本，DL_DIR/SSTATE_DIR 指向 /work/{downloads,sstate}；验收 kas --version、两次 kas dump 用 diff 断言无差异、四个 edition 可解析、LAYERSERIES_COMPAT 单值。
C S4 挂载：scripts/preflight.sh（只读检查，属主不符 exit 2、空间不足 exit 3）+ scripts/bootstrap.sh（幂等）；两卷分别 -v 挂载；验收必须含"删容器后新容器数据仍在"与"错属主被拒"的真实输出。
D S5 构建：空卷首次构建、清 build 保留 downloads/sstate 后第二次构建；贴两次 wall time、产物路径、cooker log 中 from sstate 复用行数。
E S6/S7 接线：先 ADR-004 定分片发布形态（每片一 tag 或 oras artifact）；新增 scripts/cache/gen-meta.sh 从 threshold.conf 生成 cache-meta.json；split.sh 去掉 --max-bytes 覆盖并清 SHA256SUMS.slice；发布链 pack→split→上传→记录 digest；空壳镜像结论降级为"仅布局基线"。若要让孤立分支自动发布，先出 CHG 再给 m0.yml 加受限 push 触发，不许直接改 on:。
F S8 门禁（脚本语法、阈值唯一、无缓存服务器、提交身份、文档一致性，不跑 bitbake）+ S9 docs/m0/variable-index.md，并给"故意手改被检出"的样例；最后 acceptance 判据 1–8 全部收口。

红线：只用 zeek.zhao <zeek.zhao@foxmail.com> 提交、禁止 AI 署名；没跑过不许写"通过"；阈值只在 threshold.conf；容器禁止 root；禁止远程 sstate/hashserv 与 bitbake-setup；不开 PR；不新增需求；非预期现象先开 ISS 再修，贴证据才关单。

提交格式：
<type>(m0): 一句话动作
Refs: YP-M0-DES-0NN / YP-M0-ISS-0NN / YP-M0-CHG-0NN
Doc: docs/m0/design/S<N>-xxx.md

每 Stage 回报六项：改动文件、执行命令（含失败）、已验证项（贴输出行）、未验证项及原因、新增记录编号、下一步建议。
```

---

## 9. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 建立交接现状与执行指令，纳入 L-01/L-02 遗留 | zeek.zhao |
