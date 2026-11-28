# YP-M1-DES-005 · M1-S4 buildhistory、层自检与四步 CI 设计

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-DES-005 |
| 版本 | v1.0（设计评审；实测待实现提交后回填） |
| 状态 | 设计评审中 |
| 责任人 | zeek.zhao |
| 关联 | `docs/m1/plan.md` §M1-S4、§3.4、§5、§7；上游 S3=`b858798`；评审 `docs/m1/reviews/RV-M1-S4.md` |
| 覆盖 | D-06（buildhistory diff 可读并归档）、D-08（yocto-check-layer 正/负向）、D-09（四步流程 CI）；D-07 bblock 为 P2 可选 |

## 1. 目标与边界

把 S0–S3 已验证的构建链路（build → eSDK/devtool → deploy-target → gdbserver）固化成**可回归、可归档**的 CI 能力，而不是本地手工 demo。M1 出口句：**构建、devshell 改代码、deploy-target、gdbserver 调试四步流程在 CI 中稳定通过（连续 3 次 green）**。

不做：不打 `m1.0`、不改 M0/M0.1 结论与 tag、不建 M2、不引入 self-hosted 32c/128G runner、不为让 CI 跑而改 M0 workflow 的 paths、不把 TCG 写成硬件加速、不把单次通过写成"稳定通过"。

## 2. 设计阶段真实探测事实（2026-11-28，容器 `yp-m1-build` / `s2build`）

### 2.1 buildhistory（D-06）

- oe-core `meta/classes/buildhistory.bbclass` 存在；关键变量实测默认值：
  - `BUILDHISTORY_FEATURES ?= "image package sdk"`
  - `BUILDHISTORY_DIR ?= "${TOPDIR}/buildhistory"`
  - `BUILDHISTORY_COMMIT ?= "1"`
  - `BUILDHISTORY_DIR_IMAGE = "${BUILDHISTORY_DIR}/images/${MACHINE_ARCH}/${TCLIBC}/${IMAGE_BASENAME}"`
- `scripts/buildhistory-diff` 存在，依赖 GitPython；容器内实测 `python3 -c 'import git'` → `3.1.37`，可用。
- `buildhistory-diff` 参数：`-p/--buildhistory-dir`、`-a/--report-all`、`-s/-S` 签名、`-e/--exclude-path`、`revisions`（两个 commit）。
- 现有 `s2build/build/conf/local.conf` 未启用 buildhistory（grep 无命中），需新增配置。

结论：D-06 技术路径成立。`BUILDHISTORY_DIR` 归口到 `kas/editions/dev.yml`（dev 专属，不污染 base/prod），`BUILDHISTORY_COMMIT="1"` 使每次构建自动提交，两次构建的 diff 用 `buildhistory-diff <rev1> <rev2> -p <dir>` 生成并归档。

### 2.2 yocto-check-layer（D-08）

- 工具齐全：`scripts/yocto-check-layer`、`scripts/yocto-check-layer-wrapper`、`scripts/lib/checklayer/cases/{common,bsp,distro}.py`。
- `yocto-check-layer` 关键参数：`layers`（被检查层）、`--dependency`（依赖层目录）、`--no-auto-dependency`、`--additional-layers`、`--machines`、`--with/--without-software-layer-signature-check`、`-n/--no-auto`、`-o/--output-log`。
- `yocto-check-layer-wrapper` 会建临时干净 build 目录并透传 `"$@"`，避免污染现有构建；需先 `source oe-init-build-env`。
- **依赖层解析实测**：本层 `LAYERDEPENDS_meta-yp-distro = "core yocto"`（`yocto` 即 meta-poky）。在已有完整 bblayers 的 build 里跑会因 `--dependency` 重复添加 meta-poky 报 `duplicated BBFILE_COLLECTIONS 'yocto'`；不用 `--dependency` 又报 `depends on yocto and isn't found`。**可行组合**：wrapper（干净 build，仅 core）+ `--dependency <meta-poky> <meta-oe>`，实测进入逐用例检查。
- **正向用例结果（真实跑出的结论）**：

  | 用例 | 结果 | 备注 |
  |---|---|---|
  | test_layerseries_compat | ok | `LAYERSERIES_COMPAT = "wrynose"` 匹配 |
  | test_parse | ok | |
  | test_patches_upstream_status | ok | |
  | test_readme | **FAIL** | `Layer doesn't contain a README file` |
  | test_security | **FAIL** | `Layer doesn't contain a SECURITY.md file` |
  | test_show_environment | ok | |
  | test_signatures | ok | |
  | test_world | 重 | 触发 `bitbake -S lockedsigs world`（全层签名锁），8G 沙箱卡住 |

- 失败点均为**可修复的文档缺失**（`meta-yp-distro/` 根目录无 README、SECURITY.md）——补这两个合规文档即可让正向全绿，不是篡改检查。
- `test_world` 是重型用例（`bitbake -S lockedsigs world`），CI 可行性需控制：用 `--without-software-layer-signature-check` 关掉软件层签名污染检查，但 `test_world` 属 common case 仍会跑；设计上以"正向层检查跑通到可读结论 + 归档"为准，world 若因资源超时则标 `RESOURCE_PARTIAL`/`UNVERIFIED`，不冒充。
- **负向构造**：`checklayer/cases/common.py::test_readme` 要求 README 存在且含 maintainer/patch/email，缺 README 即确定性 FAIL。临时坏层 = 仅含最小 `conf/layer.conf`、无 README 的目录 → check-layer 必然 FAIL，作为负向证据。

结论：D-08 技术路径成立；正向需补 README + SECURITY.md（本 Stage 实现），负向用临时无 README 层。

### 2.3 四步 CI（D-09）

- 前序已验证的四步证据：S0 QEMU 启动（`.ext4` 启动到 login，TCG）、S1 构建（`BUILD_RC=0`）、S2 eSDK/devtool（`DEVTOOL_SMOKE_OK`）、S3 deploy/gdb（`DEPLOY_OK`、`GDB_BREAKPOINT_HIT`、`SOURCE_LINE_OK`）。
- 四步编排脚本 `scripts/dev/four-step.sh` 尚未存在，需新建，串联：build → devtool modify/build → deploy-target → gdbserver。
- `.github/workflows/` 现有 `m0-gate.yml`（`feat-m0*`/`release-m0*`）、`m0.yml`（同，带 paths）。本分支 `feat-m1-dev-platform` 不匹配 → 前序 S0–S3 的 CI 均 `total_count=0`。
- plan §3.4：四步 CI 跑 GitHub-hosted `ubuntu-latest`，不用 self-hosted；容器不加 `--cpus`/`--memory`/`--cpu-quota`/`--cpu-set`；每次打印实际 `nproc`/`MemTotal`，低于 32c/128G 标 `RESOURCE_PARTIAL`；CI 只跑缓存增量（GHCR 预热缓存 + 分 job），不跑全冷构建；本地证据与 CI 证据分列，不互相替代。
- 硬约束：不为让 CI 跑而改 M0 workflow 的 paths（前序边界）；新增独立 `m1-dev.yml` 属本 Stage 交付，不是改 M0。

## 3. 设计

### 3.1 D-06 buildhistory 配置与归档

- **`kas/editions/dev.yml`** 增加（dev 专属，不污染 base/prod）：
  - `INHERIT += " buildhistory"`
  - `BUILDHISTORY_DIR = "${TOPDIR}/buildhistory"`
  - `BUILDHISTORY_COMMIT = "1"`
  - `BUILDHISTORY_FEATURES = "image package"`（去掉 sdk，避免与 eSDK 产物耦合；保留 image/package 做差异可读）
- **`scripts/ci/buildhistory-diff.sh`**：接收两次构建的 commit（或默认取最近两次），调用 oe-core 的 `buildhistory-diff -p <buildhistory-dir> <rev1> <rev2>`，输出重定向到 `docs/m1/evidence/buildhistory-diff-<date>.txt` 归档；支持 `--check` 模式断言 diff 文件非空且含可读字段（package 增减/版本变化）。
- 归档目录：`docs/m1/evidence/`（新增）。证据文件为文本 diff，不入库大二进制。
- 变量登记：`docs/m0/variable-index.md` 追加 `BUILDHISTORY_*`（dev edition 覆盖类，与 #30/#31 同列）。

### 3.2 D-08 check-layer 正/负向脚本

- **`meta-yp-distro/README`**：新增合规 README（含 maintainer、patching instructions、email）→ 满足 `test_readme`。
- **`meta-yp-distro/SECURITY.md`**：新增安全策略文件 → 满足 `test_security`。
- **`scripts/ci/check-layer.sh`**：
  - 正向：`source oe-init-build-env` + `yocto-check-layer-wrapper <meta-yp-distro> --dependency <meta-poky> <meta-oe> --without-software-layer-signature-check -o <log>`；断言退出码 0、日志含 `test_readme ... ok`、`test_security ... ok`。若 `test_world` 因资源卡住/超时 → 记 `RESOURCE_PARTIAL`，不冒充全绿。
  - 负向：用 `mktemp -d` 建临时坏层（仅 `conf/layer.conf`，`LAYERSERIES_COMPAT` 与集合名齐全但无 README），跑 check-layer 断言退出码非 0 且日志含 `test_readme ... FAIL`；清理临时层。
  - 路径可配置（`-o` 日志、层根目录），CI 与本地共用。

### 3.3 D-09 four-step.sh 与 m1-dev.yml

- **`scripts/dev/four-step.sh --target qemu [--image <ext4>] [--binary <bin>]`**：按序调用
  1. build：`kas build ... --target yp-image-dev`（本地复用已有构建目录；CI 走缓存增量）
  2. devtool modify/build：复用 S2 `devtool-smoke.sh` 的 modify 路径（对已有 recipe `m4` 做 modify→build→reset）
  3. deploy-target：复用 S3 `deploy-target.sh`（marker 生效 → `DEPLOY_OK`）
  4. gdbserver：复用 S3 `gdb-connect.sh`（断点命中 → `GDB_BREAKPOINT_HIT`）
  - 每步打印 `STEP_<n>_BEGIN/END` 日志段与耗时，任一步非 0 即整体失败并打印失败步骤；四步分别留日志段供 CI 归档。
  - devshell 为交互式（plan §3），CI 不跑，脚本内标 `DEVSHELL_UNVERIFIED`，不冒充。
- **`.github/workflows/m1-dev.yml`**：`ubuntu-latest`，三个 job：
  - `gate`：跑 `bash scripts/gate.sh` + `check-vars.sh` + `bash -n`，打印 `nproc`/`MemTotal`。
  - `build-dev`：GHCR 预热缓存（sstate/downloads 层），`kas build --target yp-image-dev`，打印 `nproc`/`MemTotal`；低于 32c/128G 标 `RESOURCE_PARTIAL`（env 输出 `RESOURCE_PROFILE`）。
  - `four-step`：跑 `scripts/dev/four-step.sh --target qemu`，分段归档四步日志，打印资源；TCG 标注。
  - 容器不加资源限制；不使用 SSTATE_MIRRORS/远程 hashserv（G3 门禁）；不写阈值数值字面值（G2 门禁）；token 只经 Actions secret/CI 官方机制，不入库。
  - 触发：`workflow_dispatch` + `push branches: [feat-m1*]`（本分支匹配，属新增 workflow，不改 M0）。
- **CI 3 次 green**：本地无法代替远端 runner；设计上明确"3/3"必须以 GitHub Actions 实际 3 次成功 run 为准。若因分支/权限/资源无法在远端跑满 3 次，如实标 `SINGLE_PASS`/`UNVERIFIED`，不写"稳定通过"。

### 3.4 D-07 bblock（P2 可选）

- 探测 bblock 类与 `BB_BLOCKED_RECIPES` 支持；若时间/资源允许且不影响 P1，补一个最小验证（锁定某 recipe 不重编）。不进入 M1 gate，做不成如实标 P2 未做。

## 4. 四问评审（见 RV-M1-S4 §1）

1. **覆盖**：D-06/D-08/D-09 逐项有脚本 + 证据落点；D-07 标 P2 可选。
2. **真实证据**：所有结论以容器内真实跑出的用例结果/commit 为准；check-layer 正向 FAIL 原因（README/SECURITY）如实记录并修复；CI 3 次 green 必须以远端 Actions 为准，不本地伪造。
3. **失败处理**：失败先开 ISS；test_world 资源卡住标 RESOURCE_PARTIAL/UNVERIFIED；不把单次通过写成稳定通过。
4. **边界**：不打 m1.0、不改 M0、不建 M2、不引入 self-hosted、不改 M0 workflow paths、无 token 入库。

## 5. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S4 设计 + 设计阶段真实探测证据（buildhistory 变量/GitPython、check-layer 依赖解析与正/负向用例、四步 CI 资源口径） | zeek.zhao |
