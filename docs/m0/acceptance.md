# YP-M0-REC-001 · M0 验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-REC-001 |
| 版本 | v1.6 |
| 状态 | Draft（Stage B/C/D 判据 6、3、4、1 通过；S5 已证 prod 一条命令出镜像 + B-12/B-13；待 S5 重验判据 5、S6/S7 判据 7、S8 判据 8） |
| 责任人 | |
| 生效日期 | |

## 判据与证据

| # | 判据 | 证据（命令 / 产物 / 日志） | 结论 |
|---|---|---|---|
| 1 | 容器内一条命令出 prod 镜像 | S3 提供镜像基础 `yp-builder:wrynose-m0`（Ubuntu 24.04 + kas）；S5 容器内 `kas build kas/yp.yml:kas/editions/prod.yml` 一条命令实跑成功（rc=0, wall 10253s, 4630 tasks all succeeded），产物 `core-image-minimal-qemux86-64.rootfs-20261125064738.ext4`（42M），容器 `file` → `Linux rev 1.0 ext4 filesystem data`，`IMAGE_FSTYPES = "ext4"` 生效；DES-005/RV-005（prod 补跑证据） | 通过 |
| 2 | 构建身份为 jenkins | S3 实证：`docker run --rm yp-builder:wrynose-m0 whoami`→`jenkins`，`id -u`→`1000`（默认）/2000（build-arg），root 覆盖被 entrypoint 拒绝（exit 1）；镜像 `ba1a5b8b7ecf`；DES-003/RV-003/ISS-003 | 通过 |
| 3 | 下载目录跨容器留存 | S4 容器内实证（DES-004/RV-004/CHG-002）：`bootstrap.sh` 连续 3 次输出 `KEEP`/`OWNER_OK` 且 `.probe` 内容不变（幂等）；命名容器写入 → `WRITE_OK`，宿主 `cat /tmp/yp-dl/.probe` → `probe`；`docker rm -f yp-m0-probe` 后**全新** `docker run --rm -v ...` 读取 → `probe` + `PERSIST_OK`；`preflight.sh` → `PREFLIGHT=0` | 通过 |
| 4 | 缓存目录独立可清 | S4 容器内实证（DES-004/RV-004）：两卷分别 `-v` 挂载、各有 `.yp-volume` 标识（`type=downloads`/`type=sstate`），新容器内均读到；删除 sstate 载荷后 `CLEARED_PREFLIGHT=0` 且 downloads 探针仍 `probe`（`DOWNLOADS_INTACT`），证明缓存卷可独立清空；错属主 `BAD_OWNER_EXIT=2`、空间不足 `LOW_SPACE_EXIT=3`、挂错卷 `BAD_VOLUME_EXIT=1`；构建级实证见 Stage D（清 `build/` 保留 sstate 卷后二次构建 99% 命中） | 通过 |
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
| v1.4 | 2026-11-25 | Stage C：判据 3/4 → 通过（容器内 WRITE_OK/PERSIST_OK、三次 bootstrap 幂等、sstate 独立清空、错属主 exit 2/空间不足 exit 3/挂错卷 exit 1） | zeek.zhao |
| v1.5 | 2026-11-25 | Stage D：判据 4 补构建级证据（清 build 保留 sstate 二次构建 99% 命中） | zeek.zhao |
| v1.6 | 2026-11-25 | Stage D：判据 1 → 通过（容器内 prod 一条命令出裸 ext4 镜像，file 识别；wall 10253s/4630 tasks/零 OOM） | zeek.zhao |
