# 追溯矩阵 YP-M0-REC 附录 · 需求 → 证据

> 维护规则：新增设计或修复提交后同步更新本表；评审中本表与代码不一致直接打回。
> 需求编号来自 PRD B 组；证据列只写「命令 + 输出位置」，不写「已验证」这类无依据结论。

| 需求 | 设计 | 实现提交 | 验证证据（命令 / 产物路径） | 验收行 | 状态 |
|---|---|---|---|---|---|
| B-01 kas 单一入口 | DES-001（层载体）+ DES-002（kas 入口） | `cf31d9b` `Refs: YP-M0-DES-002` | 容器内实跑：`kas --version`→5.5；规范性写法（CHG-009/ISS-015）两次 `kas dump kas/yp.yml:editions/prod.yml` `diff -u` 空 → `DUMP_STABLE`；四个 edition 均 `EDITION_OK`（DES-002/RV-002/ISS-007；历史长写法保留在 ISS-007 原文） | 判据 6 | 已验证 |
| B-02 层版本锁定 | DES-001（层系列锁定）+ DES-002（repos commit 锁定） | `cf31d9b` `Refs: YP-M0-DES-002` | `grep -c commit: kas/base.yml`→4（四个远程 repo 全 pin 真实 commit；meta-yp-distro 走本地 path 免 pin）；`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值；kas 固定 5.5（CHG-001） | 判据 6 | 已验证 |
| B-03 Ubuntu 容器环境 | DES-003（ADR-003：ubuntu:24.04） | `2dd387a` `Refs: YP-M0-DES-003` | 官方支持矩阵（DES-003 第 2 节）；`docker build` 成功（`ba1a5b8b7ecf`，589MB），容器内 `PRETTY_NAME="Ubuntu 24.04.5 LTS"` | 判据 1 | 已验证 |
| B-04 普通用户构建 | DES-003 | `2dd387a` `Refs: YP-M0-DES-003` | `docker run ... whoami`→jenkins、`id -u`→1000（默认）/2000（build-arg）；root 覆盖→exit 1、错属主→exit 1、正确属主→exit 0（ISS-003） | 判据 2 | 已验证 |
| B-05 下载目录挂载 | DES-004（`design/S4-mounts.md`）+ CHG-002 | `452115f` `Refs: YP-M0-DES-004` | 容器内 `WRITE_OK` → 宿主 `cat .probe` = `probe` → `docker rm -f` 后全新容器 `probe` + `PERSIST_OK`；三次 bootstrap `KEEP`/`OWNER_OK`、`PREFLIGHT=0`（RV-004 §验收输出 1/2） | 判据 3 | 已验证 |
| B-06 缓存目录挂载 | DES-004 + CHG-002 | `452115f` `Refs: YP-M0-DES-004` | 两卷分别 `-v` 挂载、各有 `.yp-volume`（`type=downloads`/`type=sstate`）；清空 sstate 载荷后 `CLEARED_PREFLIGHT=0` 且 `DOWNLOADS_INTACT`；`BAD_OWNER_EXIT=2`、`LOW_SPACE_EXIT=3`、`BAD_VOLUME_EXIT=1`，preflight 后属主仍 `0:0`（只读）（RV-004 §验收输出 3/4） | 判据 4 | 已验证 |
| B-07 不依赖缓存服务器 | DES-002 | `cf31d9b` `Refs: YP-M0-DES-002` | T4 实跑 `grep -rnE 'SSTATE_MIRRORS[[:space:]]*=\|BB_HASHSERVE[[:space:]]*=' kas/ meta-yp-distro/ \| grep -v '^.*#'` → 仅 `kas/base.yml:41:    BB_HASHSERVE = "auto"`，无远程地址；判据 5 按静态口径收口（非端到端） | 判据 5 | 已验证 |
| B-08 预热镜像分发 | DES-007 / DES-008（F-02 降级） | `43b14d3` `Refs: YP-M0-DES-007` | 基线布局镜像公共 GHCR 匿名 pull 成功（builder sha256:ef28c044、cache 修复版 sha256:1eaf38f5）；`docker run whoami=jenkins/kas 5.5`、entrypoint 拒绝 root、正确挂载放行；ISS-006 卷属主后端到端 `--volumes-from` 通过。**结论升级（CHG-010/011 / ISS-016 关闭）**：真实 S5 载荷样本制品 + PAT 发布，run `45607197090` 四 job 全 success；builder/cache 真实推送，分片 tag `wrynose-m0-part-00` digest `sha256:11ae257dd1049ab25667538fbcc79d5b342777f401c608718c5da7c35062088a`（GHCR registry API 独立核验）；历史失败 run `45601074345` 归档于 ISS-016 | 判据 7 | 已验证（基线 + 发布端到端） |
| B-09 超限切分 | DES-006 / DES-008 / ADR-005（方案 1 已接线发布流程） | `43b14d3` + `dd96ecc`（Stage E） | 本地实跑 ~20 MiB→`split.sh` 5 片、每片一个 GHCR tag 契约（ADR-005）、workflow `publish-cache-slices` 接线 pack→gen-meta→split→tag+manifest+digest；run `45607197090` 端到端 success，`SPLIT_OK slices=1`、manifest 制品 `yp-cache-slices-manifest`（15019075626）、digest 经 GHCR 独立核验；CHG-012 全量 11 GiB→2 片、merge sha256 与源一致、两片 GHCR digest 独立核验（ISS-019/020） | 判据 7 | 已验证（本地链路 + 发布端到端 + 全量载荷） |
| B-10 分片完整性校验 | DES-006 / DES-008 / CHG-006 | `43b14d3` + `dd96ecc`（Stage E）、`6cb4925`（CHG-011）、待提交（CHG-012） | 本地实跑：合并 sha256 与源逐字节一致（`SHA256_MATCH_OK`）、缺片 exit 1、篡改分片 exit 1、manifest `source_sha256` 比对、改阈值 gen-meta 数值联动、`--max-bytes` 覆盖 exit 2（RV-008 §验收输出）；CHG-012 全量 11 GiB 分片修复 dd 大 bs 后 merge sha256 一致（ISS-019） | 判据 7 | 已验证（含全量回归） |
| B-12 缓存指标 | DES-005 | `87b49c5`（RV-005）、`458ea86`（measure.sh 入库） | 两次 `Sstate summary` 原始行 + `Tasks Summary`：首次 0% match/4083 全跑；二次 99% match（2049/2054）、3829 免重跑；wall 7096s→214s | 容器实跑 2026-11-25 | 已验证 |
| B-13 离线构建 | DES-005 | `87b49c5`（RV-005）、`458ea86`（measure.sh 入库） | 第二次 `=== STATS second === fetching_lines=0`，无网络重新拉取 | 容器实跑 2026-11-25 | 已验证 |
| S8 门禁 / S9 变量索引（判据 8） | DES-009 / RV-009 / ISS-012 / CHG-009 | `b072417`（Stage F）、`458ea86`（measure.sh 入库） | `bash scripts/gate.sh`→GATE_PASS（五项全绿）；`bash scripts/check-vars.sh`→VARS_OK；故意改 `BB_NUMBER_THREADS` 4→8→`DRIFT`+exit 1→还原→VARS_OK（RV-009 §验收输出） | 判据 8 | 已验证 |

状态取值：`未开始` / `进行中` / `已验证` / `UNVERIFIED` / `阻塞（ISS-0NN）`。
