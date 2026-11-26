# YP-M0 README / 宿主依赖 / 路径 B 文档收口 · AI 执行提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-007 |
| 版本 | v1.1 |
| 日期 | 2026-11-26 |
| 适用仓库 | `https://github.com/zeek-zhao/yp-distro`，分支 `feat-m0-kas-bootstrap` |
| 编写时 HEAD | `8b30722`（v1.1 补充稿提交；开工以 `git rev-parse HEAD` 为准） |
| 目标 | **v1.0 的 T1–T5 已由外部 AI 执行并提交 `50893a9`，不要重复执行。** v1.1 只做两件事：① 本轮记录收口 + `m0.0` 冻结 + 分支；② 下一轮 M0.1 证据闭环（真实全量 / 8 片 / ghcr / K-8 / publish） |
> **执行入口（v1.1，2026-11-26）**：本文 v1.0 的 T1–T5 已执行并提交 `50893a9`，仅作为历史保留，**不要再跑一遍**。本轮只看本文件末尾的 **§5 本轮收口** 与 **§6 下一轮 M0.1**；§5 完成后必须停下等评审，§6 未获评审通过不得开工。
>
> 事实基线：`50893a9` 的 gate `45803774082` success；`50893a9` 的 publish 因 paths 未触发；旧 publish `45799521429`（AI-006 `1d1ddb6`）4 job success。`RV-017` V9 仍停在归档时点 `UNVERIFIED`，`CHG-019` 仍写 publish `in_progress`，这是本轮要修的记录缺口。

## 0. 角色、边界与已定决策

你是本轮 **README 与前置条件收口执行方**。以下决策已确定，不要重新做方案对比：

1. **README 必须能直接照抄**：第 2 步不能再只放一条裸 `bootstrap.sh`。必须同时给出路径 A（sudo + `--uid 1000`）与路径 B（显式当前 UID + 本地 `yp-builder:local`），并说明路径 B 需先按 runbook §5.2 构建镜像。
2. **宿主机不是“只装 Docker”**：除 Docker 外，clone 需要 `git`，fetch/verify 需要 `bash`、`python3`、`curl`、`tar`、`sha256sum`。文档要如实列出，`verify-env.sh` 要在最前面检查，缺依赖不得再被报成 registry/网络 401。
3. **路径 B 的镜像变量必须自包含**：runbook 步骤 7 与 test prompt §5 都必须通过 `IMAGE="${YP_BUILDER_IMAGE:-...}"` 解析，路径 B 要明确“同一 shell export”或直接把该行设为 `yp-builder:local`；不能出现新开 shell 后静默回退 GHCR 1000 的情况。
4. **官方流程固定仓库根目录 `.`**：步骤 4/7 的 `.` 与 `$PWD` 保持一致；§4 手工恢复里的 `DEST_PARENT` 只用于手工恢复，明确标注不得与步骤 7 混用。不要为了手工变量改官方流程。
5. **RV-016 只更正、不改写历史**：V11 按实际 CI 状态回填（gate success、publish 未完成则仍 `UNVERIFIED`）；V3/V4 的“残留仅 N 处”改为“当前验收无命中；历史/更正/提示词指令仍有字样”，不改变原 PASS 结论。
6. **不下载 11 GiB、不重传 release、不改 manifest 字节/哈希、不在真实缓存上试 `--force`、不跑 `--mode ghcr`**。K-8 仍是 P3 可选项，不在本轮修。
7. 提交身份只用 `zeek.zhao <zeek.zhao@foxmail.com>`，无 AI 署名；token 不入库、不落盘；所有“通过”必须有本轮真实输出，没跑的写 `UNVERIFIED`。

## 1. 开工先复现（只读，不下载）

```bash
git clone --branch feat-m0-kas-bootstrap https://github.com/zeek-zhao/yp-distro.git
cd yp-distro
git rev-parse HEAD && git log --oneline -3 && git status --short
bash scripts/gate.sh
bash scripts/check-vars.sh
```

记录以下基线，证明问题存在：

```bash
grep -n "bash scripts/bootstrap.sh" README.md
grep -n "只装 Docker" README.md docs/runbook-new-machine.md
grep -n "docker run --rm ghcr" docs/ai/m0-new-machine-test-prompt.md
grep -n "DEST_PARENT\|\$PWD/downloads\|\$PWD/sstate" docs/runbook-new-machine.md
```

在 UID 不是 1000 的普通用户下做隔离探针（只在临时目录，不碰正式卷；root 可建 `uid1234` 普通用户，记录 `uid=0`）：

```bash
rm -rf /tmp/uid7 && mkdir -p /tmp/uid7
bash scripts/bootstrap.sh --downloads /tmp/uid7/dl --sstate /tmp/uid7/sstate --min-free-bytes 0
echo "DEFAULT_BOOT_RC=$?"

bash scripts/bootstrap.sh --downloads /tmp/uid7/dl --sstate /tmp/uid7/sstate \
  --min-free-bytes 0 --uid "$(id -u)" --gid "$(id -g)"
echo "EXPLICIT_BOOT_RC=$?"

bash scripts/preflight.sh --downloads /tmp/uid7/dl --sstate /tmp/uid7/sstate \
  --min-free-bytes 0 --uid "$(id -u)" --gid "$(id -g)"
echo "EXPLICIT_PF_RC=$?"
```

预期：`DEFAULT_BOOT_RC=2` 且打印 `UID_MISMATCH`；显式两条均 `0`，属主为当前 UID。若 `bootstrap` 报 `LOW_SPACE`，是临时目录空间不足，换大目录或加 `--min-free-bytes 0` 重跑，UID 检查应通过。

## 2. 工作项

### T1 · README 快速开始的 UID 分支

文件：`README.md`

当前第 2 步只有：

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate
```

UID≠1000 的机器照抄会 `exit 2 UID_MISMATCH`。必须改成两条**二选一**的分支，并保留“先 fetch、若已先 bootstrap 则 fetch 后重跑”的顺序说明。两条命令必须放在**两个独立代码块**里，不能放在同一个可整体复制执行的块中：

```bash
# 2. 先按 runbook §3 步骤 4 取回缓存（目标为空，无需 --force），再归一属主。
#    若已先 bootstrap，fetch 后必须重跑本步——root 解包会把属主变为归档 UID。
```

**路径 A（二选一；当前 UID=1000 或 root，卷保持镜像 1000）**

```bash
sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid 1000 --gid 1000
```

**路径 B（二选一；当前 UID≠1000，卷保持当前 UID；先按 runbook §5.2 构建 yp-builder:local）**

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
```

同时：

- 第 1 步 `docker pull` 下补一句：路径 B 可跳过本行，改用 runbook §5.2 的本地镜像；不要把 GHCR 1000 镜像用于路径 B 构建。
- 不要在 README 第 2 步保留“只有裸 bootstrap”的另一条路径；只保留上述两条，并明确“二选一，不要顺序执行两条”。
- 不要复制 fetch 的完整命令，避免与 runbook 漂移；保留“入口在 runbook §3 步骤 4”的指向。

### T2 · 宿主机前置依赖

文件：`README.md`、`docs/runbook-new-machine.md`、`scripts/verify-env.sh`

事实：README 目标与 runbook §1 都写“宿主机只装 Docker”，但实际：

- `git clone` 需要 `git`；
- `fetch-cache.sh` 的 `command -v python3` 是硬依赖；
- 下载用 `curl`，解包用 `tar`，校验用 `sha256sum`；
- `verify-env.sh` 目前只显式检查 Docker/curl；缺 `python3` 时会在 registry token 解析处失败，输出会被误读成“网络/代理/401”。

必须改：

1. README 目标段的“只装 Docker 的机器……”改为“宿主机需要 Docker + git/bash/python3/curl/tar/sha256sum；不需要 kas/bitbake。Ubuntu 24.04 默认具备大部分，缺失见 runbook §1”。“三步上手”开头那句同样不要再说“宿主机只需要 Docker”。
2. runbook §1 表格增加“宿主工具”行，列出 `git`、`bash`、`python3`、`curl`、`tar`、`sha256sum`；说明它们是 fetch/verify/clone 的前置，不要求版本锁定，但必须存在。
3. `scripts/verify-env.sh` 在 `ENV PRECHECK` 输出之后、Docker 检查之前增加“0) 宿主依赖”段：

```bash
# 0) 宿主依赖（fetch/verify/clone 需要；缺 python3 不得落到 registry 401）
for c in git bash python3 curl tar sha256sum; do
  if command -v "$c" >/dev/null 2>&1; then
    pass "DEP $c=$(command -v "$c")"
  else
    fail "DEP_MISSING $c（fetch/verify/clone 需要；先安装再继续）"
  fi
done
```

4. 该段必须在 registry 探测之前执行；缺 `python3` 时输出首行应是 `FAIL DEP_MISSING python3`，不能只报“无法取得 ghcr token（网络/代理/401）”。
5. 不改 `verify-env.sh` 的退出码语义：仍为 0 全通过 / 1 致命 / 2 警告；依赖缺失计入 `FAIL_N`，最终 `ENV_FAIL`。

### T3 · 路径 B 的镜像变量自包含

文件：`docs/runbook-new-machine.md`、`docs/ai/m0-new-machine-test-prompt.md`

当前 runbook 步骤 7 已有：

```bash
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
```

但路径 B 的 `export` 在 §5.2，若用户新开 shell 直接跑步骤 7，变量会静默回退 GHCR 1000，和 1234 的卷不匹配。必须：

- 步骤 7 的 `IMAGE` 行上方加注释：

```bash
# 路径 B：必须在同一 shell 先 export YP_BUILDER_IMAGE=yp-builder:local；
# 若跨 shell，直接把下一行改为 IMAGE=yp-builder:local。
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
```

- `docs/ai/m0-new-machine-test-prompt.md` §5 的“拉取 builder 镜像并核对身份”不要写死 GHCR：

```bash
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
docker run --rm "$IMAGE" sh -c 'whoami; id -u; kas --version'
```

路径 B 应核对自己构建的 `yp-builder:local`；路径 A 才核对 GHCR 的 `jenkins/1000` 基线。

- §4.2 的路径 B 已 `export YP_BUILDER_IMAGE=yp-builder:local`，补一句“后续 §7/§9 若另开 shell，必须重新 export，或直接把步骤 7 的 `IMAGE` 设为 `yp-builder:local`”。

### T4 · DEST_PARENT 的官方/手工边界

文件：`docs/runbook-new-machine.md`

当前官方步骤 4 固定 `--dest-parent .`，步骤 7 固定挂 `$PWD/downloads`、`$PWD/sstate`；§4 手工恢复又定义了 `DEST_PARENT`。用户若在 §4 自定义后继续步骤 7，会挂错目录。本轮不要求把官方流程改成自定义变量，但必须明确边界：

- 在 §4 的 `DEST_PARENT="${DEST_PARENT:-.}"` 上方或下方加一句：

```text
本节 DEST_PARENT 仅用于手工恢复；官方步骤 4/7 固定使用仓库根目录 `.`。
不要把这里的自定义值带入步骤 7；若确要自定义，必须同步修改步骤 7 的两个 -v 挂载。
```

- 步骤 4/7 不要出现第二套变量；保持 `--dest-parent .` 与 `$PWD/...` 一致。
- 如果执行方选择改成统一 `DEST_PARENT`，必须同时改步骤 4、步骤 7 的挂载，并在 RV-017 记录；不要只改一处。

### T5 · 记录收口

新建（先查重，按现有编号续号）：

- `docs/m0/issues/ISS-033.md`：P2，README 第 2 步仍只有裸 `bootstrap`，UID≠1000 照抄 exit 2；关联 README 第 2 步、runbook §5.2。
- `docs/m0/issues/ISS-034.md`：P2，README/runbook 宣称“只装 Docker”，实际 fetch/verify/clone 依赖 git/bash/python3/curl/tar/sha256sum；`verify-env` 缺依赖会误报 registry 401。
- `docs/m0/issues/ISS-035.md`：P3，路径 B 镜像变量跨 shell 静默回退、test prompt §5 仍验 GHCR 镜像、`DEST_PARENT` 官方/手工边界不清、RV-016 V11/V3/V4 记录精度。
- `docs/m0/changes/CHG-019.md`：本轮 README/前置依赖/路径 B 文档收口；状态 `Approved`（本提示词 §0 已定），明确不改 release 资产、不改 acceptance 判据、不修 K-8。
- `docs/m0/reviews/RV-017.md`：本轮验证记录，逐条列命令、输出、UNVERIFIED。

每个新建 ISS 在对应验证项通过后改为 `Closed`，附关闭条件与证据；未通过的保持 `Reopened`/`Verifying`，不要为了收口提前关闭。

修改：

- `docs/m0/reviews/RV-016.md`：文首加更正块，不改 V1–V10 历史结论：
  - V11：按实际 CI 回填。gate 若 success 写 `gate=success`；publish 若仍 `in_progress` 写 `publish=UNVERIFIED（publish-builder 未完成）`；只有 publish run 真正 `completed/success` 才写 success。
  - V3/V4：改为“当前验收判据无命中；历史/更正/提示词指令中仍有字样”，不再写“仅 N 处”。
- `docs/m0/plan.md`：新增 v2.17，记录 CHG-019 / ISS-033 / ISS-034 / ISS-035 / RV-017；不要改写 v2.16 历史。
- `docs/m0/traceability.md`：新增本轮行，写“已验证 V1–V8；真实全量/GHCR/K-8 仍 UNVERIFIED”。
- `docs/m0/deviations.md`：如本轮仍未跑全量/`--mode ghcr`，登记 #6，说明不阻塞文档收口；不要冒充已跑。

### T6 · 验证矩阵（不下载全量）

| # | 验证 | 期望 |
|---|---|---|
| V1 | README 第 2 步检索 | 同时出现路径 A（`--uid 1000 --gid 1000`）与路径 B（`--uid "$(id -u)" --gid "$(id -g)"`）；没有唯一一条裸 bootstrap |
| V2 | UID 1234 隔离探针 | 默认裸 bootstrap exit 2 `UID_MISMATCH`；路径 B 显式 `--uid/--gid` bootstrap + preflight 均 exit 0；路径 A 以 root `--uid 1000` 也 exit 0 |
| V3 | `verify-env.sh` 依赖段 | 正常跑打印 `DEP git/bash/python3/curl/tar/sha256sum`；`DEP_MISSING` 在 registry 探测之前；正常结果仍 `ENV_OK` 或 `ENV_WARN`，不得新增 FAIL |
| V4 | 路径 B 镜像变量 | runbook 步骤 7 与 test prompt §5 都用 `IMAGE="${YP_BUILDER_IMAGE:-...}"` + `"$IMAGE"`；§4.2 有同一 shell/重新 export 说明 |
| V5 | `DEST_PARENT` 边界 | 官方步骤 4/7 仍固定 `.`；§4 有“仅手工恢复、不得带入步骤 7”的限定；无第二套未同步变量 |
| V6 | RV-016 更正 | 文首有更正块；V11 按实际 CI 状态；V3/V4 不再写“仅 N 处” |
| V7 | `bash scripts/gate.sh` / `check-vars.sh` | `GATE_PASS` / `VARS_OK checked=28 drift=0` |
| V8 | token 扫描 | `NO_TOKEN_IN_REPO`（无 `github_pat_` 明文） |
| V9 | CI | 新提交 gate 与 publish 的实际 run；publish 未完成写 `UNVERIFIED`，不得用本地 gate 代替远端 |
| V10 | release 不变 | 不重传、不改资产；manifest `expected_bytes=11153387520`、8 assets 不变（只读核对即可） |

真实 8 片重组、`--mode ghcr` 全链路、真实 11 GiB 正常顺序重下仍不要求本轮跑；在 RV-017 §5 写 `UNVERIFIED` 与复验方法。若机器上已有 `cache-work/cache-full.tar` 与 8 个分片，可额外做一次本地 `unpack-only`，但不得重新下载。

## 3. 提交与回报

提交前：

```bash
git status --short
git diff --stat
bash scripts/gate.sh
bash scripts/check-vars.sh
git grep -nE 'github_pat_[A-Za-z0-9_]{20,}' || true
```

提交信息建议：

```text
fix(m0): close README UID, host prereq and path-B doc gaps

Refs: YP-M0-CHG-019 / YP-M0-ISS-033 / YP-M0-ISS-034 / YP-M0-ISS-035 / YP-M0-RV-017
Doc: docs/m0/changes/CHG-019.md
```

推送后，回报必须包含：

```text
MACHINE: os=... uid=... docker=...
HEAD: <起点> -> <本轮提交>
REPRO: default_boot_rc=... explicit_boot_rc=... explicit_pf_rc=...
DEPS: git=... bash=... python3=... curl=... tar=... sha256sum=...
CHANGED: <文件清单>
V1..V10: <命令与关键输出；失败写 FAIL/UNVERIFIED>
CI: gate=<url/run> publish=<url/run> status=<success|in_progress|failure>
TOKEN: NO_TOKEN_IN_REPO
VERDICT: PASS（文档收口）| PARTIAL | FAIL
UNVERIFIED: <逐条>
```

`VERDICT=PASS（文档收口）` 的条件：V1–V8 全过；V9 若 publish 未完成写 `UNVERIFIED`，不能写成成功；V10 只读核对通过。真实全量/GHCR/K-8 未跑不阻塞，但必须写清。

## 4. 明确禁止

- 不下载 11 GiB，不重传/删除 release 资产，不改 `expected_bytes`、`assets[].size`、`checksum_asset_sha256`。
- 不把 README 改回“只装 Docker”的旧说法；不省略 `python3`/`tar`/`sha256sum` 依赖检查。
- 不在路径 B 的步骤 7 继续使用 GHCR `wrynose-m0`；`$YP_BUILDER_IMAGE` 必须能解析到本地镜像。
- 不在 `DEST_PARENT` 上同时保留“官方固定 `.`”和“手工自定义”却不加边界说明。
- 不把 publish 的 `in_progress` 写成 success；不把本地 gate 冒充远端 CI。
- 不在真实缓存上试 `--force`；不删除 `.yp-volume`；不用 root 跑构建。
- **K-8 的边界**：v1.0 已执行期间不修；v1.1 下一轮 E3 才修，且只在独立新机验证，不在审核机下载 11 GiB。

---

## 5. 本轮收口（只动记录/文档，不动脚本）

> 这一节是 v1.1 的 Phase 0。完成后提交、打 `m0.0`、建分支，然后停止等评审；不要顺手开始 §6。

### 5.1 · `RV-017` 文首更正块

在 `docs/m0/reviews/RV-017.md` 的表格之后、§1 之前加（不要改 V9 原行）：

```markdown
> **2026-11-26 推送后更正（AI-007 v1.1）**
>
> 归档时点 V9 写 UNVERIFIED，保留为历史快照。实际推送后：
> 提交 50893a9 的 gate run 45803774082 = completed/success；
> 50893a9 的 publish 未被触发（m0.yml paths 仅 docker/**、scripts/cache/**、kas/**；
> 本轮只改 README/docs/verify-env），publish 仍 UNVERIFIED，不是失败。
> 旧 publish run 45799521429（AI-006 1d1ddb6）4 job success，与本轮 publish 无关。
```

验收：`grep -n "45803774082\|未被触发\|45799521429" docs/m0/reviews/RV-017.md` 三处命中；V9 原行仍在。

### 5.2 · `CHG-019` errata

在 `docs/m0/changes/CHG-019.md` 文首加：

```markdown
> **Errata（2026-11-26，AI-007 v1.1）**
>
> 本文“变更后”段写于 AI-006 publish 尚未完成时；实际 45799521429 的 4 个 job 已全部 success。
> AI-007 的 50893a9 是纯文档提交，publish 未被 paths 触发，不能写成“publish success”。
> 旧行保留为历史，最终状态以本 errata 与 RV-017 更正块为准。
```

### 5.3 · `RV-016` 指针同步

在 `docs/m0/reviews/RV-016.md` 文首更正块补一行：

```markdown
> AI-007 50893a9 的 CI 不在 V11 范围内：gate 45803774082 success；publish 因 paths 未触发，
> 当前状态见 RV-017 文首更正块。V11 只描述 AI-006 1d1ddb6 的 45799521429。
```

### 5.4 · `plan` / `traceability` / `deviations`

1. `docs/m0/plan.md` 追加 v2.18：M0.0 冻结提交；gate `45803774082` success；`50893a9` publish 未触发（paths）；tag `m0.0` 指向本轮更正提交；不改 Step 表既有状态。
2. `docs/m0/traceability.md` 最后一行状态改为：V1–V8、V10 已验证；V9 gate success / publish 未触发；真实全量、8 片重组、`--mode ghcr`、GHCR 源 tar 布局、K-8 仍 `UNVERIFIED`。
3. `docs/m0/deviations.md` 追加 `#7`：AI-007 纯文档提交不触发 publish，是 paths 设计结果，不是 CI 失败；不作为异常偏差。

### 5.5 · `sudo` 文档缺口

只改文档，不改 `verify-env.sh` 业务逻辑：

1. `README.md` 宿主工具段：`Docker + git / bash / python3 / curl / tar / sha256sum`；路径 A 另需 `sudo`，路径 B 不需要；root 可去掉 `sudo` 直接执行；UID=1000 非 root 且无 `sudo` 时走路径 B。
2. `docs/runbook-new-machine.md` §1「宿主工具」行补同样一句；§5.2 路径 A 补“root 可去 sudo；无 sudo 走 B”。
3. `docs/ai/m0-new-machine-test-prompt.md` 若路径 A 有 `sudo`，补同样一句。
4. 不为 `verify-env` 增加 `sudo` 检查；`sudo` 不是所有路径的硬依赖。

### 5.6 · 门禁、提交、`m0.0`、分支

```bash
git status --short
git diff --stat
bash scripts/gate.sh          # 期望 GATE_PASS
bash scripts/check-vars.sh    # 期望 VARS_OK drift=0
grep -RInE 'github_pat_|ghp_' . --exclude-dir=.git || true
```

提交标题：`docs(m0): freeze M0 with CI correction and portability plan`

```text
Refs: YP-M0-RV-017 / YP-M0-CHG-019 / YP-M0-RV-016
Doc: docs/ai/m0-readme-prereq-and-pathb-closeout-prompt.md
```

身份 `zeek.zhao <zeek.zhao@foxmail.com>`，无 AI 署名。**tag 必须打在本轮更正提交上，不得打在 `50893a9` 或提示词提交上**：

```bash
git tag -a m0.0 -m "M0.0 doc freeze: criteria 1-8 pass; residual UNVERIFIED in RV-017; M0.1 closed next"
git push origin m0.0

git branch release-m0.0 m0.0
git push origin release-m0.0
git branch feat-m0.1-evidence m0.0
git push origin feat-m0.1-evidence

git ls-remote origin refs/tags/m0.0 refs/tags/m0.0^{} refs/heads/release-m0.0 refs/heads/feat-m0.1-evidence
git rev-parse m0.0^{}
```

`m0.0` 是纯文档冻结，publish 不应被触发；不要为了“让 tag 也有 publish”而强行 dispatch 或改 paths。tag 指向已经 gate 绿的更正提交；不 `--force`、不移动/删除 tag。远端有新提交先 rebase，有冲突立即停止报告。

### 5.7 · 本轮报告

回报：改动文件、执行命令、已验证/未验证项、tag 与两个分支的远端 SHA、gate run。明确写“§6 未开工”。

---

## 6. 下一轮 M0.1 证据闭环（评审通过后执行）

### 6.1 边界

- 分支：`feat-m0.1-evidence`，基点 `m0.0`。
- 只做证据闭环，不新增功能、不碰 `main`、不改 M0 Final 结论。
- 建议新建 `docs/m0.1/`：`plan.md`、`design/`、`reviews/RV-018.md`、`changes/CHG-020.md`、`issues/ISS-036.md`、`acceptance.md`；M0 记录只加指针。编号顺延 `DES-010`/`RV-018`/`CHG-020`/`ISS-036`，不跳号。
- 真实全量测试只在独立新机（Ubuntu 24.04、Docker、≥300 GB 可用）执行；审核机不下载 11 GiB。

### 6.2 E1 · 真实 release 全量正常顺序（最高优先）

从 `m0.0` clone 到独立新机：

1. `verify-env.sh`，记录 `ENV_OK/ENV_WARN/ENV_FAIL` 与 `fail/warn` 计数。
2. 按 runbook §3 步骤 4 取 release `m0-s5-payload-full` 的 8 个分片：
   - 目标为空，**不得 `--force`**；
   - 必须走 `fetch-cache` 默认 `requires_reassembly=true` 的 8 片重组；
   - 记录 `REASSEMBLE_OK bytes=11153387520`、`SHA256_OK=1c8126d4…`。
3. 按路径 A（`sudo --uid 1000`）或路径 B（显式当前 UID + `yp-builder:local`）bootstrap。
4. `preflight`。
5. 记录 `STRUCT_OK mode=direct downloads=1288 sstate=6945`。
6. 保存命令、日志、耗时、磁盘峰值；不得手工 `tar` 替代 fetch。

通过条件：以上四项输出齐全，且没有 `--force`、没有手工改归档。

### 6.3 E2 · 8 片重组边界

- 同一 manifest 下 `--parts 1` 必须 exit 1。
- 用 `unpack-only` 对已重组 tar 做布局探测，确认 direct 单层；记录 `STRUCT_OK`。
- 若 `requires_reassembly` 缺失回退旧逻辑，单独记录回退用例，不混入主证据。

### 6.4 E3 · `--mode ghcr` 全链路 + K-8

在独立新机、目标为空、不得 `--force`：

1. 修 `fetch-cache.sh`：
   - `check_target` 移到 `docker pull` 循环之前（非空目标在下载前失败）；
   - manifest 有 `digest` 时按 digest 拉取（`docker pull "$im@$dg"`），不只按 tag；
   - 拉取后校验 `docker image inspect` 的 `RepoDigests` 与 manifest digest；缺失 digest 才回退 tag，并记 `DIGEST_FALLBACK`；
   - 不改分片 `bytes`/`sha256`/`digest`。
2. 执行 `--mode ghcr --manifest manifests/full-slices-manifest.json`，记录 `SLICE_OK`、`merge`、`SHA256_OK=a8870b50…`、`STRUCT_OK`。
3. 实际确认 GHCR 源 tar（`a8870b50…`）布局；若确认，更新 `full-slices-manifest.json` 的 `layout`/`layout_note`，**不得改 `total_bytes`、分片字节、sha256、digest**；无法确认则保持 `UNVERIFIED`。
4. 记录匿名 pull 的 digest；需要认证时说明原因，token 不落盘。

### 6.5 E4 · 发布 CI 观察

- E3 改 `scripts/cache/**`，push 后 `m0.yml` restricted push 应触发 publish；核对 4 个 job（`prepare-cache-payload`、`publish-cache`、`publish-cache-slices`、`publish-builder`）真实状态。
- 未触发就用 `workflow_dispatch` 触发一次；记录 run id/head_sha/每个 job 结论。
- 只跑 sample 写“sample 通过”，不得写 full 通过；全量以 E1 为准。

### 6.6 E5 · 记录与 `m0.1`

- 新建 `RV-018`：E1–E4 命令、真实输出、未验证项与复验方法。
- 新建 `CHG-020`：K-8 的 digest 拉取/前置 `check_target` 变更；若改 `layout`，同单记录依据。
- 新建 `ISS-036`：E3/E4 有新问题先开单再修；没有就不硬造。
- 更新 M0.1 `plan`/`traceability`/`acceptance`；M0 的 `acceptance.md` 不改 Final 结论，只加指针。
- 通过后：

```bash
git tag -a m0.1 -m "M0.1 evidence closure: E1-E4 real evidence; residual list updated"
git push origin m0.1
git branch release-m0 m0.1
git push origin release-m0
```

### 6.7 M0.1 出口

E1 的真实 8 片正常顺序全量、E2 的 `--parts 1` 拒绝与 direct、E3 的 ghcr/K-8、E4 的 publish 4 job、E5 的记录与门禁，全部有真实输出或明确 `UNVERIFIED`；不得用本地检查冒充远端，不得 sample 冒充 full。

### 6.8 M1 入口

只有 `m0.1` 打完后，才从 `m0.1` 拉 `feat-m1-<scope>`；M1 功能范围必须先按 PRD/新 DES 评审，本文件不定义 M1。不要从会漂移的 `feat-m0-kas-bootstrap` 拉 M1。

---

## 7. 分支与标签路线

| 阶段 | 分支 | 标签 | 出口 |
|---|---|---|---|
| M0 文档冻结 | `feat-m0-kas-bootstrap` → 更正提交 | `m0.0` | 记录更正；gate/vars；`release-m0.0`；`feat-m0.1-evidence` |
| M0.1 证据闭环 | `feat-m0.1-evidence`（基于 `m0.0`） | `m0.1` | E1–E5；`release-m0`；可进入 M1 |
| M1（未开始） | `feat-m1-<scope>`（基于 `m0.1`） | `m1.0` | PRD/范围先评审；本文件不定义功能 |

规则：`m0.0` 只打一次、不移动；`release-m0.0` 是不可变快照；`m0.1` 只打一次，`release-m0` 指向 `m0.1`；所有下一轮分支从标签拉，不从会漂移的旧分支拉；不 `--force`、不删除/移动 tag。

## 8. 完成后回报

1. 改动文件清单；2. 执行命令清单（含 tag/branch/push/CI 查询）；3. 已验证项（真实输出/run id）；4. 未验证项及原因；5. 新增/更正记录编号；6. 下一步建议。

§5 完成后只回报 §5，不要顺手开始 §6。
