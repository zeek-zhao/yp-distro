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
| E5 | 记录与冻结 | 本目录 + `m0.1` tag | gate/vars/token 全绿；tag m0.1 + release-m0 打在本版最终提交 | 已验证 |
| E6 | 并发资源化 + bitbake 真生效 | threads.sh / base.yml / ISS-037 / CHG-021 | RV-020 §1：宿主 `threads.sh`=standard/32/-j16、`YP_BUILD_THREADS=4 YP_PARALLEL_MAKE='-j 2'` 覆盖输出 4/-j2、非法覆盖 exit 1；fresh `bitbake-getvar`=32/-j16（cpu_count 动态分级，ISS-037 修复）；临时改坏回退值 `check-vars.sh` 报 DRIFT+exit 1、gate G6 防写死 | 已验证 |
| E7 | 全配额构建复验 + 4c/8G 边界 | 容器无资源限制 + E1 真实卷 + RV-019 / RV-020 §2 | RV-019：宿主 32 核/129308484 kB、Docker NCPU=32/132GB、容器 NanoCpus=0 Memory=0；prod 构建 #1 291s / #2 236s。RV-020 §2（本增补）：容器 `yp-m0-build-m011` inspect 0/0/0、prod 构建 #1 14s / #2 314s（rm -rf build）、4630 tasks all succeeded、0 ERROR、ext4 42M（`/workspace/m01-build-artifacts/*.ext4` sha256=5a5f03e2…）；CPU ~400%/mem ~2.2GiB 无 OOM；4 核/8 GB 冷构建仍 UNVERIFIED | 已验证（全配额）；4c/8G UNVERIFIED |
| E8 | M0.1.1 发布线（CI + tag） | workflow 触发改动 + RV-020 §5 | `m0-gate.yml`/`m0.yml` push 分支扩为 `feat-m0*`/`release-m0*`、`m0.yml` paths 加 `scripts/build/**`，已提交 `f81691e`、YAML 解析通过；本地 gate/vars 绿但不代替远端 run id。执行环境无推送凭据（无 token/SSH/connector），未 push、未 dispatch → gate/publish run id、`m0.1.1` tag、`release-m0` 快进均 UNVERIFIED；`m0.1` 仍 `91adcc5` 未动。续做命令见 RV-020 §5.2 | UNVERIFIED（无凭据）；分支触发改动已提交 |

状态取值：`未开始` / `进行中` / `已验证` / `UNVERIFIED` / `阻塞（ISS-0NN）`。
