# 追溯矩阵 YP-M0-REC 附录 · 需求 → 证据

> 维护规则：新增设计或修复提交后同步更新本表；评审中本表与代码不一致直接打回。
> 需求编号来自 PRD B 组；证据列只写「命令 + 输出位置」，不写「已验证」这类无依据结论。

| 需求 | 设计 | 实现提交 | 验证证据（命令 / 产物路径） | 验收行 | 状态 |
|---|---|---|---|---|---|
| B-01 kas 单一入口 | DES-001（层载体）+ DES-002（待写，kas 入口） | S1 提交 `Refs: YP-M0-DES-001` | 静态断言：layer.conf/yp-wrynose.conf 存在且变量齐全（见 ISS-001 验证证据）；kas dump 待 S2 | 判据 6 | 进行中 |
| B-02 层版本锁定 | DES-001（层系列锁定）+ DES-002（待写，repos commit 锁定） | S1 提交 `Refs: YP-M0-DES-001` | 静态断言：`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 且无多版本兼容层字样 | 判据 6 | 进行中 |
| B-03 Ubuntu 容器环境 | DES-003（ADR-003：ubuntu:24.04） | 待提交 `Refs: YP-M0-DES-003` | 官方支持矩阵（DES-003 第 2 节）；`docker build` 成功（`ba1a5b8b7ecf`，589MB），容器内 `PRETTY_NAME="Ubuntu 24.04.5 LTS"` | 判据 1 | 已验证 |
| B-04 普通用户构建 | DES-003 | 待提交 `Refs: YP-M0-DES-003` | `docker run ... whoami`→jenkins、`id -u`→1000（默认）/2000（build-arg）；root 覆盖→exit 1、错属主→exit 1、正确属主→exit 0（ISS-003） | 判据 2 | 已验证 |
| B-05 下载目录挂载 | DES-004（待写） | — | 待补 | — | 未开始 |
| B-06 缓存目录挂载 | DES-004（待写） | — | 待补 | — | 未开始 |
| B-07 不依赖缓存服务器 | DES-002（待写） | — | 待补 | — | 未开始 |
| B-08 预热镜像分发 | DES-007 | 待提交 `Refs: YP-M0-DES-007` | 独立 TOKEN push 成功（builder digest sha256:ef28c044、cache digest sha256:0deba617）；匿名拉取 unauthorized（包 private，ISS-005 待决策） | 判据 5 | 进行中 |
| B-09 超限切分 | DES-006（待写） | — | 待补 | — | 未开始 |
| B-10 分片完整性校验 | DES-006（待写） | — | 待补 | — | 未开始 |
| B-12 缓存指标 | DES-005（待写） | — | 待补 | — | 未开始 |
| B-13 离线构建 | DES-005（待写） | — | 待补 | — | 未开始 |

状态取值：`未开始` / `进行中` / `已验证` / `UNVERIFIED` / `阻塞（ISS-0NN）`。
