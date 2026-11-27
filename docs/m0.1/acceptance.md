# YP-M0.1-REC-001 · M0.1 证据闭环验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-REC-001 |
| 版本 | v1.5 |
| 状态 | Final + M0.1.1/M0.1.2/M0.1.3 增补（E1–E5 见 v1.1；E6/E7/E8 见 RV-020；E9 资源兜底与文档去误导见 RV-021；E10 ai-entry 状态解析与 M1 闸门见 RV-022；`m0.1`=`91adcc5`、`m0.1.1`=`8cb0fc6`、`m0.1.2`=`8c28dc1` 冻结不动，不改写旧结论） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-27 |
| 关系 | M0 `docs/m0/acceptance.md` 状态 `Final` 不变；本文件只记录 M0.1 证据闭环，不改 M0 判据 1–8 结论 |

## 验收项

| # | 项 | 证据 | 结论 |
|---|---|---|---|
| 1 | 真实 release 8 片正常顺序全量 | RV-018 §1：无 --force，REASSEMBLE_OK 11153387520、SHA256_OK=1c8126d4…、STRUCT_OK direct 1288/6945、bootstrap/preflight owner=1000 | 通过 |
| 2 | 8 片重组边界 | RV-018 §2：--parts 1 exit 1；unpack-only direct；回退 reassemble=1 | 通过 |
| 3 | ghcr 全链路 + K-8 | RV-018 §3：DIGEST_OK×2、RepoDigests 校验、非空目标 0s 拒绝、DIGEST_FALLBACK 回退、MERGE_OK a8870b50…、STRUCT_OK two-stage-yp、FETCH_OK | 通过 |
| 4 | GHCR 源 tar 布局确认 | CHG-020：layout UNVERIFIED→two-stage-yp（yp-dl.tar+yp-st.tar）；M0 各轮此项 UNVERIFIED，本轮首次真实确认 | 通过 |
| 5 | manifest 笔误修复 | ISS-036：slice1 sha256 63→64 位补 c；bytes/digest/total_bytes/source_sha256 不变 | 通过 |
| 6 | 发布 CI 4 job | RV-018 §4：workflow_dispatch 触发（分支受限未自动 push）；gate `45820896095` success；publish `45820900729` success，4 job（prepare-payload/builder/cache/cache-slices）全 success，head_sha=`0ce4a5e` | 通过 |
| 7 | 门禁与冻结 | GATE_PASS / VARS_OK checked=28 drift=0 / NO_TOKEN_IN_REPO；tag `m0.1`（annotated）+ 分支 `release-m0` 打在本版最终提交 | 通过 |

### M0.1.1 增补（E6/E7/E8，RV-020）

| # | 项 | 证据 | 结论 |
|---|---|---|---|
| E6 | 并发资源化 + bitbake 真生效 | RV-020 §1：threads.sh=standard/32/-j16；fresh bitbake-getvar=32/-j16（ISS-037 修复：cpu_count 动态分级）；变量契约防回归 | 通过 |
| E7 | 全配额构建复验 + 4c/8G 边界 | RV-020 §2：容器 inspect 0/0/0；prod 构建 #1 14s / #2 314s、0 ERROR、all succeeded、ext4 42M；CPU ~400%/mem ~2.2GiB 无 OOM；4c/8G 全冷构建未跑 | 部分通过：全配额构建通过；4c/8G 全冷构建 UNVERIFIED |
| E8 | 发布线（CI + tag） | RV-020 §5：push `59e254d` 自动触发 gate `45962283036` success、publish `45962283012` success（4 job 全绿、head_sha=`59e254d`）；`m0.1` 仍 `91adcc5`，`m0.1.1` annotated tag + `release-m0` 快进见 RV-020 §5.3 | 通过（CI）；tag/branch 见 RV-020 §5.3 |

### M0.1.2 增补（E9，RV-021）

| # | 项 | 证据 | 结论 |
|---|---|---|---|
| E9 | 资源兜底（CPU+内存分级）+ 文档去误导 | RV-021：base.yml `INHERIT yp-concurrency` + `.bbclass` 的 `yp_build_threads(d)` 按 cgroup v2/v1 内存+CPU 分级（实测矩阵：32/123→32/-j16、4/8→4/-j2、16/16→8/-j4、32/64→16/-j8、64/4→4/-j2 不按 CPU 翻倍）；threads.sh 只读 `SUGGEST_*` 无 export，runbook/测试提示词无 eval/export；标准机 getvar 32/-j16 + 缓存 prod 构建 309s RC=0 0 ERROR ext4；CI push `9898bde` gate `45972533386` / publish `45972533380` 均 success（4 job 全绿）；tag/branch 见 RV-021 §5.2；4c/8G 全冷构建按用户要求不做 | 通过；tag/branch 见 RV-021 §5.2；4c/8G 全冷构建按用户要求不做 |

### M0.1.3 增补（E10，RV-022）

| # | 项 | 证据 | 结论 |
|---|---|---|---|
| E10 | ai-entry 状态解析与 M1 立项闸门 | RV-022 §1：完成态按 `^完成`/`^已验` 前缀判定，`完成（…）`/`完成 / …` 被跳过、`未完成` 不误吞；普通模式输出 `M0/M0.1 已闭环；M1 未立项（需 PRD/范围评审）`，`--next` 输出闭环提示 exit 0、无空 Step；临时 plan 三态样例通过；记录收口见 RV-022 §2 | 通过（T1 真实输出）；T2–T5 见 RV-022 |

结论只填：`通过` / `未通过` / `部分通过` / `UNVERIFIED`。填 `通过` 必须附真实输出位置。

## M1 立项闸门（AI-011 §4 / T3）

**M1 入口为 `m0.1.3`（`8c28dc1` 之后的最终提交），但 M1 功能范围必须先按 PRD / 新 DES 评审、由人类确认，不得从 `m0`/`m0.1` 直接拉功能分支，也不得在未给出范围时自行编造 M1 需求。** `scripts/ai-entry.sh` 在全部 M0 Step 完成后只提示「M1 未立项，先补 M1 范围/PRD 评审」，不写 M1 代码、不创建 `docs/m1/design`。本轮不创建任何 M1 功能分支。

