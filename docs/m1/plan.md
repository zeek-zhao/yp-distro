# YP-M1-PLAN-001 · M1 开发者平台实施规划

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-PLAN-001 |
| 版本 | v0.3 |
| 状态 | Approved（D 组范围、D-01 两层解释、S0 前置、资源全量使用口径已确认；S0 待执行） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-27 |
| 上游 | [`yp-wrynose 发行版 PRD v0.1`](https://my.feishu.cn/docx/PA8kdIhZsoziwvxq3GVcNiVT6mh) §里程碑 M1、D 组 |
| 基线 | `m0.1.3` = `300007e`（`m0.1`=`91adcc5`、`m0.1.1`=`8cb0fc6`、`m0.1.2`=`8c28dc1` 冻结） |
| 分支 | `feat-m1-dev-platform`（从 `m0.1.3` 拉出） |
| 目标标签 | `m1.0`（M1 全部 P1 通过后）；`release-m1` 仅快进 |
| 不在范围 | M2 内核/驱动、M3 安全合规、M4 启动度量、M5 交付形态；BSP 真机适配；OTA；改 M0/M0.1 结论；移动旧 tag；`--force`；4c/8G 全冷构建 |

## 1. 结论

M1 的唯一目标是 **开发者平台（PRD D 组）**，不是“继续补 M0”，也不是提前做内核或安全。

M1 出口只有一句话：**构建、devshell 改代码、deploy-target、gdbserver 调试四步流程在 CI 中稳定通过。** 其余 D 项是这条链路的组成部分，不是各自独立的 demo。

M1 的交付物：

- `yp-image-dev`（可写、带调试工具）；
- `yp-image-prod`（不残留调试工具，作为 D-04 负向对照）；
- `base / devtools / kernel-tools` 三个包组；
- `populate_sdk_ext` 产出的 eSDK；
- `deploy-target` 脚本与 QEMU 目标；
- `gdbserver` / `gdb` / `debuginfod` 调试链路；
- `buildhistory`、`yocto-check-layer` 门禁；
- 四步流程 CI（3 次连续通过才算“稳定”）。

## 2. 现状与差距（实测）

| 现状 | 事实 | 对 M1 的影响 |
|---|---|---|
| 发行版层 | `meta-yp-distro` 只有 `layer.conf`、`yp-wrynose.conf`、`yp-concurrency.bbclass` | 没有 image、packagegroup、recipe；D-01/D-04 从零开始 |
| 构建目标 | `kas/base.yml` 的 `target` 仍是 `core-image-minimal` | 没有 `yp-image-dev` / `yp-image-prod`；D-04 无法验收 |
| dev edition | `kas/editions/dev.yml` 只有 `debug-tweaks`、`DEBUG_FLAGS=-g` | 没有 devtools/kernel-tools 包组；D-01 不成立 |
| 启动 | M0 只验证 `.ext4` 的 `file` 类型；仓库无 `runqemu` / 串口采集脚本 | D-03/D-09 需要目标机；M1 必须先补 QEMU 启动基线 |
| eSDK | 无 `populate_sdk_ext` 产物、无 SDK 安装/使用脚本 | D-02 无落点 |
| 调试 | 无 `gdbserver`、`gdb`、`debuginfod`、`minidebuginfo` 配置 | D-05 无落点 |
| CI | `m0-gate.yml` 只跑静态门禁；`m0.yml` 只发布镜像/缓存，均不跑 bitbake | D-09 需要新的 M1 构建 + 四步流程 job |
| 缓存 | M0 的 `SSTATE_DIR=/work/sstate` 为共享路径 | M1 dev 必须按 edition 隔离，避免污染 prod 缓存 |

## 3. 关键解释与决策

### 3.1 D-01 拆成“宿主 SDK”和“目标镜像”两层

PRD 写“镜像内提供 devtool、recipetool、devshell、python devshell、quilt、gdbserver、perf、strace、trace-cmd”。其中：

- `devtool`、`recipetool`、`devshell`、`python devshell`、`quilt` 是 **宿主/eSDK 工具**，不装进 rootfs；
- `gdbserver`、`perf`、`strace`、`trace-cmd` 是 **目标镜像工具**，进 `yp-image-dev`；
- 不把 `devtool` 强行塞进 rootfs；若要求字面“镜像内”，须单开 CHG/偏离，不建议。

D-01 验收按两层分别取证，不把“宿主有 devtool”写成“镜像内有 devtool”。

### 3.2 M1-S0 是 M1 的前置，不是新增 PRD 需求

M0 没有做 QEMU 启动，D-03/D-09 无法落地。M1-S0 只补“目标能启动、串口能采集”的基线，不扩张到 M2 内核调试。

### 3.3 缓存按 edition 隔离

`yp-image-dev` 使用独立 `SSTATE_DIR`（建议 `/work/sstate/dev`），不直接写 M0 的 `/work/sstate`；DL_DIR 可共享。验收要看到 dev 构建不把 dev 缓存写入 prod 缓存路径。

### 3.4 CI 资源口径（已确认）

四步 CI 跑在 **GitHub-hosted `ubuntu-latest`**，不预设核数/内存，也**不使用 self-hosted 32c/128G runner**。所有构建容器不加 `--cpus` / `--memory` / `--cpu-quota` / `--cpuset-cpus`，机器有多少就用多少；每次记录实际 `nproc` / `MemTotal`，低于 32c/128G 标 `RESOURCE_PARTIAL`，达到基线才可写 full-quota。CI 只跑缓存增量（GHCR 预热缓存 + 分 job），不跑全冷构建；本地构建证据与 CI 证据分列，不互相替代。

## 4. Stage 规划

每个 Stage 一个提交、一个 DES/RV 记录，提交后停下等评审；不一次做完再补记录。

### M1-S0 · QEMU 启动与串口基线

**目的**：让 `core-image-minimal` 在 QEMU 中可重复启动，产出串口日志，作为后续 deploy/debug 的靶子。

**交付**：

- `docs/m1/design/S0-qemu-boot.md`；
- `scripts/dev/qemu-run.sh`：启动 QEMU、串口落盘、超时退出、打印 `BOOT_OK`；
- `scripts/dev/qemu-smoke.sh`：调用 run，断言登录提示/关键行；
- 不改 `kas` 目标，先把 M0 产物跑起来。

**验收**：

```bash
# 容器内，已有 core-image-minimal 产物
bash scripts/dev/qemu-run.sh --image <ext4> --timeout 180 --log /tmp/qemu.log
grep -q 'login:' /tmp/qemu.log && echo BOOT_OK
```

必须贴 `BOOT_OK`、串口日志路径、QEMU 命令与超时；没有 `/dev/kvm` 时用 TCG，记录实际耗时，不声称硬件加速。

### M1-S1 · dev/prod 镜像与三个包组（D-04、D-01 目标侧）

**目的**：把“dev 镜像有工具、prod 镜像无残留”变成可构建、可检查的镜像。

**交付**：

- `meta-yp-distro/recipes-core/packagegroups/packagegroup-yp-base.bb`
- `.../packagegroup-yp-devtools.bb`
- `.../packagegroup-yp-kernel-tools.bb`
- `meta-yp-distro/recipes-core/images/yp-image-dev.bb`
- `meta-yp-distro/recipes-core/images/yp-image-prod.bb`
- `kas/editions/dev.yml` 增加 dev 缓存隔离与镜像目标；
- devtools 包组至少：`gdbserver`、`gdb`、`perf`、`strace`、`trace-cmd`、`quilt`（目标侧只放可运行工具）。

**验收**：

```bash
kas build kas/yp.yml:editions/dev.yml
# 产物存在
ls -lh build/tmp/deploy/images/qemux86-64/yp-image-dev-qemux86-64.ext4
# 包清单与负向对照
oe-pkgdata-util list-pkg yp-image-dev | grep -E 'gdbserver|perf|strace|trace-cmd'
oe-pkgdata-util list-pkg yp-image-prod | grep -E 'gdbserver|perf|strace|trace-cmd' && exit 1 || true
```

QEMU 内 `which gdbserver perf strace trace-cmd` 全部命中；prod 镜像同命令应无输出。

### M1-S2 · eSDK 与宿主 devtool 链路（D-01 宿主侧、D-02）

**目的**：产出可安装的 eSDK，能在宿主机完成 `devtool add/modify/build`。

**交付**：

- `docs/m1/design/S2-esdk.md`；
- eSDK 构建目标：`bitbake yp-image-dev -c populate_sdk_ext`；
- `scripts/dev/install-sdk.sh`：安装到指定 prefix，输出 `SDK_INSTALL_OK`；
- `scripts/dev/devtool-smoke.sh`：`devtool add` / `modify` / `build` 的最小样例；
- `devtool ide-sdk` 只做可用性检查（`--help` 或非交互 smoke）；不在本轮承诺 IDE 全链路。

**验收**：

```bash
bitbake yp-image-dev -c populate_sdk_ext
ls -lh build/tmp/deploy/sdk/*.sh
bash scripts/dev/install-sdk.sh --installer <sdk.sh> --prefix /tmp/yp-sdk
source /tmp/yp-sdk/environment-setup-*
devtool --help
bash scripts/dev/devtool-smoke.sh
```

必须贴 `SDK_INSTALL_OK`、`devtool add/modify/build` 输出；`devshell` 为交互式，CI 不跑，记录“本地/伪终端已验证”或 `UNVERIFIED`。

### M1-S3 · deploy-target 与调试链路（D-03、D-05）

**目的**：一条命令把改过的程序部署到 QEMU，并能用 gdbserver 远程断点。

**交付**：

- `scripts/dev/deploy-target.sh --target qemu --binary <path>`：部署并打印 `DEPLOY_OK`；
- `scripts/dev/gdb-connect.sh`：启动 gdbserver / 连接 / 批处理断点；
- `yp-image-dev` 增加 `gdbserver`、`gdb`、`debuginfod`/`minidebuginfo` 相关配置；
- QEMU 端口转发（slirp）与目标 SSH/串口路径写清楚；
- D-05 验收要覆盖：无符号表时 gdb 能定位源码行、远程断点能命中。

**验收**：

```bash
bash scripts/dev/deploy-target.sh --target qemu --binary /tmp/yp-demo
# 目标机执行改过的二进制，输出 marker
bash scripts/dev/gdb-connect.sh --target qemu --break yp_demo_main
```

必须贴 `DEPLOY_OK`、目标机 marker、`GDB_BREAKPOINT_HIT`、`SOURCE_LINE_OK`；`debuginfod` 未跑通就写 `UNVERIFIED`，不能把 gdbserver 通过写成 D-05 全通过。

### M1-S4 · buildhistory、层自检与四步 CI（D-06、D-08、D-09；D-07 可选）

**目的**：把开发者平台变成可回归的 CI 能力，而不是本地手工 demo。

**交付**：

- `BUILDHISTORY_DIR` / `BUILDHISTORY_COMMIT` 配置与产物归档；
- `scripts/ci/check-layer.sh`：运行 `yocto-check-layer`，并用一个故意不合规的临时层做负向测试；
- `scripts/dev/four-step.sh`：build → devtool modify/build → deploy-target → gdbserver；
- `.github/workflows/m1-dev.yml`：`ubuntu-latest` 上拆 `gate` / `build-dev` / `four-step` 三个 job，使用 GHCR 预热缓存；容器不加资源限制，所有 job 打印实际 `nproc`/`MemTotal`，低于 32c/128G 才标 `RESOURCE_PARTIAL`；
- `D-07 bblock` 为 P2，不进入 M1 gate；有余量再做。

**验收**：

```bash
# buildhistory 两次构建差异可读
bitbake yp-image-dev && bitbake yp-image-dev
buildhistory-diff ...
# 层自检正/负向
bash scripts/ci/check-layer.sh
# 四步流程
bash scripts/dev/four-step.sh --target qemu
```

CI 要连续 **3 次** green，且四步分别有日志段；一次通过只能写“单次通过”，不能写“稳定通过”。

### M1-S5 · 验收、追溯与 `m1.0`

**目的**：把 D 组 P1 的结论、证据、分支/tag 收口。

**交付**：

- `docs/m1/acceptance.md`（D-01…D-09 逐项，D-07 标 P2/可选）；
- `docs/m1/traceability.md`（需求 → 设计 → 提交 → 证据 → 验收）；
- `docs/m1/reviews/RV-*`（四问 + 真实输出）；
- `m1.0` annotated tag；`release-m1` 快进；
- `m0.1.3` 及之前 tag 不动。

**验收**：

- D-01/D-02/D-03/D-04/D-05/D-06/D-08/D-09 全通过；
- 四步 CI 3/3；
- `GATE_PASS` / `VARS_OK` / 提交身份 / 无 token / 无大二进制；
- `m1.0` 与 `release-m1` 指向同一最终提交，未 force。

## 5. 验收矩阵

| 需求 | 验收证据 | Stage |
|---|---|---|
| D-01 | 宿主 eSDK `devtool add/modify/build`；目标镜像 `gdbserver/perf/strace/trace-cmd` 可执行 | S1/S2 |
| D-02 | `populate_sdk_ext` 产物、SDK 安装、宿主机 cross 编译 | S2 |
| D-03 | `deploy-target.sh` 一条命令，目标机 marker 生效 | S3 |
| D-04 | 三包组存在；dev 有工具、prod 无调试工具残留 | S1 |
| D-05 | gdbserver 远程断点命中；gdb 定位源码行；debuginfod/minidebuginfo 有证据或 UNVERIFIED | S3 |
| D-06 | 两次构建的 buildhistory diff 可读并归档 | S4 |
| D-07 | bblock 锁定某 recipe 后不重编（P2，不阻断 M1） | S4 可选 |
| D-08 | `yocto-check-layer` 正向通过 + 临时坏层负向失败 | S4 |
| D-09 | 四步流程在 GitHub-hosted `ubuntu-latest` 连续 3 次 green；每次用 runner 实际全部资源，记录 `nproc`/`MemTotal`，低于 32c/128G 才标 `RESOURCE_PARTIAL` | S4 |

## 6. 分支与发布线

| ref | 规则 |
|---|---|
| `m0.1.3` | 基线，冻结不动 |
| `feat-m1-dev-platform` | M1 工作分支，从 `m0.1.3` 拉 |
| `m1.0` | M1 全部 P1 通过后的 annotated tag |
| `release-m1` | 仅快进到 `m1.0`，不 force |
| M2 | 从 `m1.0` 拉，不从 `m0.1.3` 拉 |

## 7. 风险与未决

| 风险 | 应对 |
|---|---|
| QEMU 在容器内无 KVM，启动慢/超时 | 用 TCG，超时阈值按实测设；不把 TCG 通过写成硬件加速 |
| eSDK 构建体积大、CI 超时 | SDK job 独立缓存；按 runner 实际资源分 job，超时则拆 job 或改手动，不降级成“未跑也通过” |
| gdbserver 端口转发复杂 | 先 QEMU slirp 固定端口，失败再退到串口/本地 gdbstub，但 D-05 只认 gdbserver 证据 |
| debuginfod 依赖 host 服务 | 先做本地最小服务；跑不通标 UNVERIFIED，不用 gdbserver 冒充 D-05 通过 |
| 四步 CI 在 hosted runner 资源不足 | 用 runner 实际全部资源；不足 32c/128G 时标 `RESOURCE_PARTIAL`，不引入 self-hosted，不写 full-quota PASS |
| `devtool` 字面“进镜像”与工程实际冲突 | 按 §3.1 两层实现；如坚持字面，单开 CHG/偏离 |

**已确认（2026-11-27）**：

1. D-01 接受“宿主 SDK + 目标镜像”两层解释；
2. M1-S0 的 QEMU 启动基线作为 M1 前置；
3. CI 无 self-hosted 32c/128G，跑 GitHub-hosted；资源按 runner 实际全部使用，不预设核数/内存，低于基线才标 `RESOURCE_PARTIAL`；
4. D-05 的 debuginfod 仍在 M1 范围内；未闭环则 D-05 不通过，M1 不宣称全 P1，留 M1.1 补。

## 8. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v0.1 | 2026-11-27 | 建立 M1 开发者平台规划：D 组范围、S0–S5、验收矩阵、分支/tag、风险 | zeek.zhao |
| v0.2 | 2026-11-27 | 确认 D-01 两层解释、S0 为 M1 前置、CI 使用 GitHub-hosted（无 self-hosted）；D-05 debuginfod 未闭环则 M1 不宣称全 P1 | zeek.zhao |
| v0.3 | 2026-11-27 | 资源口径改为“机器有多少用多少、容器不加限制、记录实际值”；去掉固定 4c/16G 假设，低于 32c/128G 才标 RESOURCE_PARTIAL | zeek.zhao |
