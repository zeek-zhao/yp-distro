# YP-M0.1-REC-001 · M0.1 证据闭环验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-REC-001 |
| 版本 | v1.0 |
| 状态 | 进行中（E1–E3 已验证；E4 待 push 后回填；E5 冻结待执行） |
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
| 6 | 发布 CI 4 job | RV-018 §4（push 后回填 run id / 每 job 结论） | 进行中 |
| 7 | 门禁与冻结 | GATE_PASS / VARS_OK drift=0 / NO_TOKEN_IN_REPO；m0.1 tag + release-m0 | 进行中 |

结论只填：`通过` / `未通过` / `UNVERIFIED`。填 `通过` 必须附真实输出位置。
