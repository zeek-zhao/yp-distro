# YP-M0-REC-001 · M0 验收记录

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-REC-001 |
| 版本 | v1.16 |
| 状态 | Final（判据 1/2/3/4/5/6/7/8 全部通过；判据 5 按「配置层无远程地址」静态收口；判据 7 发布端到端由 run 45607197090 与 GHCR 独立核验 digest 收口；M0 收口条件三项均满足） |
| 责任人 | |
| 生效日期 | |

## 判据与证据

| # | 判据 | 证据（命令 / 产物 / 日志） | 结论 |
|---|---|---|---|
| 1 | 容器内一条命令出 prod 镜像 | S3 提供镜像基础 `yp-builder:wrynose-m0`（Ubuntu 24.04 + kas）；S5 容器内 `kas build kas/yp.yml:kas/editions/prod.yml` 一条命令实跑成功（rc=0, wall 10253s, 4630 tasks all succeeded），产物 `core-image-minimal-qemux86-64.rootfs-20261125064738.ext4`（42M），容器 `file` → `Linux rev 1.0 ext4 filesystem data`，`IMAGE_FSTYPES = "ext4"` 生效；DES-005/RV-005（prod 补跑证据） | 通过 |
| 2 | 构建身份为 jenkins | S3 实证：`docker run --rm yp-builder:wrynose-m0 whoami`→`jenkins`，`id -u`→`1000`（默认）/2000（build-arg），root 覆盖被 entrypoint 拒绝（exit 1）；镜像 `ba1a5b8b7ecf`；DES-003/RV-003/ISS-003 | 通过 |
| 3 | 下载目录跨容器留存 | S4 容器内实证（DES-004/RV-004/CHG-002）：`bootstrap.sh` 连续 3 次输出 `KEEP`/`OWNER_OK` 且 `.probe` 内容不变（幂等）；命名容器写入 → `WRITE_OK`，宿主 `cat /tmp/yp-dl/.probe` → `probe`；`docker rm -f yp-m0-probe` 后**全新** `docker run --rm -v ...` 读取 → `probe` + `PERSIST_OK`；`preflight.sh` → `PREFLIGHT=0` | 通过 |
| 4 | 缓存目录独立可清 | S4 容器内实证（DES-004/RV-004）：两卷分别 `-v` 挂载、各有 `.yp-volume` 标识（`type=downloads`/`type=sstate`），新容器内均读到；删除 sstate 载荷后 `CLEARED_PREFLIGHT=0` 且 downloads 探针仍 `probe`（`DOWNLOADS_INTACT`），证明缓存卷可独立清空；错属主 `BAD_OWNER_EXIT=2`、空间不足 `LOW_SPACE_EXIT=3`、挂错卷 `BAD_VOLUME_EXIT=1`；构建级实证见 Stage D（清 `build/` 保留 sstate 卷后二次构建 99% 命中） | 通过 |
| 5 | 无缓存服务器依赖 | 静态判定（非端到端）：实跑 `grep -rnE 'SSTATE_MIRRORS[[:space:]]*=\|BB_HASHSERVE[[:space:]]*=' kas/ meta-yp-distro/ \| grep -v '^.*#'` → 仅 `kas/base.yml:41:    BB_HASHSERVE = "auto"`（本地 hashserv，无远程地址），`SSTATE_MIRRORS` 零命中。判定依据是**配置层无远程地址**，不是「端到端空缓存构建已验」；后者由 S5 两次构建与 99% 命中证据覆盖（判据 1、B-12），本判据不要求也不声称远程服务器实跑 | 通过 |
| 6 | 分层锁定可复现 | S2 容器内实证（builder 镜像）：`kas --version`→5.5；规范性写法（CHG-009/ISS-015）两次 `kas dump kas/yp.yml:editions/prod.yml` + `diff -u` 空 → `DUMP_STABLE`；四 edition `EDITION_OK dev/prod/dev-kernel/ci`；`grep -c commit: kas/base.yml`→4；`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值；无远程缓存（DES-002/RV-002/ADR-004/CHG-001/ISS-007） | 通过 |
| 7 | 超限切分可用 | **结论 A · 本地切分链路：通过**。T5 实跑（20 MiB 载荷，`YP_SPLIT_MAX_BYTES=6291456` 仅测试用并打印 WARN）：`PACK_OK ... sha256=61e45b2d404591c2d735a3ea6583e6f36b53793fdb58f226fecae2a875354d04`；`SPLIT_OK slices=4 total_bytes=21002240 source_sha256=61e45b2d... max=6291456`；`MERGE_OK ... sha256=61e45b2d... source_sha256=61e45b2d...`；`sha256sum src.tar merged.tar` 两行完全一致；移走片 → `ERROR: 缺片 cache.slice.01，拒绝恢复`、`MISSING_EXIT=1`；篡改片 → `ERROR: 分片 cache.slice.02 sha256 不符，拒绝恢复`、`TAMPER_EXIT=1`。Stage E 另验改阈值 gen-meta 数值联动、`--max-bytes` 覆盖 exit 2。**结论 B · 发布端到端：通过**。CHG-010 用具名 secret `GHCR_PAT` 替代 `GITHUB_TOKEN` 登录（token 不入库），CHG-011 新增 `prepare-cache-payload` 从 release `m0-s5-payload-sample` 的 `cache-payload-sample.tar.gz`（抽样自真实 S5 缓存，downloads 3 个文件 / sstate 12 个文件，sha256 `ca3063ab1d164b4c7556896507912a5a23bd4ccab341b924d57615704028cf1d`）上传 `cache-payload` 制品；ISS-017/018 修复表达式与冒号文件名。修复后 run `45607197090`（https://github.com/zeek-zhao/yp-distro/actions/runs/45607197090，`event=workflow_dispatch`、`head_sha=6cb4925`）四 job 全 `success`：`prepare-cache-payload`、`publish-cache`、`publish-builder`、`publish-cache-slices`。CI 日志实跑摘行：`CACHE_SOURCE_FOUND`、`PACK_OK ... sha256=dd2e2eaa24fcb3041cea8f51a2a646f2e3c0cbf597fab3d613cb14ae10f7a251`、`SPLIT_OK slices=1 total_bytes=18534400 max=8589934592`、`wrynose-m0-part-00: digest: sha256:11ae257dd1049ab25667538fbcc79d5b342777f401c608718c5da7c35062088a`。制品：`cache-payload`（ID 15018840892，18484148 B）、`yp-cache-slices-manifest`（ID 15019075626，312 B，下载后 manifest.json 的 `source_sha256` 与 PACK_OK 一致）。**独立核验**：匿名访问 GHCR registry API 取 `ghcr.io/zeek-zhao/yp-cache:wrynose-m0-part-00` 的 `docker-content-digest: sha256:11ae257dd1049ab25667538fbcc79d5b342777f401c608718c5da7c35062088a`，与 job 输出一致。PAT 范围内 `workflow_dispatch` 可用（CHG-010 v1.1），`GITHUB_TOKEN`/匿名下不可用（ISS-005）；L-01 不再是绝对阻断。历史失败 run `45601074345` 与两类原因归档于 ISS-016（已关闭）。结论 A/B 均为通过：本地切分链路见 T5 输出，发布端到端见 run `45607197090` 与 GHCR 独立核验 digest | 通过 |
| 8 | 手改配置可发现 | Stage F 实跑：`scripts/check-vars.sh` 对 `variable-index.md` 28 个变量断言归口值 → `VARS_OK`（drift=0）；故意改 `BB_NUMBER_THREADS` 4→8 → `DRIFT` 检出 + exit 1 → 还原 → `VARS_OK`；门禁 `scripts/gate.sh` 五项全绿 `GATE_PASS`（RV-009 §验收输出）。**事实修正**：CI run `45594520683`（push，HEAD `b072417`）曾 `checked=28 drift=2`、`MACHINE_measure`/`EDITION_measure` 因 `scripts/build/measure.sh` 未入库而 DRIFT（ISS-013）；T1 将 `.gitignore` 的 `build/` 改为根锚定 `/build/` 并按 DES-005 §3.5 入库该脚本，干净检出复跑 → `VARS_OK drift=0`、`GATE_PASS`；CHG-009：G2 数值改由 threshold.conf 变量提供，`gate.sh`/`check-vars.sh` 不再含阈值字面量与自我豁免，`grep -rnE '8589934592|480' scripts/ .github/ | grep -v threshold.conf` 无输出；修复后 push run 45600235881 → `success` | 通过 |

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
| v1.7 | 2026-11-25 | Stage E：判据 7 → 通过（本地切分链路 5 片合并 sha256 一致、缺片/篡改 exit 1、阈值联动；发布 workflow 接线完成但端到端因 L-01 未验）；ADR-005/CHG-006/DES-008/RV-008 | zeek.zhao |
| v1.8 | 2026-11-25 | Stage F：判据 8 → 通过（check-vars 28 变量 VARS_OK、故意手改 DRIFT+exit 1、还原通过；gate.sh 五项 GATE_PASS）；DES-009/RV-009/ISS-012、variable-index.md，判据 1-8 全部收口 | zeek.zhao |
| v1.9 | 2026-11-25 | T1：判据 8 结论不变，修正事实——记录 CI run 45594520683 因 measure.sh 未入库红灯，ISS-013 修复后干净检出 VARS_OK drift=0 / GATE_PASS | zeek.zhao |
| v1.10 | 2026-11-25 | T2：判据 7 口径修正——dispatch 不可用 ≠ CI 阻断；CHG-007 增加受限 push；发布端到端改由真实 push run 决定 | zeek.zhao |
| v1.11 | 2026-11-25 | T3：判据 7 补 CHG-008/ISS-014 载荷与失败即停事实；本地静态与分支模拟通过，端到端仍待 push run | zeek.zhao |
| v1.12 | 2026-11-25 | T4：判据 5 由 UNVERIFIED → 通过，依据为配置层静态 grep 仅 `BB_HASHSERVE = "auto"`、无远程地址；明确写「非端到端」 | zeek.zhao |
| v1.13 | 2026-11-25 | T5：判据 7 拆两条结论——本地切分链路通过（贴 split/merge/缺片/篡改真实输出）、发布端到端 UNVERIFIED（无命中 paths 的 push run、S5 载荷未上传制品） | zeek.zhao |
| v1.14 | 2026-11-25 | T6：判据 6/8 补 CHG-009 事实——规范性 kas 简写实测 DUMP_STABLE、G2 去自我豁免、阈值字面量仅 threshold.conf；判据 8 补 CI run 45600235881 success | zeek.zhao |
| v1.15 | 2026-11-25 | T7：判据 7 结论 B 填真实 push run 45601074345 及失败原因（缺 cache-payload 制品 + GHCR permission_denied），保持 UNVERIFIED；ISS-016 归档 | zeek.zhao |
| v1.16 | 2026-11-25 | CHG-010/011 + ISS-016/017/018：判据 7 结论 B 由 UNVERIFIED → 通过——PAT 具名 secret 修复 GHCR 权限、真实 S5 样本制品生产链路落地；run 45607197090 四 job success，分片 digest 经 GHCR registry API 独立核验；判据 1-8 全部通过，M0 收口 | zeek.zhao |
