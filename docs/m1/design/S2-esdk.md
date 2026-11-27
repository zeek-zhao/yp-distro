# YP-M1-DES-003 · M1-S2 eSDK 与宿主 devtool 链路设计

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-DES-003 |
| 版本 | v1.0 |
| 状态 | Approved（设计先行；本提交只含设计与四问评审，脚本在评审后单独提交） |
| 关联 | `docs/m1/plan.md` §M1-S2 §3.1；基线 `feat-m1-dev-platform`=`dd8463e`（S1 已合入并 push）；S1 产物 `yp-image-dev` 为 eSDK target |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-28 |

## 1. 目的与不做的事

**目的**：把「宿主可安装 eSDK、在宿主机完成 `devtool add/modify/build`」从规划变成可构建、可安装、可冒烟的链路。落地两个脚本（`install-sdk.sh` / `devtool-smoke.sh`），使 D-01 **宿主侧**与 D-02（可安装 eSDK）可取证：用 S1 的 `yp-image-dev` 跑 `populate_sdk_ext` 产出 install-only/ext SDK，安装到指定 prefix 后 `source environment-setup-*` 即可用 devtool。

**不做**（plan §M1-S2 边界）：不写 `deploy-target` / `gdb-connect` / gdbserver 远程断点 / debuginfod（S3）；不写 buildhistory / yocto-check-layer / 四步 CI / `m1-dev.yml`（S4）；不打 `m1.0`、不改 M0 tag 与结论、不建 M2 分支；不新增 PRD 之外的需求。

**D-01 两层口径**（plan §3.1）：本 Stage 只做**宿主/eSDK 层**——`devtool`/`recipetool`/`devshell`/`python devshell` 由 eSDK 的 buildtools 提供，安装在宿主 prefix，不进 rootfs。目标镜像层（gdbserver/perf/strace/trace-cmd）已在 S1 验证，本 Stage 不重复、不冒领。

**IDE 口径**（plan §M1-S2）：`devtool ide-sdk` 只做可用性检查（`--help` / 非交互 smoke），**不在本轮承诺 IDE 全链路**（需 host IDE、GUI、pty，CI 不跑）。

## 2. 输入与前提（容器内 `kas checkout` 固定 commit 实测，非推测）

- **eSDK 任务由 image.bbclass 自动附带**：`openembedded-core/meta/classes-recipe/image.bbclass:18` 有 `IMGCLASSES += "${@['', 'populate_sdk_ext']['linux' in d.getVar("SDK_OS")]}"`。实测 `bitbake -c listtasks yp-image-dev` 输出含 `do_populate_sdk_ext`。因此 **yp-image-dev.bb 无需改动**，plan §M1-S2 的 `bitbake yp-image-dev -c populate_sdk_ext` 可直接执行。
  - 负向实测：在 local.conf 全局 `INHERIT += "populate_sdk_ext"` 会报 `ParseError: Could not inherit file classes/populate_sdk_ext.bbclass`（类在 `classes-recipe/`，非 `classes/`），故**不用全局 INHERIT**，也不改配方。
- **SDK 命名变量（实测 `bitbake -e yp-image-dev`）**：
  - `SDK_DEPLOY = "/work/s1build/build/tmp/deploy/sdk"`；
  - `SDK_NAME = "yp-wrynose-glibc-x86_64-yp-image-dev-x86-64-v3-qemux86-64"`；
  - `SDK_VERSION = "0.1.0"`；
  - `TOOLCHAINEXT_OUTPUTNAME = "yp-wrynose-glibc-x86_64-yp-image-dev-x86-64-v3-qemux86-64-toolchain-ext-0.1.0"`。
  - installer 期望路径：`${SDK_DEPLOY}/${TOOLCHAINEXT_OUTPUTNAME}.sh`。**installer 名含 distro/arch/镜像名/版本，脚本不得硬编码**（`install-sdk.sh` 用 `--installer` 显式传参；探测命令用 `ls $SDK_DEPLOY/*.sh` 通配）。
- **devtool 命令齐全（实测插件目录 `openembedded-core/scripts/lib/devtool/`）**：`build.py`、`ide_sdk.py`、`standard.py`（`add`/`modify` 由 standard 注册）、`sdk.py`、`export.py`。`add/modify/build/ide-sdk` 全部存在；`devtool --help` 非交互可用。
- **eSDK buildtools**：`populate_sdk_ext.bbclass` 安装 buildtools installer（含 devtool/recipetool）到 SDK 的 sysroot，安装后 `source <prefix>/environment-setup-*` 即可用。class 中 `WITHIN_EXT_SDK = "1"` 标记 ext SDK 上下文。
- **缓存与隔离**：eSDK 目标与 dev 镜像同 target（`yp-image-dev`），在 dev edition 构建，`SSTATE_DIR=/work/sstate/dev`（S1 已建，7189 对象），不写 prod 路径 `/work/sstate`。ext SDK 会额外构建 nativesdk/buildtools 链，属 dev 缓存域。
- **资源口径**：宿主 32c / `MemTotal=129308484 kB`；Docker daemon NCPU=32；构建容器 `NanoCpus=0 Memory=0 CpuQuota=0`（无限制）。**但嵌套沙箱宿主 shell cgroup memory.max=8G**（AGENTS §2.1），S1 实测 32×16 并发全量编译触发 OOM（ISS-M1-002）。S2 延续 `RESOURCE_PARTIAL` 口径：用既有 `BB_NUMBER_THREADS` 机制临时降到 6/-j2（本地 overlay `/work/s1-lowconc.yml`，不入库），记录实际并发与内存峰值。
- **构建目录**：用独立干净目录 `/work/s2build`（避免 S1 的 dev/prod INHERIT 差异污染 datastore，ISS-M1-002 P4），从仓库 tar 拷贝（排除 `.git`/`downloads`/`sstate`/`cache-work*`）。DL_DIR 共享 `/work/downloads`。

## 3. 脚本设计

### 3.1 `scripts/dev/install-sdk.sh`

- 参数：`--installer <path>`（必填，SDK `.sh` installer）、`--prefix <path>`（必填，安装目标前缀）；`--help`。
- 行为：
  1. 校验 installer 存在且可执行（`test -x`），否则 `SDK_INSTALL_FAIL` 非 0；
  2. `mkdir -p <prefix>`；
  3. 以 `-y -d <prefix>` 非交互执行 installer（**已探测**：模板 `openembedded-core/meta/files/toolchain-shar-extract.sh:72` 为 `getopts ":yd:npDRSl"`，`:101` Usage `[-y] [-d <dir>]`、`:102` `-y` = Automatic yes；故 `-y` 免确认、`-d <dir>` 指定目录。脚本默认 `-y -d <prefix>`，并支持 `--` 透传覆盖）；
  4. 验证 `<prefix>/environment-setup-*` 存在（glob 命中）→ 打印 `SDK_INSTALL_OK prefix=<prefix>`；否则 `SDK_INSTALL_FAIL` 非 0。
- 不写仓库外持久状态之外的东西；prefix 由调用方给（验收用 `/tmp/yp-sdk*`）。不 source（source 由调用方/验收脚本做，避免子进程环境丢失）。
- 日志/错误一律 stdout/stderr，不落盘到仓库。

### 3.2 `scripts/dev/devtool-smoke.sh`

- 前置：调用方已 `source <prefix>/environment-setup-*`，脚本内检测 `command -v devtool`，缺失则 `DEVTOOL_SMOKE_FAIL` 非 0。
- 最小样例（在临时工作目录 `/tmp/yp-devtool-smoke-*` 内，不污染仓库）：
  1. `devtool --help` → 断言含 `add`/`build`/`modify`；
  2. `devtool ide-sdk --help` → 可用性检查（非交互；若该版本不支持则记 `IDE_SDK_UNAVAILABLE`，非阻断）；
  3. `devtool add` / `modify` / `build`：用最小本地 make 样例走 add → build → `reset -n` → modify → build → reset 流程。**add 与 modify 对同一 recipe 互斥**（add 后 recipe 已在 workspace，modify 同名报 `already in your workspace`，实测），故 modify 用 SDK 内现成 recipe（默认 `m4`，`--modify-recipe` 可配）。每一步打印真实输出与 rc；任一步非 0 → `DEVTOOL_SMOKE_FAIL`。
- 输出 `DEVTOOL_SMOKE_OK` 仅当 add/modify/build 三步均成功；`ide-sdk` 单独标 `IDE_SDK_HELP_OK` 或 `UNAVAILABLE`，不并入主结论。
- 不在仓库内创建 recipe/workspace；临时目录用 `mktemp -d`，结束时清理（或保留路径供取证，记录于 RV）。
- 交互 `devshell` / `devshell -p` 不跑（plan 明示 CI 不跑），记录 `UNVERIFIED`。

### 3.3 配方与 kas

- **不改** `meta-yp-distro/recipes-core/images/yp-image-dev.bb`（探测证明 image.bbclass 自动附带 `populate_sdk_ext` 任务，无需继承或改配方）。
- **不改** kas 配置：仍用 `kas/yp.yml:kas/editions/dev.yml` 构建，dev.yml 的 `SSTATE_DIR=/work/sstate/dev` 与 `target: yp-image-dev` 保持 S1 状态（只读断言不漂移）。
- 新增文件仅两个脚本；`docs/m0/variable-index.md` 本 Stage 不新增变量（无新 bitbake 变量/kas 覆盖），不改。

## 4. 失败模式与检测

| # | 失败模式 | 检测信号 | 处理 |
|---|---|---|---|
| F1 | `populate_sdk_ext` 任务不存在 | `bitbake -c listtasks` 无 `do_populate_sdk_ext` / `No such task` | 已探测任务存在；若发生开 ISS，核对 image.bbclass IMGCLASSES/SDK_OS，不擅自全局 INHERIT |
| F2 | ext SDK 构建 OOM 或超长编译（buildtools + llvm/clang native 链） | `Killed` / `Error 137` / do_compile 失败 / 编译耗时数十分钟至数小时 | 用 6/-j2 本地 overlay（ISS-M1-002 机制），不写「已通过」；实测 dev edition 未裁图形特性使 `populate_sdk_ext` 拉入 llvm-native（3472 步）+ clang-native（2282 步）全编，耗时显著；内存峰值与耗时 Recording 于 RV |
| F3 | installer 名/路径不符预期 | `ls $SDK_DEPLOY/*.sh` 空 / `TOOLCHAINEXT_OUTPUTNAME` 与文件不符 | 脚本用 `--installer` 传参 + 通配探测，不硬编码名；记录真实文件名 |
| F4 | installer 非交互参数错误 | installer 退出非 0 / prefix 无 environment-setup | 实现时读 installer `--help` 确认 `-y`/`-d` 用法；失败开 ISS |
| F5 | devtool 在 SDK 中缺失 | `source environment-setup` 后 `command -v devtool` 空 | 核对 buildtools installer 是否装入；缺项开 ISS，不写「已验证」 |
| F6 | devtool add/modify/build 失败 | 任一步 rc≠0 / 报错 | 用最小样例定位；非 0 → DEVTOOL_SMOKE_FAIL；样例兼容性问题开 ISS |
| F7 | 同目录 edition 污染 | `basehash changed` / `No such task: do_rm_work` | 用独立 `/work/s2build`，不复用 S1 build 目录（ISS-M1-002 P4） |
| F8 | 校验脚本漂移 | `gate.sh` / `check-vars.sh` 非 0 | 新增脚本不改受保护变量行；复跑 drift=0 |
| F9 | devshell 交互未验证被误写通过 | RV 措辞 | 如实标 `UNVERIFIED`（CI/非 pty 不跑），不冒充 |

## 5. 验收命令与期望输出

```bash
# eSDK 构建（dev edition，独立目录，低并发 overlay）
docker exec -w /work/s2build yp-m1-build \
  kas build kas/yp.yml:kas/editions/dev.yml:/work/s1-lowconc.yml \
  --target yp-image-dev -c populate_sdk_ext
# 期望：SDK_DEPLOY/*.sh 产出；BUILD_RC=0（或如实记录客户端收尾卡住但产物落盘）

# 定位 installer（不硬编码名）
docker exec yp-m1-build bash -c 'ls -lh /work/s2build/build/tmp/deploy/sdk/*.sh'

# 安装（宿主可执行 installer：ext SDK installer 为宿主架构可运行）
bash scripts/dev/install-sdk.sh --installer <sdk.sh> --prefix /tmp/yp-sdk
# 期望：SDK_INSTALL_OK prefix=/tmp/yp-sdk

# devtool 链路
bash -c 'source /tmp/yp-sdk/environment-setup-* && devtool --help'
bash -c 'source /tmp/yp-sdk/environment-setup-* && bash scripts/dev/devtool-smoke.sh'
# 期望：devtool --help 含 add/build/modify；DEVTOOL_SMOKE_OK；ide-sdk help OK 或 UNAVAILABLE（非阻断）

# 门禁
bash -n scripts/dev/*.sh; bash scripts/gate.sh; bash scripts/check-vars.sh
```

**证据要求**：installer `ls -lh` 与文件名；`SDK_INSTALL_OK` 原始输出；`devtool --help`/`add`/`modify`/`build`/`ide-sdk --help` 原始输出与 rc；`DEVTOOL_SMOKE_OK`；实际 `nproc`/`MemTotal`/容器三项 0/0/0/内存峰值；构建耗时与并发口径（`RESOURCE_PARTIAL`）。任何未跑的命令在 RV 写 `UNVERIFIED`，不写「已通过」。

## 6. 回滚

删除 `scripts/dev/install-sdk.sh`、`scripts/dev/devtool-smoke.sh` 与本文/评审文档即可；不改任何配方/kas/base.yml/M0 文件/配置/tag；SDK 产物、安装 prefix、构建目录均在 `/work` 与 `/tmp`，不在仓库回滚范围，可按需删除。无跨 Stage 影响（S0/S1 脚本与证据不动）。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建 S2 eSDK 与宿主 devtool 链路设计；含 populate_sdk_ext 自动附带、installer 命名、devtool 命令、RESOURCE_PARTIAL 的真实探测结论与失败模式 | zeek.zhao |
