# YP-M0 换机链路 direct 收口修复 · AI 执行提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-005 |
| 版本 | v1.0 |
| 日期 | 2026-11-26 |
| 适用仓库 | `https://github.com/zeek-zhao/yp-distro`，分支 `feat-m0-kas-bootstrap` |
| 编写时 HEAD | `b818251`（开工时以实际 `git rev-parse HEAD` 为准并记录；若已前进，先读最新 `plan.md`、`acceptance.md`、`runbook-new-machine.md`、`RV-014.md`） |
| 目标 | 修复 `b818251` 上仍存在的换机链路 P1：官方顺序 bootstrap→fetch 必失败、release 归档 direct 与 runbook/CHG/manifest 的 two-stage 描述矛盾、manifest `layout` 字段语义混用；让“新机器照文档、不带 `--force`”可以稳定取回并进入构建 |
| 不在范围 | 改发布资产、重传 11 GiB、改已 Final 的判据结论、新增远程缓存、cold build 性能优化、`--mode ghcr` 实跑、K-8 |

## 0. 角色、边界与已定决策

你是本轮**收口修复执行方**。先复现，再最小修复，再留痕。以下决策已由需求方拍板，不要再做方案对比：

1. **release 归档就是 direct**：顶层为 `yp-dl/`、`yp-st/`（空目录）、`downloads/`、`sstate/`，没有 `downloads.tar` / `sstate.tar`。不要为了迁就文档去改发布归档。
2. **不重传、不重算**：release 资产数仍为 8 + sha256，总字节仍为 `11153387520`，tar sha256 仍为 `1c8126d4…`。acceptance v1.21 的字节结论不动。
3. **官方顺序改为 fetch → bootstrap → preflight**：新机器先取缓存（目标为空），再 `bootstrap` 归一属主，再 `preflight`。正常路径不再使用 `--force`。
4. **`check_target` 做防御性放宽**：目标不存在、空目录、或**仅含 `.yp-volume`** 视为可写；只要有其他任何条目（含隐藏文件）就仍判冲突。这样即使有人先 bootstrap 再 fetch，也不会被 marker 误杀。
5. **manifest 拆语义**：`layout` 只描述归档内部布局（本 release 为 `direct`）；新增 `requires_reassembly: true` 描述“下载后需先合并分片”。`fetch-cache` 的重组判断改读后者，不再拿 `layout=two-stage` 当“是否分片”的开关。
6. **不要编造 provenance**：目前没有证据表明 release tar 由 `pack.sh` 产出；实测 `pack.sh` 产出 two-stage。若拿不到当时的确切打包命令，就在 CHG-017 中写 `UNVERIFIED`，只记录可观测事实，禁止补一条“看起来合理”的命令。

硬约束：

- 只允许 `zeek.zhao <zeek.zhao@foxmail.com>` 提交；不得出现 AI 署名 trailer。
- 不得把 token 写入仓库、脚本、日志、提交信息；推送用环境变量或一次性 URL。
- **不得下载 11 GiB 全量载荷**。本机已有 `cache-work/` 归档时可复用；否则只用 sample、dry-run、HTTP Range 和本地小样本验证。
- 不得删除/重建 release 资产；不得修改 `cache-full.release.json` 的 `expected_bytes`、`assets[].size`、`checksum_asset_sha256`。
- 不得用 root 跑构建；不得改阈值来源 `scripts/cache/threshold.conf`。
- 任何“通过”必须有本轮命令与输出；没跑的写 `UNVERIFIED`。

## 1. 开工先复现（只读，10 分钟）

```bash
git clone --branch feat-m0-kas-bootstrap https://github.com/zeek-zhao/yp-distro.git
cd yp-distro
git rev-parse HEAD && git log --oneline -3 && git status --short
```

依次记录以下四项，作为修复前基线：

1. **release 归档真实布局**（不下载全量，只读前 4 KB）：

```bash
curl -L -r 0-4095 -o /tmp/part00.head \
  https://github.com/zeek-zhao/yp-distro/releases/download/m0-s5-payload-full/cache-full.part-00
strings /tmp/part00.head | head -30
```

期望看到 `downloads/.yp-volume`、`sstate/`、`yp-dl/` 一类 direct 条目，**不应**出现 `downloads.tar` 作为顶层成员。

2. **`pack.sh` 的真实产出**（本地小样本，不碰全量）：

```bash
mkdir -p /tmp/pk/downloads /tmp/pk/sstate
echo a > /tmp/pk/downloads/a.txt
echo b > /tmp/pk/sstate/b.txt
bash scripts/cache/pack.sh --downloads /tmp/pk/downloads --sstate /tmp/pk/sstate \
  --out /tmp/pk/out.tar
tar -tf /tmp/pk/out.tar | head
```

期望顶层是 `./` 加 `./downloads.tar`、`./sstate.tar`，即 two-stage。把这条事实写进报告，它证明“release 不是 pack.sh 产出”。

3. **官方顺序的冲突**：

```bash
rm -rf /tmp/mk && mkdir -p /tmp/mk/downloads /tmp/mk/sstate
: > /tmp/mk/downloads/.yp-volume
: > /tmp/mk/sstate/.yp-volume
bash scripts/cache/fetch-cache.sh --mode unpack-only \
  --unpack-only /tmp/pk/out.tar --dest-parent /tmp/mk
```

期望当前版本报“目标非空”并 exit 1。若已不再失败，说明前序修复已生效，记录实际输出并调整后续工作项。

4. **manifest 与 dry-run 口径**：

```bash
python3 -c "import json;d=json.load(open('manifests/cache-full.release.json'));print(d['layout'],d['expected_bytes'],len(d['assets']))"
bash scripts/cache/fetch-cache.sh --mode release --dry-run \
  --dest-parent /tmp/nope --work /tmp/nope-work --release-tag m0-s5-payload-full
```

当前期望输出 `layout=two-stage`，但第 1 步证明实物是 direct。这个矛盾就是本轮要修的。

## 2. 工作项

### T1 · `fetch-cache.sh` 的 `check_target`

文件：`scripts/cache/fetch-cache.sh`

行为要求：

- 目标目录不存在 → 可写；
- 目标为空目录 → 可写；
- 目标**只有 `.yp-volume`**（可有多层，但每层只允许该 marker）→ 可写，继续解包，不删除 marker，不要求 `--force`；
- 目标存在任何其他条目（包括 `.DS_Store`、日志、半截 tar）→ 仍 `die`，提示用 `--force`，并把“`--force` 会删除整个目标目录”写进提示；
- `--force` 行为本身不要改成静默合并；保留其破坏性语义，只加强提示。
- 解包后如果当前用户是 root，打印一条 `OWNER_HINT`：归档条目可能带非 1000 属主，请随后执行 `bootstrap.sh` 归一。

不要用“删除 marker 再判断”的实现，判断必须是无损的。

### T2 · runbook 改成 fetch → bootstrap，并统一 direct

文件：`docs/runbook-new-machine.md`

必须改到的位置：

- §2 分发口径表：release 全量归档标 `direct`；`pack.sh` 只标“本地打包/GHCR 源 tar 为 two-stage”，不要把两者混成一句。
- §3 步骤顺序：把“取回缓存”移到 `bootstrap` 之前；先 fetch（目标为空，不需要 `--force`），再 bootstrap 归一属主，再 preflight。UID≠1000 的路径 A/B 决策放在 bootstrap 之前说明即可，但 fetch 不依赖镜像 UID。
- §3 步骤 5 及所有“两步解包”措辞：改为“单层解包，直接得到 `downloads/` 与 `sstate/`”。
- §4 手工恢复命令：改成 `tar -xf cache-full.tar -C <parent>`，校验 `downloads/`、`sstate/` 存在；删除 `tar -xf downloads.tar` / `sstate.tar` 这类命令。
- §5.4：改为按 §4 的单层方式核对。
- §7：保留已修正的 direct 说明，并与 §4 口径一致。
- 明确写：`--force` 只用于“目标已有真实文件、确认可丢弃”的场景；新机器正常路径不需要，重复执行会删除已有缓存。

### T3 · README 去掉“两步解包”

文件：`README.md`

- 状态表/快速开始中凡出现“两步解包”“downloads.tar/sstate.tar”的句子，改为 direct 单层。
- “三步上手”第 3 步若仍不可直接执行，保留 ISS-028 的修正结果，不要回退。
- 明确 S5 缓存取回入口是 runbook §3，不在 README 里复制一套会漂移的命令。

### T4 · manifest 与 fetch 的重组逻辑

文件：`manifests/cache-full.release.json`、`manifests/full-slices-manifest.json`、`scripts/cache/fetch-cache.sh`

`cache-full.release.json`：

- `layout` 改为 `"direct"`；
- 新增 `"requires_reassembly": true`；
- 其余资产列表、大小、`expected_bytes`、`checksum_asset_sha256` 一律不动；
- 如已有 `asset_count`，保持 8。

`full-slices-manifest.json`（GHCR 源 tar）：

- 若该源 tar 确为 two-stage（由 `pack.sh` 产出），保留 `layout: two-stage`，并加 `requires_reassembly: true`；
- 不要把它和 release 的 direct 混成一个字段；
- 若无法确认，标 `UNVERIFIED`，不要改已有 digest。

`fetch-cache.sh`：

- 读取 `requires_reassembly`；缺失时回退旧逻辑（`layout == two-stage` 视为需要重组），保证旧 manifest 不炸；
- 重组条件改为 `count == M_COUNT && requires_reassembly == true`；
- `--parts` 的拒绝条件改为 `requires_reassembly == true`，提示语写“分片归档不支持部分取片”，不要再写死 two-stage；
- `MODE_INFO` 同时打印 `layout=` 与 `reassemble=`；
- 增加一致性校验：`layout=direct` 且 `count>1` 时，若 `requires_reassembly` 不为 true 直接报错；`layout=two-stage` 且 `requires_reassembly` 为 false 也报错，防止未来再次漂移；
- `unpack_archive` 保留对实际 tar 的 direct/two-stage 探测，作为最后防线，不要只信 manifest。

### T5 · 更正记录，不篡改历史

新建：

- `docs/m0/changes/CHG-017.md`：本轮契约更正，至少包含：
  - release 归档实际 `layout=direct`、顶层成员、字节与 sha 不变；
  - `pack.sh` 产出 two-stage，**不是** release 产出者；
  - manifest 字段拆分（`layout` / `requires_reassembly`）；
  - 官方顺序 fetch → bootstrap；
  - `--force` 的使用边界；
  - 明确“不重传、不改变发布资产”。
- `docs/m0/issues/ISS-030.md`：P1，manifest `layout` 语义混用；关闭条件为字段拆分、dry-run 显示 `layout=direct reassemble=1`、`--parts` 仍拒绝。
- `docs/m0/reviews/RV-015.md`：本轮修复验证记录，逐项列命令、输出、未验证项。

修改：

- `ISS-029`：把状态从 Closed 改为 Reopened，新增“关闭证据不足”一节：§4 未改、RV-013 未补、根因“pack.sh 产出 direct”实测错误；待 T2/T5 完成并给出证据后再关闭。不要删除原关闭记录。
- `RV-013`：加“更正”段：原“外层 tar 顶层是 downloads.tar/sstate.tar”只适用于 `pack.sh` 的本地小样本，不适用于 release 归档；release 为 direct。
- `RV-014`：加“执行偏差”段，明确记录：
  - 本轮为绕开 `.yp-volume` 冲突使用了 `--force`，该参数不在 runbook/提示词中；
  - fetch 后重新执行了 bootstrap 才恢复 1000 属主；
  - 因此 RV-014 的 PASS 是“功能链路 PASS”，不是“按 runbook 无偏差 PASS”；
  - 结论不改，但必须让读者看到偏差。
- `docs/m0/deviations.md`：登记上述 `--force` 与顺序偏差，编号按现有格式续。
- `docs/m0/plan.md`、`docs/m0/traceability.md`：补记 T1–T7 与 K-1…K-8、CHG-017、ISS-029/030，保持“plan 是进度唯一事实源”。
- `CHG-012`：不要静默改写历史。在文首加醒目“更正”块，指向 CHG-017，说明本文中 `downloads.tar/sstate.tar`、`same pack.sh 链路` 的表述已被 CHG-017 取代；若保留原文，必须让读者第一眼看到更正。

### T6 · 清理过期提示词

文件：`docs/ai/m0-portability-prompt.md`、`docs/ai/m0-new-machine-test-prompt.md`

- `m0-portability-prompt.md` 是 T1–T7 历史提示词。**不要重写正文冒充当时就是这样**；在文首加“历史文件/已取代”块，逐条列出已被 CHG-014/015/017 更正的项：默认 UID、payload 字节、two-stage 布局。执行入口指向最新 runbook。
- `m0-new-machine-test-prompt.md` 是当前测试入口，必须改对：
  - `STRUCT_OK` 期望从 `mode=two-stage` 改为 `mode=direct`；
  - 全量期望字节写 `11153387520`；
  - 默认 UID 说明改为镜像 1000（CHG-014），删除“preflight 不带参数会以当前 UID 误报 BAD_OWNER”的过期说法；
  - 官方顺序改为 fetch → bootstrap → preflight；
  - 明确正常路径不得用 `--force`；如已用，必须记偏差。
- 改完做一次交叉 grep，确保没有“当前执行入口仍要求 two-stage”的句子。

### T7 · 验证矩阵（不下载全量）

至少完成：

| # | 验证 | 期望 |
|---|---|---|
| V1 | marker-only 目标 + 小 direct tar，`fetch --mode unpack-only` | 成功，不需要 `--force`，marker 保留 |
| V2 | marker + 额外文件，同上 | exit 1，提示 `--force` 破坏性 |
| V3 | `pack.sh` 小样本 `tar -tf` | `./downloads.tar`、`./sstate.tar`，two-stage |
| V4 | full manifest + `--dry-run` | `layout=direct reassemble=1`，`expected_bytes=11153387520` |
| V5 | `--parts 1` | exit 1，提示“不支持部分取片” |
| V6 | HTTP Range 读 `part-00` 前 4 KB | 出现 `downloads/`、`sstate/`，不出现顶层 `downloads.tar` |
| V7 | `bash scripts/gate.sh` / `check-vars.sh` | `GATE_PASS` / `VARS_OK drift=0` |
| V8 | `git grep -n 'downloads.tar'` | 仅出现在 `pack.sh` 作用域说明或明确的“更正/历史”块，不得有未加限定的当前操作命令 |
| V9 | token 扫描 | 仓库无 `github_pat_` 明文 |
| V10 | 本机已有 `cache-work/` 且不下载时 | 可用 sample 或本地归档做一次真实 unpack；没有则标 `UNVERIFIED`，不要为了 V10 去下 11 GiB |

如果机器上保留了 `cache-work/cache-full.tar`，可额外做一次“marker-only 目标 + 真实归档 unpack”，只解包不下载；仍不得重新上传或修改归档。

## 3. 提交与回报

提交前：

```bash
git status --short
git diff --stat
git grep -n 'github_pat_' || true
bash scripts/gate.sh
bash scripts/check-vars.sh
```

提交信息建议：

```text
fix(m0): align direct archive layout and new-machine fetch order

Refs: YP-M0-CHG-017 / YP-M0-ISS-029 / YP-M0-ISS-030 / YP-M0-RV-015
Doc: docs/m0/changes/CHG-017.md
```

回报必须包含：

```text
MACHINE: os=... docker=... cpu=... mem=... disk=... uid=...
HEAD: <起点> -> <本轮提交>
REPRO: layout_head=<direct|...> pack=<two-stage|...> check_target_before=<exit ...> dryrun_before=<layout=...>
CHANGED: <文件清单>
V1..V10: <每项命令与关键输出，失败的写 FAIL/UNVERIFIED>
RELEASE: assets=8 bytes=11153387520 sha=1c8126d4... unchanged=yes|no
DOC_GREP: <two-stage/downloads.tar 仍出现的位置及限定语>
GATE: <GATE_PASS/VARS_OK>
TOKEN: NO_TOKEN_IN_REPO
VERDICT: PASS（收口）| PARTIAL | FAIL
UNVERIFIED: <逐条写清原因与复验方法>
```

`VERDICT=PASS（收口）` 的条件：V1–V9 全过，且当前 runbook/README/CHG 不再存在“未加限定、会让读者执行 two-stage”的句子。V10 未跑不阻塞，但必须写 `UNVERIFIED`。不得把“功能曾经 PASS”当作本轮文档收口的证据。

## 4. 明确禁止

- 不下载、不重传、不删除 release 的 8 个分片与 sha256 资产。
- 不修改 `acceptance.md` 的判据结论与字节数；如确需加说明，只能加“布局为 direct、字节不变”的注释，不得改 Final 状态。
- 不把 `--force` 写成新机器的常规步骤；不得在真实 11 GiB 缓存目录上试 `--force`。
- 不把 `pack.sh` 说成 release 归档的产出者；找不到确切命令就写 `UNVERIFIED`。
- 不通过删除 `.yp-volume` 来“修复”冲突；marker 是卷标识，必须保留。
- 不为了 V4 的 `layout=direct` 去改 `fetch` 的重组分支而不加 `requires_reassembly`，那会直接把全量下载打断。
- 不使用 root 跑构建，不引入远程 sstate/hashserv。
