# YP-M0 换机 UID 路径与文档一致性收口 · AI 执行提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-006 |
| 版本 | v1.0 |
| 日期 | 2026-11-26 |
| 适用仓库 | `https://github.com/zeek-zhao/yp-distro`，分支 `feat-m0-kas-bootstrap` |
| 编写时 HEAD | `35c4119`（开工以 `git rev-parse HEAD` 为准；若已前进，先读最新 plan/runbook/RV-015） |
| 目标 | 把 `35c4119` 上仍会卡住新机的 UID≠1000 路径、当前测试提示词的旧判据、GHCR 布局口径和记录状态收口；不重传、不下载 11 GiB、不改发布资产 |
| 不在范围 | 改构建配置、改发布产物、改已 Final 的 acceptance 判据、真实全量重下、`--mode ghcr` 实跑、K-8 代码重构 |

## 0. 角色、边界与已定决策

你是本轮**文档与命令收口执行方**。以下决策已确定，不要重新做方案对比：

1. **路径 A**（sudo、卷保持 1000）：`bootstrap` 与 `preflight` 都必须显式 `--uid 1000 --gid 1000`，并以 sudo 执行。
2. **路径 B**（本地重建镜像、卷保持当前 UID）：`bootstrap` 与 `preflight` 都必须显式 `--uid "$(id -u)" --gid "$(id -g)"`；只写 `--build-arg` 重建镜像不够，因为脚本默认目标仍是 1000，会直接 exit 2。
3. **构建步骤必须使用镜像变量**：`IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"`，`docker run` 用 `"$IMAGE"`；不能把 GHCR 镜像写死，否则路径 B 的 1234 卷会配上 1000 容器。
4. **当前测试入口的判据必须是 direct**：release 归档单层解包，`STRUCT_OK mode=direct`；不得再写“两层解包”。
5. **GHCR 源 tar 布局是 `UNVERIFIED`**：只有 `pack.sh` 本地产出确定为 two-stage；GHCR 源 tar 不得再断言 two-stage。
6. **ISS-029 按既有事实关闭**：其关闭条件（runbook §4/RV-013 与 direct 实物一致）已满足；真实全量重下未跑属于 RV-015 §5 的残留，不要拿它阻塞 ISS-029。
7. 不改 `acceptance.md` 的判据结论与字节；不改 release 资产；不下载 11 GiB。

硬约束：只用 `zeek.zhao <zeek.zhao@foxmail.com>` 提交，无 AI 署名；token 不入库；不得在真实缓存上试 `--force`；所有“通过”必须有本轮输出，没跑的写 `UNVERIFIED`。

## 1. 开工先复现（只读，10 分钟）

```bash
git clone --branch feat-m0-kas-bootstrap https://github.com/zeek-zhao/yp-distro.git
cd yp-distro
git rev-parse HEAD && git log --oneline -3 && git status --short
```

在 UID 不是 1000 的普通用户下做隔离探针（只在 `/tmp`，不碰正式卷；root 可跳过，但要记录 `uid=0`）：

```bash
rm -rf /tmp/uid6 && mkdir -p /tmp/uid6
bash scripts/bootstrap.sh --downloads /tmp/uid6/dl --sstate /tmp/uid6/sstate --min-free-bytes 0
echo "DEFAULT_BOOT_RC=$?"

bash scripts/bootstrap.sh --downloads /tmp/uid6/dl --sstate /tmp/uid6/sstate \
  --min-free-bytes 0 --uid "$(id -u)" --gid "$(id -g)"
echo "EXPLICIT_BOOT_RC=$?"

bash scripts/preflight.sh --downloads /tmp/uid6/dl --sstate /tmp/uid6/sstate \
  --min-free-bytes 0 --uid "$(id -u)" --gid "$(id -g)"
echo "EXPLICIT_PF_RC=$?"
```

预期：

- `DEFAULT_BOOT_RC=2`，打印 `UID_MISMATCH`（默认 1000 与当前 UID 不符）；
- `EXPLICIT_BOOT_RC=0`，属主为当前 UID；
- `EXPLICIT_PF_RC=0`（若仅 `LOW_SPACE` 说明 `/tmp` 空间不足，改用 `--min-free-bytes 0` 重跑；UID 检查应通过）。

同时记录以下基线，证明问题存在：

```bash
grep -n "bash scripts/preflight.sh" docs/runbook-new-machine.md
grep -n "bash scripts/bootstrap.sh\|bash scripts/preflight.sh" docs/ai/m0-new-machine-test-prompt.md
grep -n "两层解包" docs/ai/m0-new-machine-test-prompt.md
grep -rn "GHCR.*two-stage\|GHCR 源 tar.*two-stage" README.md docs/runbook-new-machine.md docs/m0 docs/ai
```

## 2. 工作项

### T1 · runbook 的 UID 路径与构建镜像

文件：`docs/runbook-new-machine.md`

必须改：

- 步骤 5 的 `bootstrap`：明确分两条路径。路径 A 用 `sudo ... --uid 1000 --gid 1000`；路径 B 用 `... --uid "$(id -u)" --gid "$(id -g)"`。不要把默认 1000 当成路径 B 的默认值。
- 步骤 6 的 `preflight`：路径 A 用 `sudo ... --uid 1000 --gid 1000`；路径 B 用 `... --uid "$(id -u)" --gid "$(id -g)"`。当前裸 `preflight` 在 UID 1234 上会直接 exit 2。
- §5.2 的两条路径：把 §1 的两组命令补完整；路径 B 必须显式 UID，且说明“重建本地镜像后，bootstrap/preflight 仍要显式 `--uid $(id -u)`，因为默认值来自 threshold.conf 的 1000，不会读镜像”。
- 步骤 7 的 `docker run`：改为
  ```bash
  IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
  docker run -d --name yp-m0-build \
    -v "$PWD:/mnt/repo:ro" \
    -v "$PWD/downloads:/work/downloads" \
    -v "$PWD/sstate:/work/sstate" \
    "$IMAGE" sleep infinity
  ```
  并在路径 B 处明确：`docker pull` 的 GHCR 镜像不用于构建，构建容器必须用 `yp-builder:local`。
- 步骤 3 的 pull 说明：路径 B 可跳过 GHCR pull，或保留仅作对照；不要让读者误以为路径 B 仍跑 GHCR 镜像。

验收：在 UID 1234 下按 runbook 路径 B 的完整命令（`/tmp` 探针）能走到 `preflight` 的 UID 检查通过；在路径 A 下 `sudo bootstrap`/`sudo preflight` 的 `--uid 1000` 版本能通过 UID 检查。

### T2 · 当前测试提示词

文件：`docs/ai/m0-new-machine-test-prompt.md`

- §4.2 路径 B 的 `bootstrap` 与 `preflight` 全部补 `--uid "$(id -u)" --gid "$(id -g)"`；不要保留“默认 1000 会按当前用户”的误导。
- §4.2 路径 B 明确：`docker run` 必须用 `$YP_BUILDER_IMAGE`（`yp-builder:local`），不能用 GHCR 的 `wrynose-m0`。
- 通过判据 §12 第 4 条把“两层解包 `STRUCT_OK`”改为“单层解包 `STRUCT_OK mode=direct`”；搜索全文，确认不再有“两层解包”作为当前验收要求。
- 如果 `K-5` 表仍写 `--parts` 对 two-stage 的旧缺陷，补一句“已由 CHG-017 改为 `requires_reassembly` 判断并显式拒绝”，避免读者以为未修。

### T3 · GHCR 源 tar 口径统一为 UNVERIFIED

文件：`docs/runbook-new-machine.md`、`docs/m0/changes/CHG-012.md`、`docs/m0/changes/CHG-017.md`、`docs/m0/issues/ISS-029.md`、`docs/ai/m0-portability-prompt.md`、`scripts/cache/fetch-cache.sh` 头部注释。

把所有“GHCR 源 tar 为 two-stage”改成：

```text
pack.sh 本地产出 = two-stage；GHCR 源 tar（a8870b50…）布局 = UNVERIFIED（未拉取验证）
```

重点位置：

- `runbook` §4 的历史背景句与 §7 事实核对句（“pack.sh 本地 / GHCR 源 tar 为 two-stage”自相矛盾）；
- `CHG-012` 文首更正块；
- `CHG-017` §1 的“pack.sh 本地/GHCR 源 tar 为 two-stage”；
- `ISS-029` §8 的“pack.sh+GHCR two-stage”；
- `m0-portability-prompt.md` 历史横幅；
- `fetch-cache.sh` 头部“GHCR 源 tar 为 two-stage”。

不要改 `full-slices-manifest.json` 的 `layout=UNVERIFIED` 与既有 digest；不要伪造 GHCR 源 tar 的布局。

### T4 · README 快速开始的顺序

文件：`README.md`

当前第 2 步只有 `bootstrap`，但正文要求先 fetch；root 用户先 bootstrap、后 fetch 会把归档的 1750 属主带进卷，`check_target` 会放行但不会自动再 chown。

改成以下任一，优先 A：

A. 在代码块第 2 步前加一行可执行的 fetch 引用/命令（不复制完整参数，避免漂移）：
```bash
# 2. 先按 runbook §3 步骤 4 取回缓存（目标为空时无需 --force）
# 3. 再归一属主
bash scripts/bootstrap.sh ...
```

B. 至少明确写：“若已先执行 bootstrap，fetch 后必须重跑 bootstrap；root 解包会把属主变为归档 UID。”

不要保留“取回缓存后再归一属主”但代码块只有 bootstrap、无 fetch 的歧义。

### T5 · runbook §4 与零散事实

文件：`docs/runbook-new-machine.md`、`scripts/bootstrap.sh`、`docs/ai/m0-portability-closeout-prompt.md`

- §4 的手工解包命令补变量：
  ```bash
  DEST_PARENT="${DEST_PARENT:-.}"
  tar -xf cache-full.tar -C "$DEST_PARENT"
  ```
  或在命令中直接写 `-C .`，确保复制可执行。
- §3 步骤 4 的期望输出 `ASSET_OK index=NN` 改为实际字段 `ASSET_OK name=cache-full.part-NN`。
- `scripts/bootstrap.sh:4` 的注释仍写“默认取当前用户”，改为“默认取镜像用户 JENKINS_UID/JENKINS_GID（CHG-014）”；不改逻辑。
- `docs/ai/m0-portability-closeout-prompt.md` 文首加 errata：§1.2 的 `pack.sh --downloads/--sstate` 参数有误，真实参数是 `--src`；§1.3 的 `unpack-only` 需要 `--work`。不要重写正文冒充原来正确。

### T6 · 记录收口

新建（按现有编号查重后续号）：

- `docs/m0/issues/ISS-031.md`：P1，UID≠1000 路径 B 的 bootstrap/preflight/构建镜像命令不可执行；关联 runbook §5.2、test prompt §4.2。
- `docs/m0/issues/ISS-032.md`：P2，当前测试判据仍写“两层解包”、GHCR 布局多处误写 two-stage。
- `docs/m0/changes/CHG-018.md`：本轮文档/命令收口；明确不改发布资产、不改 acceptance 判据。
- `docs/m0/reviews/RV-016.md`：本轮验证记录，逐条列命令、输出、未验证项。

修改：

- `ISS-029.md`：状态从 `Reopened` 改为 `Closed`，新增 §9“AI-006 关闭证据”：runbook §4 已 direct、RV-013 已更正、V6 HTTP Range 为 direct；真实全量正常顺序重下仍属 RV-015 §5 的 `UNVERIFIED`，不作为本 ISS 关闭条件。保留 §8 的“关闭证据不足”历史。
- `plan.md`：新增 v2.16，记录 CHG-018/ISS-031/ISS-032/RV-016；不要改写 v2.15 的历史。
- `traceability.md`：把“已验证（V10 … 正常顺序重跑 UNVERIFIED”这类自相矛盾的表述拆成“已验证 V1–V9/V10 unpack；正常顺序全量重下 UNVERIFIED”。
- `deviations.md`：如本轮仍使用任何 `--force` 或跳过全量，登记偏差。

### T7 · 验证矩阵（不下载全量）

| # | 验证 | 期望 |
|---|---|---|
| V1 | UID 1234 隔离探针：默认 bootstrap | exit 2，打印 UID_MISMATCH |
| V2 | UID 1234：显式 `--uid $(id -u) --gid $(id -g)` bootstrap + preflight | 均 exit 0（preflight 用 `--min-free-bytes 0` 排除空间干扰） |
| V3 | 全文检索“两层解包” | 仅允许出现在历史/更正说明中，不得出现在当前通过判据 |
| V4 | 全文检索“GHCR.*two-stage” | 0 处正向断言；GHCR 处必须写 UNVERIFIED |
| V5 | runbook 步骤 5/6/7 与 test prompt §4.2 | 路径 A 有 sudo + `--uid 1000`；路径 B 有显式当前 UID；步骤 7 用 `$YP_BUILDER_IMAGE` |
| V6 | README 快速开始 | 不再出现“先 bootstrap 后 fetch 且不重跑 bootstrap”的歧义 |
| V7 | runbook §4 手工命令 | `DEST_PARENT` 有定义或直接 `-C .`；复制可执行 |
| V8 | `bash scripts/gate.sh` / `check-vars.sh` | `GATE_PASS` / `VARS_OK drift=0` |
| V9 | token 扫描 | 无 `github_pat_` 明文 |
| V10 | release API 资产 | 仍 9 个（8 分片 + sha256），字节不变；不重传 |
| V11 | CI | 新提交 gate 与 publish 均 success（若 publish 只跑 sample 如实记录） |

真实 8 片重组、`--mode ghcr` 全链路、真实全量正常顺序重下仍不要求本轮跑；在报告中写 `UNVERIFIED` 与复验方法。若机器上已有 `cache-work/cache-full.tar` 与 8 个分片，可额外做一次本地 `fetch --mode release` 或 `unpack-only`，但不得重新下载。

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
fix(m0): close UID path and direct-layout doc gaps

Refs: YP-M0-CHG-018 / YP-M0-ISS-029 / YP-M0-ISS-031 / YP-M0-ISS-032 / YP-M0-RV-016
Doc: docs/m0/changes/CHG-018.md
```

回报必须包含：

```text
MACHINE: os=... uid=... docker=...
HEAD: <起点> -> <本轮提交>
REPRO: default_boot_rc=... explicit_boot_rc=... explicit_pf_rc=...
CHANGED: <文件清单>
V1..V11: <命令与关键输出；失败写 FAIL/UNVERIFIED>
DOC_GREP: two-layer=... ghcr-two-stage=...
RELEASE: assets=9 bytes=11153387520 unchanged=yes
GATE: GATE_PASS / VARS_OK
CI: gate=<url/run> publish=<url/run>
TOKEN: NO_TOKEN_IN_REPO
VERDICT: PASS（收口）| PARTIAL | FAIL
UNVERIFIED: <逐条>
```

`VERDICT=PASS（收口）` 的条件：V1–V10 全过，且 V3/V4 的检索无未限定旧口径；V11 CI 若尚未跑完写 `UNVERIFIED`，不得用本地 gate 代替远端结果。真实全量重下、GHCR 全链路未跑不阻塞，但必须写清。

## 4. 明确禁止

- 不下载 11 GiB，不重传/删除 release 资产，不改 `expected_bytes`、`assets[].size`、`checksum_asset_sha256`。
- 不把路径 B 的默认 1000 当成当前 UID；不把 `--build-arg` 当成 `bootstrap` 能自动识别的依据。
- 不在路径 B 继续使用 GHCR `wrynose-m0` 镜像；步骤 7 必须用 `$YP_BUILDER_IMAGE`。
- 不把“GHCR 源 tar 是 two-stage”写成事实；没有拉取证据就写 `UNVERIFIED`。
- 不把“两层解包”留在当前通过判据；历史/更正块可以保留，但必须限定作用域。
- 不在真实缓存上试 `--force`；不删除 `.yp-volume`；不用 root 跑构建。
