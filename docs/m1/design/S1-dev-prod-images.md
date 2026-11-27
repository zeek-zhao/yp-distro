# YP-M1-DES-002 · M1-S1 dev/prod 镜像与三个包组设计

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-DES-002 |
| 版本 | v1.0 |
| 状态 | Approved（设计先行；本提交只含设计与四问评审，配方/kas 在评审后单独提交） |
| 关联 | `docs/m1/plan.md` §M1-S1；基线 `feat-m1-dev-platform`=`2501402`（S0 已合入）；S0 产物 `core-image-minimal` 作回退镜像 |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-27 |

## 1. 目的与不做的事

**目的**：把「dev 镜像带目标侧调试工具、prod 镜像无残留」从规划变成可构建、可检查的 Yocto 配方。落地三个包组（`base` / `devtools` / `kernel-tools`）与两个镜像（`yp-image-dev` / `yp-image-prod`），使 D-04（dev 有工具、prod 无残留）可取证，并为 S3 的 deploy/gdbserver 提供带工具的靶机镜像。

**不做**（plan §M1-S1 边界）：不写 eSDK / `populate_sdk_ext`（S2）；不写 `deploy-target` / `gdb-connect` / gdbserver 远程断点（S3）；不写 buildhistory / yocto-check-layer / 四步 CI / `m1-dev.yml`（S4）；不打 `m1.0`、不改 M0 tag 与结论、不建 M2 分支；不新增 PRD 之外的需求。

**D-01 两层口径**（plan §3.1）：本 Stage 只做**目标镜像层**（gdbserver/gdb/perf/strace/trace-cmd/quilt 为可运行工具，进 `yp-image-dev`）；`devtool`/`recipetool`/`devshell`/`quilt` 作为宿主/eSDK 工具属于 S2，不塞进 rootfs、不在此宣称已验证。quilt 在 oe-core 同时有 target 版 `quilt_0.69.bb` 与 native 版；本 Stage 把 target 版列入 `devtools`（目标侧可运行的 `quilt` 命令），宿主侧 devtool 链路仍归 S2。

## 2. 输入与前提

- **层与配方可用性（容器内 `kas checkout` 固定 commit 实测，非推测）**：

  | 工具 | 配方 | 所在层 | base.yml 是否已含 |
  |---|---|---|---|
  | gdb / gdbserver | `gdb_17.2.bb`（`PACKAGES =+ "gdbserver"`，`FILES:gdbserver=${bindir}/gdbserver`） | openembedded-core `meta` | 是 |
  | perf | `perf.bb` | openembedded-core `meta` | 是 |
  | strace | `strace_6.19.bb` | openembedded-core `meta` | 是 |
  | quilt | `quilt_0.69.bb` | openembedded-core `meta` | 是 |
  | trace-cmd | `trace-cmd_3.1.5.bb` | meta-openembedded `meta-oe` | 是 |

  结论：五个目标工具全部落在 base.yml 已加载的 `meta` + `meta-oe` 两层，**无需新增层、无需改 LAYERDEPENDS**。

- **image 基类**：`openembedded-core/meta/recipes-core/images/core-image-minimal.bb`，`inherit core-image`，`IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL}"`。新镜像用 `require` 该基类并 `IMAGE_INSTALL +=` 追加包组，不复制基类内容。

- **构建目标覆盖**：kas 5.5 顶层只接受单数 `target`，edition 内写 `targets:` 列表会被配置校验拒绝（实测 `DUMP_RC=2`）；edition 写单数 `target: yp-image-dev` 可被 `kas dump` 解析并覆盖（实测生效）。base.yml 的 `target: core-image-minimal` **保持不变**（只读变量，check-vars 断言），dev 镜像目标写入 `kas/editions/dev.yml` 的 `target:`。prod 镜像用 `kas build --target yp-image-prod` 命令行覆盖，不改 prod.yml 既有断言行。

- **缓存按 edition 隔离**（plan §3.3）：dev 构建用独立 `SSTATE_DIR = "/work/sstate/dev"`，`DL_DIR` 仍共享 `/work/downloads`。base.yml 的 `SSTATE_DIR = "/work/sstate"` 保持不动（check-vars 断言 G5 只读），隔离只在 dev edition 生效。验收需证明 dev 缓存不写入 prod 路径 `/work/sstate`。

- **资源口径**：宿主 32c / `MemTotal=129308484 kB`（约 123 GiB，达 32c/128G 基线）；Docker daemon `NCPU=32 MemTotal=132411887616`；构建容器 `NanoCpus=0 Memory=0 CpuQuota=0`（未加 `--cpus`/`--memory`/`--cpu-quota`/`--cpuset-cpus`）。容器以 jenkins(uid 1000) 运行。无 `/dev/kvm` 与构建无关（bitbake 不需 KVM）；S3 起 QEMU 才涉及 TCG。

- **缓存现状**：`/work/downloads` 5.8G、`/work/sstate` 4.7G（6947 个 sstate 对象）；`strace`/`trace-cmd` 源码 tarball 不在当前 DL_DIR，dev 构建允许联网拉取小源码包（非 11 GiB 全量下载）。`gdb`/`quilt` 源码已在 DL_DIR。

- **builder**：`ghcr.io/zeek-zhao/yp-builder:wrynose-m0`（本地已有），kas 5.5，非 root。

## 3. 配方设计

### 3.1 三个包组（`meta-yp-distro/recipes-core/packagegroups/`）

| 配方 | 内容 | 用途 |
|---|---|---|
| `packagegroup-yp-base.bb` | `bash`、`coreutils`、`busybox`、`util-linux`、`procps`、`findutils`、`tar`、`gzip` | 两个镜像共用的最小可用基础命令集；不含任何调试/性能工具 |
| `packagegroup-yp-devtools.bb` | `gdb`、`gdbserver`、`strace`、`quilt`、`gdb` 的运行库依赖由 OE 自动带 | 目标侧可运行的开发/调试工具（D-01 目标层） |
| `packagegroup-yp-kernel-tools.bb` | `perf`、`trace-cmd` | 目标侧性能/追踪工具（D-01 目标层） |

均 `inherit packagegroup`，用 `RDEPENDS:packagegroup-yp-<name>` 声明，`SUMMARY`/`LICENSE`（MIT）齐全。写法参考 oe-core `packagegroup-core-buildessential.bb`，不复制多版本兼容层（约束 4）。

> `gdbserver` 单独列出而非靠 `gdb` 传递：它是 `gdb_17.2.bb` 显式切出的 package，验收命令按名 grep，必须显式出现在 dev 镜像清单里。

### 3.2 两个镜像（`meta-yp-distro/recipes-core/images/`）

- `yp-image-dev.bb`：`require recipes-core/images/core-image-minimal.bb`；`IMAGE_INSTALL += "packagegroup-yp-base packagegroup-yp-devtools packagegroup-yp-kernel-tools"`；`IMAGE_FSTYPES = "ext4"`；保留 base 基类其余行为。
- `yp-image-prod.bb`：`require` 同一基类；`IMAGE_INSTALL += "packagegroup-yp-base"`（只有基础包组，**不装 devtools/kernel-tools**）；`IMAGE_FSTYPES = "ext4"`；作为 D-04 负向对照。

两镜像 `SUMMARY` / `LICENSE` 齐全；不设 `ROOTFS_POSTPROCESS_COMMAND` 裁剪（D-04 靠「没装」而非「装完删除」，避免残留符号/配方的争议）。

### 3.3 kas 变更

`kas/editions/dev.yml` 在现有 `dev:` 块内追加：

```
SSTATE_DIR = "/work/sstate/dev"
target: yp-image-dev
```

`target:` 属 kas 顶层 schema，置于 `local_conf_header` 之外；`SSTATE_DIR` 置于 `dev:` 块内（bitbake 变量）。`kas/editions/prod.yml` **不改**。

`docs/m0/variable-index.md` 增补两行（SSTATE_DIR 的 dev edition 覆盖、target 的 dev edition 值）；`scripts/check-vars.sh` 的 RULES 保持只读断言不变（dev 覆盖不削弱 base 只读契约）。

## 4. 失败模式与检测

| # | 失败模式 | 检测信号 | 处理 |
|---|---|---|---|
| F1 | 目标工具配方不在已加载层 | `kas build` 报 `Nothing PROVIDES` / `No recipes available for` | 已探测全部在 `meta`/`meta-oe`；若仍发生，开 ISS 并检查 LAYERDEPENDS，不擅自加层 |
| F2 | edition 多 target 写法被拒 | `kas dump` 配置校验 exit 2 | 已探测；用单数 `target:`，prod 用 `--target` 覆盖 |
| F3 | dev 缓存写进 prod 路径 | 构建后 `/work/sstate` 新增 dev 专属 hash 目录 / RV 记录 mtime 变化 | dev.yml 设 `SSTATE_DIR=/work/sstate/dev`；验收对比两路径，dev 对象落在 dev 子目录 |
| F4 | prod 误带调试工具 | `oe-pkgdata-util list-pkg yp-image-prod` grep 命中 gdbserver/perf/strace/trace-cmd | prod 只装 base 包组；负向断言命中即 FAIL 并开 ISS |
| F5 | dev 缺工具 | dev 清单 grep 不命中 / QEMU 内 `which` 落空 | 核对包组 RDEPENDS 与镜像 `IMAGE_INSTALL`；缺项开 ISS |
| F6 | `strace`/`trace-cmd` 源码拉取失败 | do_fetch 网络错误 | dev 允许联网；记录实际拉取包；不因下载失败写「已验证」 |
| F7 | 缓存隔离导致 dev 首编超时 | `kas build` 超时 / BB 任务失败 | 分 dev/prod 两次构建、记录耗时；dev 独立 sstate 不共享 prod；不降级为「跳过构建」 |
| F8 | 校验脚本漂移 | `gate.sh` / `check-vars.sh` 非 0 | 新增配方不改受保护变量行；variable-index 增补后复跑 drift=0 |

## 5. 验收命令与期望输出

```bash
# 设计阶段已确认工具配方与 target 覆盖写法；实现提交后回填真实构建输出。
docker exec -w /work/probe yp-m1-build kas build kas/yp.yml:editions/dev.yml
# 期望：yp-image-dev-qemux86-64.ext4 产出，target=yp-image-dev，SSTATE_DIR=/work/sstate/dev

docker exec -w /work/probe yp-m1-build kas build kas/yp.yml:editions/prod.yml --target yp-image-prod
# 期望：yp-image-prod-qemux86-64.ext4 产出

docker exec yp-m1-build bash -c 'oe-pkgdata-util list-pkg yp-image-dev | grep -E "gdbserver|perf|strace|trace-cmd"; echo DEV_RC=$?'
docker exec yp-m1-build bash -c 'oe-pkgdata-util list-pkg yp-image-prod | grep -E "gdbserver|perf|strace|trace-cmd"; echo PROD_RC=$?'
# 期望：DEV_RC=0（至少四个命中）、PROD_RC=1（无命中）

# QEMU 内 which（用 S0 的 qemu-run.sh 起 dev/prod 镜像，注入 which 检查）
# 期望：dev 全部命中；prod 无输出

# 缓存隔离证据
docker exec yp-m1-build bash -c 'test -d /work/sstate/dev && echo DEV_SSTATE_EXISTS'

# 门禁
bash -n scripts/*.sh scripts/*/*.sh 2>/dev/null; bash scripts/gate.sh; bash scripts/check-vars.sh
```

**证据要求**：两个 ext4 产物 `ls -lh` 与 `file`；dev/prod 包清单 grep 原始输出与 rc；QEMU 内 which 原始输出；dev sstate 独立目录证据；实际 `nproc`/`MemTotal`/容器三项 0/0/0；构建耗时。任何未跑的命令在 RV 中写 `UNVERIFIED`，不写「已通过」。

## 6. 回滚

删除 `meta-yp-distro/recipes-core/packagegroups/packagegroup-yp-*.bb`、`meta-yp-distro/recipes-core/images/yp-image-*.bb`，撤销 `kas/editions/dev.yml` 与 `docs/m0/variable-index.md` 的增补即可；不改 base.yml、不改 M0 文件/配置/tag；已生成的 dev sstate 目录 `/work/sstate/dev` 为构建产物、不在仓库回滚范围，可按需删除。无跨 Stage 影响（S0 脚本与证据不动）。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建 S1 dev/prod 镜像与三包组设计；含工具配方所在层、target 覆盖、缓存隔离的真实探测结论与失败模式 | zeek.zhao |
