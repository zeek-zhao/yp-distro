# 本地目录保留说明（不进 Git 的工作区资产）

本仓库大量构建资产位于 `work/`（`.gitignore` 已覆盖，**约 456 GB**，截至 2026-11-14）。
这些目录**绝不纳入 Git**，也**不要随手清理**——重建代价远高于磁盘成本。

## work/ 结构与保留策略

| 目录 | 内容 | 保留策略 |
|---|---|---|
| `work/downloads/` | BitBake DL_DIR：源码包、git 镜像 | **必须保留**。删了要全量重新下载（数 GB~数十 GB） |
| `work/downloads/CVE_CHECK/` | 离线 NVD 库（`nvdcve_2-2.db` 等，由 `scripts/cve-db.sh` 维护） | **必须保留**。离线重建约 4 小时；kas/base.yml 设 `CVE_DB_UPDATE_INTERVAL="-1"`，构建期不走网络，库缺失直接构建失败 |
| `work/sstate/` | 共享状态缓存（容器内映射 `/work/work/sstate`） | **必须保留**。删了等于全量重编译（小时级） |
| `work/artifacts/` | 构建产物：镜像、SDK、manifest、SBOM | **必须保留**（交付物与 QA 证据源）。旧版本产物可按需转冷备 |
| `work/buildhistory/` | 镜像包清单历史（对比/回归用） | 保留 |
| `work/cve-cache/` | `cve-db.sh fetch` 的 NVD git 缓存 | 保留（加速重建 NVD 库） |
| `work/logs/`、`work/kas-*/` | 运行日志与 kas 工作目录 | **可清理**（只影响排障现场） |

磁盘自保：`kas/base.yml` 已配 `BB_DISKMON_DIRS`（TMPDIR/DL_DIR/SSTATE_DIR 各 1G 阈值 STOPTASKS，100M 阈值 ABORT），构建会在磁盘吃紧时自动停下而不是写满盘。

## 其他本机路径

- `~/backup-wf3/`：WF3 token 看板工具链（tokens.html、wf3.sh、wf3-tokens.sh、tokens-dashboard.py、token-usage.tsv）2026-11-14 移出仓库后的本地备份。确认不再需要后可自行删除。
- `reports/`、`logs/`、`cache/`、`tmp/`：.gitignore 覆盖的运行产物，可随时清理。
- 外部主机 `10.22.67.213:/home/jenkins/sstate`：历史 sstate 缓存主机。若需要跨机共享缓存，通过 `SSTATE_MIRRORS` 指向它，不要直接删除。

## 清理速查

| 可以安全删除 | 禁止删除 |
|---|---|
| `work/logs/`、`work/kas-*/`、`reports/`、`tmp/`、`cache/` | `work/downloads/`（含 CVE_CHECK）、`work/sstate/`、`work/artifacts/`、`work/buildhistory/` |
