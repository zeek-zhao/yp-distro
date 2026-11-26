# YP-M0 README / 宿主依赖 / 路径 B 文档收口 · AI 执行提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-007 |
| 版本 | v1.0 |
| 日期 | 2026-11-26 |
| 适用仓库 | `https://github.com/zeek-zhao/yp-distro`，分支 `feat-m0-kas-bootstrap` |
| 编写时 HEAD | `1d1ddb6`（本轮提示词提交后 HEAD 会多一条 docs/ai 提交；开工以 `git rev-parse HEAD` 为准） |
| 目标 | 把 README 快速开始的 UID 分支、宿主机前置依赖、路径 B 的镜像变量自包含、`DEST_PARENT` 的官方/手工边界、RV-016 的 CI 记录收口；不重传、不下载 11 GiB、不改发布资产 |
| 不在范围 | 真实全量重下、`--mode ghcr` 全链路、K-8 代码重构、改构建配置、改 acceptance 判据、改 release 资产 |

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
- 不在真实缓存上试 `--force`；不删除 `.yp-volume`；不用 root 跑构建；不修 K-8。
