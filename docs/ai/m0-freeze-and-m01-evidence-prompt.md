# YP-M0-AI-008 · M0 收口冻结 + M0.1 证据闭环

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-008 |
| 起点 | `feat-m0-kas-bootstrap` @ `50893a9` |
| 执行方 | 外部 AI（代码执行方） |
| 审核方 | 本代理（只审文档与证据，不代跑构建） |
| 本提示词范围 | Phase 0：M0 记录收口 + `m0.0` 冻结 + 分支；Phase 1：M0.1 证据闭环计划 |
| 执行方式 | **先只做 Phase 0，提交后停下等评审；Phase 1 未获评审通过不得开工** |

> 这不是新功能轮次。Phase 0 只修记录和文档，不改任何脚本业务逻辑；Phase 1 只把 M0 残留的 `UNVERIFIED` 变成真实证据，不新增发行版功能。

---

## 0. 开工前必须知道的事实（已由审核方独立核实）

1. 当前 HEAD 为 `50893a9`，工作区干净；本轮 13 个文件的改动已落地。
2. 本轮 gate 为 [`45803774082`](https://github.com/zeek-zhao/yp-distro/actions/runs/45803774082)，状态 `completed/success`。
3. `50893a9` 的 **publish 没有被触发**：`m0.yml` 的 `paths` 只含 `docker/**`、`scripts/cache/**`、`kas/**`，本次只改 README/docs/verify-env，不命中；这不是失败。
4. 旧 publish [`45799521429`](https://github.com/zeek-zhao/yp-distro/actions/runs/45799521429)（AI-006 `1d1ddb6`）的 4 个 job 全部 `success`，`RV-016` V11 的 success 本身正确。
5. `RV-017.md:67` 的 V9 仍停在“归档时点本轮提交尚未推送 → UNVERIFIED”，没有 gate run，也没有“publish 未触发”；`CHG-019.md:22` 仍写“publish in_progress → UNVERIFIED”，与 `RV-016` V11、`ISS-035` 矛盾。
6. `README`/runbook 的路径 A 使用 `sudo`，但宿主工具清单没有列 `sudo`；root 无 `sudo`、UID=1000 非 root 无 `sudo` 两种情况会卡在路径 A。路径 B 不需要 `sudo`。
7. `verify-env.sh` 的 6 条 `DEP` 已落地；本机无 Docker，正常跑只能到 `FAIL DOCKER`；隔离 PATH 缺 `python3` 时首个 `FAIL` 是 `DEP_MISSING python3`、`exit 1`。外部完整环境的 `fail=0 warn=1` 不能由本机替代。

---

## 1. 硬约束（Phase 0/1 都适用）

- 只在本轮指定分支工作，不碰 `main`；不向 `main` 开 PR（ADR-002 方案 A 继续有效）。
- 提交身份只允许 `zeek.zhao <zeek.zhao@foxmail.com>`，禁止 AI 署名 trailer。
- 未实际执行的结论一律写 `UNVERIFIED`；不得用本地静态检查冒充远端 CI，不得用 sample 冒充 full。
- 不在审核机下载 11 GiB；真实全量测试只能在独立新机执行。
- 不在真实缓存上试 `--force`；Phase 0/1 的正常顺序不允许 `--force`。
- 不改写历史 RV/CHG/ISS 的原文结论；需要修正时用文首更正块或 errata，保留旧行。
- 不改 `manifests/` 的 `expected_bytes`、分片 `sha256`、`digest`；未验证的 `layout` 只能按证据更新，不能顺手改成“看起来合理”的值。
- 一次一步：Phase 0 提交后停止，等评审；不要在同一个提交里预埋 Phase 1 代码。

---

## 2. Phase 0：本轮收口（只动记录/文档）

### T1 · 回填 `RV-017` 的 CI 事实

在 `docs/m0/reviews/RV-017.md` 的表格之后、§1 之前加一个**文首更正块**（不要改 V9 原行）：

```markdown
> **2026-11-26 推送后更正（AI-008 Phase 0）**
>
> 本文件归档时点（推送前）V9 写 `UNVERIFIED`，该行保留为历史快照。
> 实际推送后：提交 `50893a9` 的 gate run `45803774082` 为 `completed/success`；
> `50893a9` 的 publish workflow **未被触发**（`m0.yml` paths 仅 `docker/**`、`scripts/cache/**`、`kas/**`；
> 本轮只改 README/docs/verify-env），因此 publish 仍为 `UNVERIFIED`，不是失败。
> 旧 publish run `45799521429`（AI-006 `1d1ddb6`）4 job success，与本轮 publish 无关，不得混写。
```

验收：`grep -n "45803774082\|未被触发\|45799521429" docs/m0/reviews/RV-017.md` 三处都在；V9 原行仍在。

### T2 · `CHG-019` 加 errata

在 `docs/m0/changes/CHG-019.md` 文首加：

```markdown
> **Errata（2026-11-26，AI-008 Phase 0）**
>
> 本文“变更后”段写于 AI-006 publish 尚未完成时；实际 `45799521429` 的 4 个 job 已全部 success。
> AI-007 的 `50893a9` 是纯文档提交，publish 未被 paths 触发，不能写成“publish success”。
> 旧行保留为历史，最终状态以本 errata 与 `RV-017` 更正块为准。
```

验收：`grep -n "Errata\|45799521429\|未被 paths 触发" docs/m0/changes/CHG-019.md` 命中。

### T3 · `RV-016` 指针同步

在 `docs/m0/reviews/RV-016.md` 文首更正块补一行（或追加一个小段）：

```markdown
> AI-007 `50893a9` 的 CI 不在 V11 范围内：gate `45803774082` success；publish 因 paths 未触发，
> 当前状态见 `RV-017` 文首更正块。V11 只描述 AI-006 `1d1ddb6` 的 `45799521429`。
```

验收：`RV-016` 不再让读者把 AI-007 的 CI 误解为“已 publish success”。

### T4 · `plan.md` v2.18 + `traceability` + `deviations`

1. `docs/m0/plan.md` 追加 v2.18 行，内容至少包含：
   - M0.0 冻结提交：Phase 0 记录更正；
   - gate `45803774082` success；
   - `50893a9` publish 未触发（paths），publish 仍 `UNVERIFIED`；
   - tag `m0.0` 指向 Phase 0 更正提交；
   - 不改 Step 表既有状态，不把 M0 Final 改成“未完成”。
2. `docs/m0/traceability.md` 最后一行状态改为：
   - V1–V8、V10 已验证；
   - V9 gate success / publish 未触发（路径过滤）；
   - 真实全量正常顺序重下、8 片重组、`--mode ghcr`、GHCR 源 tar 布局、K-8 仍 `UNVERIFIED`。
3. `docs/m0/deviations.md` 追加 `#7`：AI-007 纯文档提交不触发 publish，是 paths 设计的结果，不是 CI 失败；不作为异常偏差。

### T5 · `sudo` 文档缺口

只改文档，不改 `verify-env.sh` 业务逻辑：

1. `README.md` 宿主工具段（目标段/三步开头）改为：
   - `Docker + git / bash / python3 / curl / tar / sha256sum`；
   - 路径 A 另需 `sudo`；路径 B 不需要；
   - root 可去掉 `sudo` 直接执行；UID=1000 非 root 且无 `sudo` 时走路径 B。
2. `docs/runbook-new-machine.md` §1「宿主工具」行补同样一句；§5.2 路径 A 补“root 可去 sudo；无 sudo 走 B”。
3. `docs/ai/m0-new-machine-test-prompt.md` 若路径 A 有 `sudo`，补一句“root 可去 sudo；无 sudo 走路径 B”。
4. 不新增 `verify-env` 的 `sudo` 检查；`sudo` 不是所有路径的硬依赖。

### T6 · 门禁、提交、冻结

1. 提交前：
   ```bash
   git status --short
   git diff --stat
   bash scripts/gate.sh          # 期望 GATE_PASS
   bash scripts/check-vars.sh    # 期望 VARS_OK drift=0
   grep -RInE 'github_pat_|ghp_' . --exclude-dir=.git || true
   ```
2. 提交：
   - 标题：`docs(m0): freeze M0 with CI correction and portability plan`
   - `Refs: YP-M0-RV-017 / YP-M0-CHG-019 / YP-M0-RV-016`
   - `Doc: docs/ai/m0-freeze-and-m01-evidence-prompt.md`
   - 无 AI 署名。
3. 打 tag（**必须在更正提交上，不得打在 `50893a9` 或提示词提交上**）：
   ```bash
   git tag -a m0.0 -m "M0.0 doc freeze: criteria 1-8 pass; residual UNVERIFIED in RV-017; M0.1 closed next"
   git push origin m0.0
   ```
   `m0.0` 是纯文档冻结提交，publish 不应被触发；不要为了“让 tag 也有 publish”而强行 dispatch 或改 paths。tag 指向的是已经 gate 绿的更正提交。
4. 拉冻结分支与下一轮分支：
   ```bash
   git branch release-m0.0 m0.0
   git push origin release-m0.0
   git branch feat-m0.1-evidence m0.0
   git push origin feat-m0.1-evidence
   ```
5. 核对：
   ```bash
   git ls-remote origin refs/tags/m0.0 refs/tags/m0.0^{} refs/heads/release-m0.0 refs/heads/feat-m0.1-evidence
   git rev-parse m0.0^{}
   git status --short
   ```
   - tag 的 peeled commit 必须等于 Phase 0 提交；
   - 两个分支指向同一 commit；
   - 不 `--force`、不移动/删除 tag、不改写远端历史。
6. 若推送时远端有新提交：先 rebase 到远端顶端；有冲突立即停止并报告，不要强推。

### Phase 0 报告（六件事）

必须回报：改动文件、执行命令、已验证项、未验证项及原因、新增/更正记录编号、tag 与分支的远端 SHA。明确写“Phase 1 未开工”。

---

## 3. Phase 1：下一轮 M0.1 证据闭环（评审通过后执行）

### 3.1 目标与边界

- 分支：`feat-m0.1-evidence`，基点 `m0.0`。
- 目标：把 M0 剩下的 `UNVERIFIED` 变成真实证据；不新增功能、不碰 `main`、不改 M0 历史结论。
- 记录目录：建议新建 `docs/m0.1/`（`plan.md`、`design/`、`reviews/RV-018.md`、`changes/CHG-020.md`、`issues/ISS-036.md`、`acceptance.md`），M0 的 Final 记录只加指针。若复用 `docs/m0/`，编号顺延且不得改 M0 Final 结论。
- 编号顺延：`DES-010`、`RV-018`、`CHG-020`、`ISS-036`；连续，不跳号。
- 真实全量测试只在独立新机执行；审核机不下载 11 GiB。

### 3.2 E1 · 真实 release 全量正常顺序（最高优先）

在独立新机（Ubuntu 24.04、Docker、≥300 GB 可用、网络可拉 GitHub release）从 `m0.0` clone：

1. `verify-env.sh`，记录 `ENV_OK/ENV_WARN/ENV_FAIL` 与 `fail/warn` 计数。
2. 按 runbook §3 步骤 4 取 release `m0-s5-payload-full` 的 8 个分片：
   - 目标为空，**不得 `--force`**；
   - 必须走 `fetch-cache` 默认 `requires_reassembly=true` 的 8 片重组；
   - 记录 `REASSEMBLE_OK bytes=11153387520`、`SHA256_OK=1c8126d4…`；
3. 按路径 A（`sudo --uid 1000`）或路径 B（显式当前 UID + `yp-builder:local`）执行 bootstrap；
4. `preflight`；
5. 记录 `STRUCT_OK mode=direct downloads=1288 sstate=6945`；
6. 全程保存命令、日志路径、耗时、磁盘峰值；不得手工 `tar` 解包替代 fetch。

通过条件：以上四项输出齐全，且没有 `--force`、没有手工改归档。

### 3.3 E2 · 8 片重组边界

- 用同一 manifest 验证 `--parts 1` **必须 exit 1**（分片归档不支持部分取片）。
- 用 `unpack-only` 对已重组 tar 做布局探测，确认 direct 单层；记录 `STRUCT_OK`。
- 若 `requires_reassembly` 缺失回退旧逻辑，单独记录回退用例，不混入主证据。

### 3.4 E3 · `--mode ghcr` 全链路 + K-8

在独立新机、目标为空、不得 `--force`：

1. 先修 `fetch-cache.sh` 的 K-8：
   - `check_target` 移到 `docker pull` 循环之前（目标非空时在下载前失败）；
   - manifest 有 `digest` 时按 digest 拉取（`docker pull "$im@$dg"`），不要只按 tag；
   - 拉取后校验 `docker image inspect` 的 `RepoDigests` 与 manifest digest 一致；缺失 digest 时才回退 tag，并在日志标记 `DIGEST_FALLBACK`；
   - 不改分片 `bytes`/`sha256`/`digest`。
2. 执行 `--mode ghcr --manifest manifests/full-slices-manifest.json`，记录 `SLICE_OK`、`merge`、`SHA256_OK=a8870b50…`、`STRUCT_OK`。
3. 实际确认 GHCR 源 tar（`a8870b50…`）的布局；若确认，更新 `full-slices-manifest.json` 的 `layout` 与 `layout_note`，但**不得改 `total_bytes`、分片字节、sha256、digest**；若仍无法确认，保持 `UNVERIFIED`。
4. 记录匿名 pull 的 digest；若需要认证，说明原因，不把 token 落盘。

### 3.5 E4 · 发布 CI 观察

- 因为 E3 会改 `scripts/cache/**`，push 后 `m0.yml` 的 restricted push 应触发 publish；核对 4 个 job（`prepare-cache-payload`、`publish-cache`、`publish-cache-slices`、`publish-builder`）真实状态。
- 若未触发，用 `workflow_dispatch` 触发一次；记录 run id、head_sha、每个 job 结论。
- 只跑 sample 就写“sample 通过”，不得写成 full 通过；全量 release 仍以 E1 为准。

### 3.6 E5 · 记录与下一标签

- 新建 `RV-018`：E1–E4 的命令、真实输出、未验证项与复验方法。
- 新建 `CHG-020`：K-8 的 digest 拉取/前置 `check_target` 行为变更；若改 `layout`，同单记录依据。
- 新建 `ISS-036`：若 E3/E4 出现新问题，先开单再修；没有新问题就不硬造单。
- 更新 M0.1 `plan.md`、`traceability.md`、`acceptance.md`；M0 的 `acceptance.md` 不改 Final 结论，只加指针。
- 通过后：
  ```bash
  git tag -a m0.1 -m "M0.1 evidence closure: E1-E4 real evidence; residual list updated"
  git push origin m0.1
  git branch release-m0 m0.1
  git push origin release-m0
  ```
- 只有 `m0.1` 打完后，才从 `m0.1` 拉 M1 分支（见 §4）；Phase 1 不开始 M1 功能。

### 3.7 M0.1 出口判据

- E1：真实 8 片正常顺序全量重下，`reassemble/sha/struct` 三项与既有事实一致；
- E2：`--parts 1` 拒绝、direct 单层确认；
- E3：`--mode ghcr` 真实跑通，K-8 修复有测试证据；GHCR 源 tar 布局有结论或仍 `UNVERIFIED`；
- E4：publish 4 job 真实状态，sample/full 口径分清；
- E5：`RV-018` 有输出，`GATE_PASS`/`VARS_OK`，无 token 落盘；
- 任何一项没跑，写 `UNVERIFIED` 并给复验命令，不得写通过。

---

## 4. 分支与标签路线（本轮 + 下一轮 + M1 入口）

| 阶段 | 分支 | 标签 | 出口 |
|---|---|---|---|
| M0 文档冻结 | `feat-m0-kas-bootstrap` → 更正提交 | `m0.0` | 记录更正；gate/vars；`release-m0.0`；`feat-m0.1-evidence` |
| M0.1 证据闭环 | `feat-m0.1-evidence`（基于 `m0.0`） | `m0.1` | E1–E5；`release-m0`；可进入 M1 |
| M1（未开始） | `feat-m1-<scope>`（基于 `m0.1`） | `m1.0` | 需 PRD/范围先评审；本提示词不定义 M1 功能 |

规则：

1. `m0.0` 只打一次，不移动；`release-m0.0` 是不可变快照。
2. `m0.1` 只打一次；`release-m0` 指向 `m0.1`，作为 M0 最终释放线。
3. 任何下一轮分支都从**标签**拉，不从会漂移的 `feat-m0-kas-bootstrap` 拉。
4. M1 不在本提示词范围内；先把 M1 范围写进新的 DES/PLAN 并评审，再拉 `feat-m1-*`。
5. 不 `--force` 推送、不删除/移动 tag、不把 `m0.0` 与 `m0.1` 混为一个发布点。

---

## 5. 完成后必须回报的六件事

1. 改动文件清单；
2. 执行命令清单（含 tag/branch/push/CI 查询）；
3. 已验证项（带真实输出/run id）；
4. 未验证项及原因（不得省略）；
5. 新增/更正记录编号；
6. 下一步建议（Phase 1 是否可开工，或还缺什么）。

Phase 0 完成后只回报 Phase 0，不要顺手开始 Phase 1。
