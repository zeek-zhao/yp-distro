# 追溯矩阵 YP-M0-REC 附录 · 需求 → 证据

> 维护规则：新增设计或修复提交后同步更新本表；评审中本表与代码不一致直接打回。
> 需求编号来自 PRD B 组；证据列只写「命令 + 输出位置」，不写「已验证」这类无依据结论。

| 需求 | 设计 | 实现提交 | 验证证据（命令 / 产物路径） | 验收行 | 状态 |
|---|---|---|---|---|---|
| B-01 kas 单一入口 | DES-001（层载体）+ DES-002（kas 入口） | 待提交 `Refs: YP-M0-DES-002` | 容器内实跑：`kas --version`→5.5；两次 `kas dump kas/yp.yml:kas/editions/prod.yml` `diff -u` 空 → `DUMP_STABLE`；四个 edition 均 `EDITION_OK`（DES-002/RV-002/ISS-007） | 判据 6 | 已验证 |
| B-02 层版本锁定 | DES-001（层系列锁定）+ DES-002（repos commit 锁定） | 待提交 `Refs: YP-M0-DES-002` | `grep -c commit: kas/base.yml`→4（四个远程 repo 全 pin 真实 commit；meta-yp-distro 走本地 path 免 pin）；`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值；kas 固定 5.5（CHG-001） | 判据 6 | 已验证 |
| B-03 Ubuntu 容器环境 | DES-003（ADR-003：ubuntu:24.04） | 待提交 `Refs: YP-M0-DES-003` | 官方支持矩阵（DES-003 第 2 节）；`docker build` 成功（`ba1a5b8b7ecf`，589MB），容器内 `PRETTY_NAME="Ubuntu 24.04.5 LTS"` | 判据 1 | 已验证 |
| B-04 普通用户构建 | DES-003 | 待提交 `Refs: YP-M0-DES-003` | `docker run ... whoami`→jenkins、`id -u`→1000（默认）/2000（build-arg）；root 覆盖→exit 1、错属主→exit 1、正确属主→exit 0（ISS-003） | 判据 2 | 已验证 |
| B-05 下载目录挂载 | DES-004（待写） | — | 待补 | — | 未开始 |
| B-06 缓存目录挂载 | DES-004（待写） | — | 待补 | — | 未开始 |
| B-07 不依赖缓存服务器 | DES-002 | 待提交 `Refs: YP-M0-DES-002` | 容器内 `grep -rn "SSTATE_MIRRORS\|BB_HASHSERVE" kas/ meta-yp-distro/` → 仅 `BB_HASHSERVE = "auto"` 本地模式，无远程地址（DES-002 §3.4） | 判据 5 | 已验证 |
| B-08 预热镜像分发 | DES-007 | `43b14d3` `Refs: YP-M0-DES-007` | 网页改 public 后匿名 pull 成功（builder sha256:ef28c044、cache 修复版 sha256:1eaf38f5）；`docker run whoami=jenkins/kas 5.5`、entrypoint 拒绝 root、正确挂载放行；ISS-006 修复卷属主后端到端 `--volumes-from` 组合通过 | 判据 5 | 已验证 |
| B-09 超限切分 | DES-006（`design/S6-cache-pack-split.md`；未接入发布流程，见 RV-010 F-07） | `43b14d3` | 待补：分片镜像 tag 与清单上传 | 判据 7 | 进行中 |
| B-10 分片完整性校验 | DES-006（同上；脚本级已通过，发布链路未验） | `43b14d3` | 本地实跑：20 MiB→4 片合并 sha256 一致、缺片 exit 1（RV-010 第 3 节） | 判据 7 | 进行中 |
| B-12 缓存指标 | DES-005（待写） | — | 待补 | — | 未开始 |
| B-13 离线构建 | DES-005（待写） | — | 待补 | — | 未开始 |

状态取值：`未开始` / `进行中` / `已验证` / `UNVERIFIED` / `阻塞（ISS-0NN）`。
