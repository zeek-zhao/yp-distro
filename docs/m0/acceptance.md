# YP-M0-REC-001 · M0 验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-REC-001 |
| 版本 | v1.1 |
| 状态 | Draft |
| 责任人 | |
| 生效日期 | |

## 判据与证据

| # | 判据 | 证据（命令 / 产物 / 日志） | 结论 |
|---|---|---|---|
| 1 | 容器内一条命令出 prod 镜像 | S3 提供镜像基础 `yp-builder:wrynose-m0`（Ubuntu 24.04 + kas）；prod 镜像实跑属 S5，未验证 | UNVERIFIED |
| 2 | 构建身份为 jenkins | S3 实证：`docker run --rm yp-builder:wrynose-m0 whoami`→`jenkins`，`id -u`→`1000`（默认）/2000（build-arg），root 覆盖被 entrypoint 拒绝（exit 1）；镜像 `ba1a5b8b7ecf`；DES-003/RV-003/ISS-003 | 通过 |
| 3 | 下载目录跨容器留存 | S6/S7 证据：`yp-cache:wrynose-m0` 匿名拉取（digest sha256:1eaf38f5）后以 `--volumes-from` 喂给 builder，`/work/downloads` 属主 1000:1000 且可写（`cache+builder WRITE OK`、`FINAL_EXIT=0`，ISS-006）；DES-006 | 通过 |
| 4 | 缓存目录独立可清 | `yp-cache` 将 `/work/downloads` 与 `/work/sstate` 声明为独立 VOLUME（`stat 1000:1000`），可单独挂载/清除而不影响 builder 镜像；DES-006 | 通过 |
| 5 | 无缓存服务器依赖 | S1 静态检查：`meta-yp-distro/` 无远程缓存地址（DES-001 约束）；全仓终检待 S9 | UNVERIFIED |
| 6 | 分层锁定可复现 | S1 证据：`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值锁定、无多版本兼容层（DES-001/ADR-001/ISS-001 静态断言全过）；两次 `kas dump` 一致性待 S2（kas 入口 + repos commit 锁定）实跑 | UNVERIFIED |
| 7 | 超限切分可用 | | |
| 8 | 手改配置可发现 | | |

结论只填三种：`通过` / `未通过` / `UNVERIFIED`。填 `通过` 必须附命令或产物路径。

## 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 建立验收表 | zeek-zhao |
