# YP-M0-REC-001 · M0 验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-REC-001 |
| 版本 | v1.3 |
| 状态 | Draft（Stage A 回退 + Stage B 判据 6 通过，待 S4/S5 重验） |
| 责任人 | |
| 生效日期 | |

## 判据与证据

| # | 判据 | 证据（命令 / 产物 / 日志） | 结论 |
|---|---|---|---|
| 1 | 容器内一条命令出 prod 镜像 | S3 提供镜像基础 `yp-builder:wrynose-m0`（Ubuntu 24.04 + kas）；prod 镜像实跑属 S5，未验证 | UNVERIFIED |
| 2 | 构建身份为 jenkins | S3 实证：`docker run --rm yp-builder:wrynose-m0 whoami`→`jenkins`，`id -u`→`1000`（默认）/2000（build-arg），root 覆盖被 entrypoint 拒绝（exit 1）；镜像 `ba1a5b8b7ecf`；DES-003/RV-003/ISS-003 | 通过 |
| 3 | 下载目录跨容器留存 | 待 S4 重验：需 `bootstrap.sh` 落盘 + 「删容器重建后下载仍在」真实输出。现有 S7 `--volumes-from` 只证明卷属主对齐（ISS-006），**不构成 S4 留存验证**（RV-010 F-03） | UNVERIFIED |
| 4 | 缓存目录独立可清 | 待 S4 重验：需独立 sstate VOLUME + 「清 build 保留 sstate」真实输出。现有 `cache.Dockerfile` 的 VOLUME 声明仅为布局，**不构成可清验证**（RV-010 F-03） | UNVERIFIED |
| 5 | 无缓存服务器依赖 | 待 S5/S9 重验：需 kas 配置落地后 `grep -rn "SSTATE_MIRRORS\|BB_HASHSERVE" kas/ meta-yp-distro/` 无命中（B-07）；S1 静态检查 `meta-yp-distro/` 无远程地址仅为部分证据 | UNVERIFIED |
| 6 | 分层锁定可复现 | S2 容器内实证（builder 镜像）：`kas --version`→5.5；两次 `kas dump kas/yp.yml:kas/editions/prod.yml` + `diff -u` 空 → `DUMP_STABLE`；四 edition `EDITION_OK dev/prod/dev-kernel/ci`；`grep -c commit: kas/base.yml`→4；`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值；无远程缓存（DES-002/RV-002/ADR-004/CHG-001/ISS-007） | 通过 |
| 7 | 超限切分可用 | 本地实跑：`split.sh` 20 MiB→4 片、`merge.sh` 合并 sha256 与源一致、移走一片后拒绝恢复（exit 1）；发布链路未接入（RV-010 F-07） | UNVERIFIED |
| 8 | 手改配置可发现 | 待补：grep 手改点的检出脚本与样例 | UNVERIFIED |

结论只填三种：`通过` / `未通过` / `UNVERIFIED`。填 `通过` 必须附命令或产物路径。

## 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 建立验收表 | zeek-zhao |
| v1.1 | 2026-11-24 | 填判据 1–8；判据 3/4 误标通过（后由 RV-010 F-03 查出） | zeek.zhao |
| v1.2 | 2026-11-25 | Stage A：判据 3/4 回退 UNVERIFIED、判据 5 补待验路径，消除带病结论（F-03/F-02） | zeek.zhao |
| v1.3 | 2026-11-25 | Stage B：判据 6 → 通过（容器实跑 DUMP_STABLE + 4 edition + commit pin 4） | zeek.zhao |
