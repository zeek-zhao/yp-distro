# YP-M1-RV-003 · M1-S2 eSDK 与宿主 devtool 链路评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-003 |
| 版本 | v1.1 |
| 评审对象 | YP-M1-S2 实现（install-sdk.sh + devtool-smoke.sh）；设计 DES-003 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-28 |
| 关联 | `docs/m1/plan.md` §M1-S2 §3.1；`docs/m1/design/S2-esdk.md`（DES-003）；S1=`dd8463e`；ISS-M1-003 |
| 结论 | S2 通过（Q1–Q4 + 实测）：eSDK 构建 BUILD_RC=0、安装 SDK_INSTALL_OK、devtool add/modify/build DEVTOOL_SMOKE_OK；标注 RESOURCE_PARTIAL（归档 xz OOM，降压缩参数后成功）。ide-sdk 仅可用性检查（本 pin UNAVAILABLE，非阻断），devshell UNVERIFIED；D-03/D-05 属 S3 |

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

## 3. 实测证据（实现提交后回填，builder 容器 TCG/无 KVM 与构建无关）

构建环境：`yp-m1-build` 容器，独立目录 `/work/s2build`；`nproc=32`、`MemTotal=129308484 kB`、容器 `NanoCpus=0 Memory=0 CpuQuota=0`；宿主 shell cgroup `memory.max=8G`（嵌套沙箱）。用既有 `BB_NUMBER_THREADS` 机制本地 overlay 降到 6/-j2（`/work/s1-lowconc.yml`，不入库）。结论标注 **RESOURCE_PARTIAL**。

### 3.1 构建过程（两次，如实）

| 尝试 | 命令 | 结果 |
|---|---|---|
| 1 | `kas build ...dev.yml:/work/s1-lowconc.yml --target yp-image-dev -c populate_sdk_ext` | 失败：`BUILD_RC=2`。6047 任务中 6046 成功（含 llvm-native 3472 步、clang-native 2282 步、mesa-native、qemu-system-native 全编），最后 `do_populate_sdk_ext`→`archive_sdk` 的 `xz --memlimit=50% --threads=32 -9` 被 SIGKILL（`Killed`、exit 137，嵌套沙箱 8G OOM）；tar.xz 0 字节，但 `sdk-ext/image/` 3.0G 完整。首次 sstate 76% match（Wanted 3298 Missed 785） |
| 2 | 同命令 + `/work/s2-lowxz.yml`（`SDK_XZ_COMPRESSION_LEVEL=-0`、`XZ_THREADS=2`、`XZ_MEMLIMIT=30%`） | **BUILD_RC=0**：`Attempted 6047 tasks of which 6044 didn't need to be rerun and all succeeded`；sstate 99% match（Wanted 404 Missed 2）；`do_populate_sdk_ext: Succeeded`，归档 7 分钟完成、无 OOM |

- 构建耗时：首编 `ESDK_START=17:32:38Z` → `ESDK_END=20:35:55Z`（约 3h03m，含 llvm/clang/mesa/qemu native 全编）；重试 `20:41:06` → `20:48:27`（约 7m，仅归档 + 2 任务）。
- 内存：首编峰值 `memory.peak≈7.5G`（6/-j2 编译 3 小时无 OOM）；归档阶段 32-thread xz 触发 OOM（ISS-M1-003）。
- eSDK 在 dev 独立 sstate：`/work/sstate/dev` 对象从 S1 的 7189 增至 9317（+2128），未写 prod 路径 `/work/sstate`（plan §3.3 保持）。

### 3.2 eSDK 产物与安装（真实）

```
installer: yp-wrynose-glibc-x86_64-yp-image-dev-x86-64-v3-qemux86-64-toolchain-ext-0.1.0.sh  2.9G  -rwxr-xr-x
           SDK_DEPLOY=/work/s2build/build/tmp/deploy/sdk
installer --help: Usage: ...sh [-y] [-d <dir>]  →  证实 install-sdk.sh 默认 -y -d <prefix> 正确
install-sdk.sh --installer <上述> --prefix /work/yp-sdk-test
  → SDK_INSTALL_OK prefix=/work/yp-sdk-test   (INSTALL_RC=0)
  → environment-setup-x86-64-v3-poky-linux 存在；ext SDK "SDK has been successfully set up"
```

### 3.3 devtool 宿主链路（真实，source environment-setup 后）

- `command -v devtool` → `/work/yp-sdk-test/layers/openembedded-core/scripts/esdk-tools/devtool`；`devtool --help` → rc=0，含 `add`/`build`/`modify`/`package`/`build-image` 等（D-01 宿主侧）。
- `devtool-smoke.sh --workdir /work/yp-devtool-smoke --keep` → **DEVTOOL_SMOKE_OK add=yp-smoke-hello modify=m4**，rc=0：
  - `devtool add yp-smoke-hello <make 样例>` → 成功（do_compile/do_package 完成）；
  - `devtool build yp-smoke-hello` → 成功；
  - `devtool reset -n yp-smoke-hello` → 清 workspace（add 与 modify 对同一 recipe 互斥，实测 `already in your workspace`，ISS-M1-003）；
  - `devtool modify m4`（oe-core 现成 recipe）→ 成功；`devtool build m4` → m4 do_compile/do_install/do_package 全 Succeeded；`devtool reset -n m4` → 清理。
- `devtool ide-sdk --help` → `IDE_SDK_UNAVAILABLE`（本 pin 该子命令 `--help` 退出非 0；非阻断，plan 明示 IDE 全链路不在本轮，仅做可用性检查）。
- `devshell` → `UNVERIFIED`（交互式，非 pty/CI 不跑，符合 plan §M1-S2）。

### 3.4 门禁与卫生

`bash -n scripts/dev/*.sh` → SYNTAX_OK；`bash scripts/gate.sh` → **GATE_PASS**；`bash scripts/check-vars.sh` → **VARS_OK checked=36 drift=0**；提交身份 `zeek.zhao <zeek.zhao@foxmail.com>`；无 token、无大二进制入库（eSDK 2.9G、installer、构建目录均在 /work 与 /tmp，不在仓库）。**配方/kas 未改**（探测证明 populate_sdk_ext 由 image.bbclass 自动附带），回滚面最小。

### 3.5 结论

**S2 通过（D-01 宿主侧、D-02）**：eSDK 可构建（BUILD_RC=0）、installer 可非交互安装（SDK_INSTALL_OK）、devtool add/modify/build 全链路真实执行通过（DEVTOOL_SMOKE_OK）。标注 `RESOURCE_PARTIAL`（嵌套沙箱 8G，归档阶段 xz OOM，降压缩参数后成功，非 full-quota）。`ide-sdk` 仅可用性检查（本 pin UNAVAILABLE，非阻断）；`devshell` 交互标 UNVERIFIED。D-03 deploy-target / D-05 gdbserver 远程断点属 S3，本 Stage 未验证。CI 状态见 §3.6。

### 3.6 CI 状态（如实）

两个提交（`fa652a3` 设计评审、`98b5ef5` 实现回填）用一次性凭据 push `feat-m1-dev-platform` 成功（`dd8463e..98b5ef5`，远端 HEAD=`98b5ef5`）；按 head_sha 与分支查询 GitHub Actions `total_count=0`——gate/publish workflow 的 push 分支限制为 `feat-m0*`/`release-m0*`，本分支 `feat-m1-*` 不匹配，故未触发 CI。与 S0/S1 同一口径：不为让 CI 跑而改 workflow paths（前序硬边界），以本地 GATE_PASS/VARS_OK 为质量证据，远端 CI 记「未触发（分支不匹配）」，不冒充 success。push 凭据经临时环境变量与一次性 git 参数传递，未写入 git config/仓库、未打印 token。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S2 设计四问评审 + 设计阶段真实探测证据（populate_sdk_ext 自动附带、installer 命名、devtool 命令、RESOURCE_PARTIAL）；实测待回填 | zeek.zhao |
| v1.1 | 2026-11-28 | 回填实测：eSDK 两次构建（首编归档 xz OOM BUILD_RC=2 → 降压缩 BUILD_RC=0）、installer 2.9G、SDK_INSTALL_OK、DEVTOOL_SMOKE_OK（add/modify/build）；记录 ISS-M1-003 两障碍（归档 OOM + add/modify 互斥）；RESOURCE_PARTIAL，S2 通过 | zeek.zhao |
