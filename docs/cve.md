# CVE 库离线化（issue #48）

`cve-check` 的结论依赖一份 NVD 的 sqlite 库。官方路径由
`cve-update-nvd2-native` 走 NVD 2.0 REST API 现拉：无 API key 时限流 5 次/30 秒、
2000 条一页，全量约 25 万条**实测 4 小时**（2026-10-29，215，出口约 1 MB/s）。
本方案把这条路彻底摘掉：数据来自 [olbat/nvdcve](https://github.com/olbat/nvdcve)
——它每天把 NVD 官方 JSON feed 拆成 `CVE-YYYY-NNNN.json` 提交到 git——由本地脚本
投影成 `cve-check` 认的 sqlite，构建期只读本地文件。

## 1. 数据流

```
github.com/olbat/nvdcve  (git, 每天更新)
        │  scripts/cve-db.sh fetch       浅克隆/增量 fetch
        ▼
work/cve-cache/nvdcve/nvdcve/CVE-*.json     404,109 个文件，3.4 GB
        │  scripts/cve-db.sh build       scripts/lib/nvd-to-sqlite.py
        ▼
work/downloads/CVE_CHECK/nvdcve_2-2.db      404 MB，385,644 条 CVE
work/downloads/CVE_CHECK/nvdcve_2.db        387 MB（3.1 的 6 列投影）
        │  bitbake do_unpack              CVE_DB_UPDATE_INTERVAL=-1，不联网
        ▼
<release>/build/tmp/sysroots/CVE_CHECK/nvdcve_2-2.db
        │  do_cve_check（每个 recipe）
        ▼
deploy/images/<machine>/<image>.rootfs.json + .cve
```

## 2. 为什么投影逻辑必须逐行照抄 bbclass

`nvd-to-sqlite.py` 的 `_cve_row()` / `_product_rows()` 是
`meta/recipes-core/meta/cve-update-nvd2-native.bb` 里 `update_db()` 与
`parse_node_and_insert()` 的移植。**任何一处偏差都会让结论与官方路径不一致**，
所以三件事刻意没「改进」：

1. `vulnStatus == "Rejected"` 的 CVE 不入库（上游是「从库里删掉」，全量重建等价于不插入）。
2. `parse_node_and_insert` 里遇到第一条 `vulnerable: false` 的 cpeMatch 是
   **`return` 而不是 `continue`** —— 整条 node 剩下的 CPE 全丢。上游就是这么写的
   （`tests/bats/09_cvedb.bats` 用 `CVE-2024-0004` 钉住了这个行为）。
3. 版本区间、`operators`、`<update>` 段拼成 `<version>_<update>` 的规则完全一致。

唯一的一处加固：上游直接下标 `cpe23[6]`，畸形 CPE（分段不足 7 段）会抛
`IndexError` 打断整个建库；这里按 `*` 处理并计入 `parse_errors`。实测 40 万条里
0 次触发。

## 3. 各版本库名与列数（实测自 poky 源码）

| release | 库文件 | NVD 表列 | 依据 |
|---|---|---|---|
| dunfell 3.1 | `nvdcve_2.db` | `ID,SUMMARY,SCOREV2,SCOREV3,MODIFIED,VECTOR` | `cve-check.bbclass` 的 `CVE_CHECK_DB_FILE` |
| kirkstone 4.0 | `nvdcve_2-2.db` | 8 列（+`SCOREV4`,`VECTORSTRING`） | `CVE_CHECK_DB_FILENAME` |
| scarthgap 5.0 | `nvdcve_2-2.db` | 同 4.0，可与 kirkstone 共用一份 | 同上 |
| wrynose 6.0 | 不适用 | 不适用 | 没有 `cve-check.bbclass`，见 §6 |

注意 4.0/5.0 的文件名是 `nvdcve_2-2.db` 而**不是** `nvdcve_2-1.db`
（issue #48 原文写的 2-1 与实际不符）。3.1 与 4.0/5.0 只是列数差异，所以
`build --release all` 先建 8 列库，再由它 `derive` 出 6 列库，JSON 只解析一遍。

## 4. 用法

```bash
# 首次：浅克隆约 3.4 GB（实测 8 分 57 秒）+ 建库（实测 18 秒）
scripts/cve-db.sh sync

# 日常：只拉当天变更，再重建两个库
scripts/cve-db.sh sync

# 只看状态
scripts/cve-db.sh status
```

```
release      db                    bytes       cves built_at
dunfell      nvdcve_2.db       405184512     385644 2026-10-30T19:25:34+0800
kirkstone    nvdcve_2-2.db     422989824     385644 2026-10-30T19:25:13+0800
scarthgap    nvdcve_2-2.db     422989824     385644 2026-10-30T19:25:13+0800
wrynose      n/a                       -          - 6.0 用 sbom-cve-check 的 git 数据库，不适用

数据源：work/cve-cache/nvdcve
修订：df08c7ecbe（2026-10-11T03:08:48+00:00）
```

库落在共享 `DL_DIR`（`work/downloads/CVE_CHECK/`），**不进 git**：它是可再生产物，
每天会变，进仓库只会让 diff 失控。旁边有 `<db>.meta.json` 记录数据源路径、
CVE 文件数、Rejected 数、`built_at`。

## 5. 合规构建

```bash
scripts/build.sh --release scarthgap --variant custom --cve
```

- `--cve` 只是在 target 之后追加 `kas/features/cve.yml`（一行
  `YP_CVE_ENABLE = "1"`），**默认的 8 组合完全不受影响**：`cve_check` 会给每个
  recipe 挂一次 `do_cve_check`，实测 scarthgap 多 1021 个任务。
- `build.sh` 会先检查 `work/downloads/CVE_CHECK/<db>` 是否存在，缺了直接报错
  让你去跑 `scripts/cve-db.sh sync`，不会在 bitbake 里挂 4 小时。
- `kas/base.yml` 里 `CVE_DB_UPDATE_INTERVAL = "-1"`：永不联网更新。3.1 下这个值
  缺失只会静默跳过，5.0 下库缺失会直接 `bb.error`。
- 开关落在 `work/logs/build-<rel>-<var>.flags`（`cve=1`），`report.sh` 据此决定
  报告里要不要出「## CVE 检查」一节 —— 没开 `--cve` 的构建不会假装有 CVE 结论。

### 实测（2026-10-30，215，32 核）

| release | 任务数 | 其中 `do_cve_check` | 构建耗时 | 镜像 `.json` | 未修复/已修复/忽略 |
|---|---:|---:|---:|---|---|
| dunfell 3.1 | 4774 | 924 | 42 s | 21.2 MB | 4165 / 9919 / 2592 |
| kirkstone 4.0 | 4481 | 993 | 49 s | 21.4 MB | 2862 / 11097 / 2737 |
| scarthgap 5.0 | 5938 | 1021 | 88 s | 25.6 MB | 668 / 17637 / 38 |

三次构建日志里 `services.nvd.nist.gov` 出现次数均为 **0**。

耗时极短是因为镜像本身命中 sstate，只有 `do_cve_check` 是真的新跑；
冷启动时这一层仍然是纯本地读库，不随网络状况波动。

## 6. wrynose（6.0）为什么是另一条通路

6.0 删掉了 `cve-check.bbclass`，改用 `sbom-cve-check`（在 `meta/classes-recipe/`，
所以配置层全局 INHERIT 找不到它）。它的库是**git 仓库**而不是 sqlite：
`fkie-cad/nvd-json-data-feeds`（db id `nvd-fkie`）与 `CVEProject/cvelistV5`（`cvelist`）。

**但 6.0 不需要接这个 bbclass**（issue #26 实测结论，见 `docs/compliance.md`）：
`INHERIT += "create-spdx"` 拿到 SBOM 之后，用 `sbom-cve-check` 的 **CLI** 在构建后
离线扫一次即可。这条路线顺带避开官方 fragment 的两个雷：

- `SRCREV = "${AUTOREV}"` + 默认库依赖 → **每次构建都 clone 两个 GB 级仓库**；
- `SPDX_INCLUDE_VEX = "all"` → 5.3 之前的实现会让 SPDX 涨到 1 GB 量级。

所以 `scripts/cve-db.sh` 对 wrynose 只做一件事：把 `nvd-fkie` 浅克隆进
`work/cve-cache/sbom/nvd-fkie`（4.1 GB / 实测 445 秒），`cvelist` 不下载
（工具侧 `--set-db-cfg cvelist disabled=true` 关掉）。

```bash
scripts/cve-db.sh --release wrynose     # 等价 --for wrynose
scripts/cve-db.sh status                # wrynose 行显示分片数与修订
```

`all` **不含** wrynose：否则每次 `sync` 都会多拉 4.1 GB。

| release | 库 | 建库动作 | 谁读它 |
|---|---|---|---|
| dunfell / kirkstone / scarthgap | `work/downloads/CVE_CHECK/nvdcve_*.db` | `nvd-to-sqlite.py` 投影 | 构建期 `do_cve_check` |
| wrynose | `work/cve-cache/sbom/nvd-fkie` | 仅检出的 git 数据 | 构建后 `sbom-cve-check` CLI |

### 实测（2026-10-31，215）

```bash
scripts/cve-db.sh --release wrynose      # 4.1 GB / 28 个年份分片 / f26b0edd41
scripts/build.sh --release wrynose --variant custom --cve   # 隐含 --spdx
```

- 构建日志里 `github.com` 出现 **0 次**（`AUTOREV` 那条路彻底没走），
  `SPDX_VERSION = "3.0.1"`、`SPDX_INCLUDE_VEX = "current"`（6.0 默认值）。
- 扫镜像 SBOM（`deploy/images/<machine>/<image>.rootfs.spdx.json`，6.5 MB）：

```bash
PYTHONPATH=work/tools/sbom-cve-check python3 work/tools/sbom-cve-check/bin/sbom-cve-check \
  --databases-dir work/cve-cache/sbom --sbom-type spdx3 \
  --sbom-path <镜像 SBOM> \
  --disable-auto-updates --offline-mode \
  --set-db-cfg cvelist disabled=true \
  --export-type yocto-cve-check-manifest --export-path <输出>
```

**8.4 s**，导出清单 24 MB，**102 个包 / Unpatched 318 / Patched 16,968 /
Ignored 41** —— 与探针口径完全一致，说明换到统一缓存路径没有改变结论。

## 7. 踩过的坑

- **`BB_DISKMON_DIRS` 的 `HALT` 会让 3.1 直接解析失败**
  （`ERROR: Unknown disk space monitor action: HALT`）。`HALT` 是 bitbake 4.0 才加的
  动作，#50 引入时 P1 的 dunfell 真构建已经跑完，所以一直没暴露。已统一改成
  `ABORT`（四版都认），详见 `docs/build-env.md`。
- **3.1 的 JSON 清单默认关闭**：`CVE_CHECK_FORMAT_JSON` 在 3.1 是 `0`（4.0+ 是 `1`），
  不开就只有文本 `.cve`，跨版本没法按同一份 json 比清单。已在
  `kas/releases/dunfell.yml` 打开。
- **镜像清单名三版不一致**：3.1 是 `<image>-<machine>.json`，3.2+ 是
  `<image>-<machine>.rootfs.json`，`report.sh` 三种都要试。
- **`kas -c` 里不能写 `${IMAGE}`**：kas 用的是 `/bin/sh -c`，bitbake 变量在那个
  shell 里不存在，会被展开成空串（`scripts/sdk.sh` 踩过同一个坑）。

## 8. 谁依赖这份库

- `scripts/build.sh --cve` 的预检与构建
- `scripts/report.sh` 的「## CVE 检查」节
- `scripts/kas-verify.py::check_cve_db`（断言 `-1` 与 `kas/features/cve.yml` 存在）
- `tests/bats/09_cvedb.bats`（10 例，全部用 `tests/fixtures/nvd/` 的 5 个样本，不联网）
- `config/features.txt` 的 `cve-db` 行
