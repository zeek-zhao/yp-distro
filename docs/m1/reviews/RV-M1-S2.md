# YP-M1-RV-003 · M1-S2 eSDK 与宿主 devtool 链路评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-003 |
| 版本 | v1.0 |
| 评审对象 | YP-M1-S2 设计（DES-003）；实现（两个脚本）待评审后单独提交 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-28 |
| 关联 | `docs/m1/plan.md` §M1-S2 §3.1；`docs/m1/design/S2-esdk.md`（DES-003）；S1=`dd8463e`（已 push） |
| 结论 | 设计通过（Q1–Q4）；实测构建/安装/devtool smoke 待实现提交后回填，**当前不宣称 S2 已通过** |

## 1. 四问自评

**Q1 覆盖需求**：S2 目标「宿主可安装 eSDK + devtool add/modify/build」由 `install-sdk.sh`（D-02 安装取证）+ `devtool-smoke.sh`（D-01 宿主侧 add/modify/build）覆盖；`devtool ide-sdk` 按 plan 只做 `--help` 可用性检查、不承诺 IDE 全链路；`devshell` 交互标 UNVERIFIED。明确不做 deploy/gdbserver(S3)、CI/tag(S4/m1.0)、不改 M0、不建 M2，不越界。D-01 目标镜像层已在 S1 验证，本 Stage 不冒领、不重复。✅

**Q2 失败模式列全且检测可执行**：设计 §4 列 9 类失败（任务缺失、OOM、installer 命名、非交互参数、devtool 缺失、smoke 失败、同目录污染、脚本漂移、devshell 误写），每类给检测信号与处理。F1/F3/F5 均为设计前实测发现（image.bbclass 自动附带、命名变量、devtool 插件），非理论推测；OOM/同目录污染来自 S1 的 ISS-M1-002 真实教训。✅

**Q3 验收可执行**：验收命令全部具体可执行（`kas build -c populate_sdk_ext`、`ls deploy/sdk/*.sh`、`install-sdk.sh`、`source environment-setup`、`devtool --help`、`devtool-smoke.sh`、`bash -n`/`gate`/`vars`），期望输出明确（`SDK_INSTALL_OK`/`DEVTOOL_SMOKE_OK`/`rc`）。installer 名不硬编码、用 `--installer` + 通配探测；未执行命令承诺写 `UNVERIFIED`，不写「已通过」。✅

**Q4 回滚可行**：删除两个脚本与本文/评审文档即可；不改配方/kas/base.yml/M0 文件/配置/tag（探测证明无需改配方，避免引入额外回滚面）；SDK/安装/构建产物均在 /work 与 /tmp，不在仓库回滚范围；无跨 Stage 影响。✅

## 2. 设计阶段探测证据（真实，容器内 `kas checkout` 固定 commit）

Builder 容器 `yp-m1-build`（jenkins/uid1000，kas 5.5，重启后缓存完整：dev sstate 7189 对象、`/work/s1-lowconc.yml` 在），资源口径：宿主 `nproc=32` `MemTotal=129308484 kB`；docker `NCPU=32 MemTotal=132411887616`；容器 `NanoCpus=0 Memory=0 CpuQuota=0`；宿主 shell cgroup `memory.max=8G`（S1 OOM 根因，ISS-M1-002）。

- `populate_sdk_ext` 任务：`image.bbclass:18` 的 `IMGCLASSES += "...populate_sdk_ext..."['linux' in SDK_OS]` 自动附带；实测 `bitbake -c listtasks yp-image-dev` 输出含 `do_populate_sdk_ext` → **配方无需改动**。
- 全局 `INHERIT += "populate_sdk_ext"` 负向：报 `ParseError: Could not inherit file classes/populate_sdk_ext.bbclass`（类在 `classes-recipe/`），故不用全局 INHERIT。
- SDK 命名（`bitbake -e yp-image-dev`）：`SDK_DEPLOY=/work/s1build/build/tmp/deploy/sdk`、`SDK_NAME=yp-wrynose-glibc-x86_64-yp-image-dev-x86-64-v3-qemux86-64`、`SDK_VERSION=0.1.0`、`TOOLCHAINEXT_OUTPUTNAME=...-toolchain-ext-0.1.0` → installer 名含 distro/arch/镜像/版本，**不硬编码**。
- devtool 命令插件（`openembedded-core/scripts/lib/devtool/`）：`build.py`、`ide_sdk.py`、`standard.py`（add/modify）、`sdk.py`、`export.py` 齐全；`ide-sdk` 在 `ide_plugins/` 存在（本 pin 支持）。
- eSDK buildtools：`populate_sdk_ext.bbclass` 安装 buildtools installer（含 devtool/recipetool）到 SDK sysroot，`WITHIN_EXT_SDK="1"` 标记 ext SDK 上下文。

以上为设计输入探测；构建/安装/devtool smoke 实测待实现提交后在 §3 回填。

## 3. 实测证据（实现提交后回填）

> 待回填：eSDK installer 产物、install-sdk.sh 的 `SDK_INSTALL_OK`、`source environment-setup` 后 devtool `--help`/`add`/`modify`/`build`/`ide-sdk --help` 原始输出与 rc、`DEVTOOL_SMOKE_OK`、构建耗时/并发/内存峰值、GATE/VARS、CI 状态。任何未执行命令写 `UNVERIFIED`。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S2 设计四问评审 + 设计阶段真实探测证据（populate_sdk_ext 自动附带、installer 命名、devtool 命令、RESOURCE_PARTIAL）；实测待回填 | zeek.zhao |
