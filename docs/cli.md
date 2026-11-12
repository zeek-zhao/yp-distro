# project.sh 命令行

`project.sh` 是项目命令的唯一入口。`Makefile` 只将目标转发给它；`scripts/dev.sh`
用于进入开发容器执行验收和开发命令，不替代项目 CLI。

> **范围（#135，2026-11-12）**：现行保障范围只有 wrynose 6.0
> （`config/supported-releases.txt`）；下文示例中的 `--release scarthgap` 仅
> 演示参数写法，换成 `wrynose` 即可。

## CLI 契约

| 子命令 | 行为 | 选项 |
|---|---|---|
| `config` | 打印解析后的最终配置（`DISTRO`/`IMAGE`/`MACHINE`/`RELEASE`/`REPO_MODE`/`TAG`/`VARIANT`，`LC_ALL=C sort`） | `--release`（必填）、`--variant`（必填）、`--machine`（必填） |
| `doctor` | 打印 8 个 release×variant 组合 + 磁盘水位检查，返回值沿用现状（水位超限非 0） | 无 |
| `kas` | 在开发容器内静态校验 kas 配置，不检出上游仓库 | `--release` 与 `--variant`（同时指定时只校验一个组合；省略时校验全部） |
| `test` | 跑 BATS：`bats -r tests/bats`，**不写报告**（报告归 `report`） | `--tags <tag>` → 追加 `--filter-tags <tag>` |
| `report` | 转发 `scripts/report.sh <release> --variant <v> [--machine <m>]`（三层报告，需求 §6） | `--release`（默认 `all`）、`--variant`（默认 `general`）、`--machine`（默认 `qemux86-64`） |
| `lint` | 转发 `bash scripts/ci/lint.sh`，参数直通 | 直通 |
| `secret-scan` | 转发 `bash scripts/ci/secret-scan.sh`，参数直通 | 直通 |
| `ci-tools` | 转发 `bash scripts/ci/install-tools.sh`，参数直通 | 直通 |
| `hooks` | 内置：`git config core.hooksPath .githooks` + `chmod +x .githooks/*` + 打印 `core.hooksPath = <值>` | 无 |
| `image` | 转发 `scripts/image.sh`，参数直通 | 直通 |
| `shell` | 转发 `scripts/container.sh`；未给 `--` 之后的命令时默认容器内跑 `bash -l` | `--release`（必填）、`--variant`（默认 `general`）、`--machine`（默认 `qemux86-64`）、`--dry-run`、`--check`、`-- <cmd>...` |

未实现子命令保留占位，输出到 stderr 并以状态码 2 退出：

| 子命令 | 阻塞原因 |
|---|---|
| `source` | C40 已改由 kas checkout 取代 |
| `build` | P1 #17 kas 落地后接管 |
| `qemu` | P2 阶段 |
| `review` | P2 阶段 |
| `e2e` | P2 阶段 |

L3（真构建 + 起机）不进 `project.sh` 的占位表，是几个独立入口：
`scripts/build.sh --release <r> --variant <v> [--machine <m>] [--cve] [--spdx]`（串行构建）、
`scripts/qemu.sh --release <r> --variant <v> [--machine <m>]`（headless 起机 + 抓串口）、
`scripts/sdk.sh --release <r> --variant <v>`（SDK/eSDK 构建 + 安装验证）、
`scripts/cve-db.sh sync|fetch|build|status`（离线 CVE 库，见 `docs/cve.md`）、
`scripts/scancode.sh sync|status|path`（按需准备 ScanCode CLI，见 `docs/scancode.md`）、
`scripts/compliance.sh --release <r> [--variant <v>] [--only sbom|cve|foss]`
（SBOM / CVE / FOSS 三件证据采集，见 `docs/compliance.md`）。
镜像名按 `config/variants/<variant>.env` 的 `IMAGE` 取，不写死在脚本里。

`--cve` 只对 `--variant custom` 有效：它把 `kas/features/cve.yml`
（一行 `YP_CVE_ENABLE = "1"`）追加到 target 之后，默认 8 组合不受影响。
前置条件是 `scripts/cve-db.sh sync` 已把离线库放进
`work/downloads/CVE_CHECK/`，缺库时 `build.sh` 在预检阶段就拒绝启动。
`--cve` 隐含 `--spdx`（6.0 的 CVE 结论来自 SBOM）。

`--spdx` 两个 variant 都能用：追加 `kas/features/spdx.yml`
（一项 `INHERIT += "create-spdx"`），产出 SBOM 供合规报告使用（issue #26）。
默认不打开 —— `do_create_spdx` 会为每个 recipe 各挂一次。
SDK 归档用 `scripts/report.sh --release <r> --variant <v> --sdk`，见 `docs/sdk.md`。
合规归档用 `scripts/report.sh --release <r> --variant <v> --compliance`，
输入是 `scripts/compliance.sh` 写的 `work/artifacts/<release>/<variant>/compliance.json`，
输出独立文件 `docs/qa/<release>/compliance-<date>-<sha>[-<variant>].md`（不并入主报告）。

### machine 维度

machine 是第三维（`release × variant × machine`），只影响「编给哪种机器」：

| 位置 | 作用 |
|---|---|
| `config/machines/<m>.env` | 给脚本：`MACHINE`、`QEMU_SSH_PORT` |
| `kas/machines/<m>.yml` | 给 bitbake：顶层 `machine:` 字段 + `QB_MEM` |
| `kas/targets/<rel>-<var>.yml` | 只 include **默认** machine，非默认机器靠叠加 |

非默认 machine 不复制 target 文件，而是用 kas 的多配置叠加：

```bash
scripts/build.sh --release scarthgap --variant general --machine qemuarm64
# → kas build targets/scarthgap-general.yml:kas/machines/qemuarm64.yml
#   工作区 work/kas-scarthgap-general-qemuarm64，产物与归档名带 -qemuarm64
```

**默认 machine（`qemux86-64`）不加任何后缀**，既有 8 组合的工作区路径、
产物目录、报告文件名全部不变；只有非默认 machine 才追加 `-<machine>`。
这样加机器维度不会让历史归档的路径失效。

aarch64 起机走容器内 `qemu-system-native`（bitbake 自己编的
`qemu-system-aarch64`，`QEMU_TARGETS` 默认就含 `aarch64`），
**不需要在宿主装 `qemu-system-arm`**，宿主环境保持零改动。

## 典型流程

先查看某 release、variant 和 machine 的最终配置：

```bash
./project.sh config --release scarthgap --variant general --machine qemux86-64
```

arm64 的构建 + 起机（宿主无需任何 aarch64 模拟器）：

```bash
scripts/build.sh --release scarthgap --variant general --machine qemuarm64
scripts/qemu.sh --release scarthgap --variant general --machine qemuarm64 --timeout 900
scripts/report.sh --release scarthgap --variant general --machine qemuarm64
```

检查将要执行的 Docker 命令，不启动容器：

```bash
./project.sh shell --release scarthgap --variant general --dry-run
```

进入构建容器；不提供 `--` 命令时会运行登录 Bash：

```bash
./project.sh shell --release scarthgap
```

## 调用关系

```text
Makefile targets
└── ./project.sh
    ├── config / doctor / test / hooks             （project.sh 内置）
    ├── kas         ──> scripts/kas-verify.py（开发容器内）
    ├── report     ──> scripts/report.sh
    ├── lint       ──> scripts/ci/lint.sh
    ├── secret-scan──> scripts/ci/secret-scan.sh
    ├── ci-tools   ──> scripts/ci/install-tools.sh
    ├── image      ──> scripts/image.sh
    ├── shell      ──> scripts/container.sh
    └── source / build / qemu / review / e2e       （未实现占位）
```

构建环境相关的并行度上限、磁盘闸、buildhistory 与源码镜像包，见
[build-env.md](build-env.md)。
