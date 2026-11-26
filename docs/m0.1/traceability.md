# YP-M0.1-TRAC-001 · M0.1 证据追溯表

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-TRAC-001 |
| 基线 | `m0.0`（`06543c4`）；分支 `feat-m0.1-evidence` |
| 维护规则 | 每条 E 项写「命令 + 输出位置」；不以「已验证」代替原始证据 |

## 证据矩阵

| 阶段 | 项 | 实现/记录 | 验证证据（命令 / 输出位置） | 状态 |
|---|---|---|---|---|
| E1 | 真实 release 全量 | runbook §3 步骤 4→5→6（未改） | `fetch-cache.sh --mode release --dest-parent /workspace/m01-e1 ...`；RV-018 §1 + `/workspace/m01-e1/{fetch,bootstrap,preflight}.log`；REASSEMBLE_OK bytes=11153387520、SHA256_OK=1c8126d4…、STRUCT_OK mode=direct 1288/6945、无 --force | 已验证 |
| E2 | 8 片重组边界 | fetch-cache.sh（未改） | `--parts 1` exit 1；unpack-only STRUCT_OK direct（复用 tar sha256=1c8126d4…）；requires_reassembly 缺失回退 reassemble=1；RV-018 §2 | 已验证 |
| E3 | ghcr + K-8 + 布局 + ISS-036 | CHG-020 / ISS-036 | fetch-cache.sh 改造（check_target 前置、digest 拉取、RepoDigests、DIGEST_FALLBACK、two-stage-yp 布局）；manifest sha256 63→64、layout UNVERIFIED→two-stage-yp（不改 bytes/digest/total/source）；RV-018 §3 + `/workspace/m01-e3-ghcr3.log`：DIGEST_OK×2、SLICE_OK×2、MERGE_OK a8870b50…、STRUCT_OK two-stage-yp 1288/6945、FETCH_OK | 已验证 |
| E4 | 发布 CI 4 job | m0.yml / m0-gate.yml（未改） | workflow_dispatch 触发（分支受限）；RV-018 §4：gate `45820896095` success、publish `45820900729` success、4 job 全 success，head_sha=`0ce4a5e` | 已验证 |
| E5 | 记录与冻结 | 本目录 + `m0.1` tag | gate/vars/token 全绿；tag m0.1 + release-m0 | 进行中 |

状态取值：`未开始` / `进行中` / `已验证` / `UNVERIFIED` / `阻塞（ISS-0NN）`。
