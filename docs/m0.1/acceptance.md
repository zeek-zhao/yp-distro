# YP-M0.1-REC-001 · M0.1 证据闭环验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-REC-001 |
| 版本 | v1.2 |
| 状态 | Final + M0.1.1 增补（E1–E5 见 v1.1；E6/E7 资源并发增补见 RV-020；`m0.1` tag 仍对应历史 v1.1 的 `91adcc5`，不改写旧结论） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-26 |
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

### M0.1.1 增补（E6/E7，RV-020）

| # | 项 | 证据 | 结论 |
|---|---|---|---|
| E6 | 并发资源化 + bitbake 真生效 | RV-020 §1：threads.sh=standard/32/-j16；fresh bitbake-getvar=32/-j16（ISS-037 修复：cpu_count 动态分级）；变量契约防回归 | 通过 |
| E7 | 全配额构建复验 + 4c/8G 边界 | RV-020 §2：容器 inspect 0/0/0；prod 构建 #1 14s / #2 314s、0 ERROR、all succeeded、ext4 42M；CPU ~400%/mem ~2.2GiB 无 OOM；4c/8G 全冷构建未跑 | 部分通过：全配额构建通过；4c/8G 全冷构建 UNVERIFIED |

结论只填：`通过` / `未通过` / `部分通过` / `UNVERIFIED`。填 `通过` 必须附真实输出位置。
