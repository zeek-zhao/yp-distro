# project.sh 命令行

`project.sh` 是项目命令的唯一入口。`Makefile` 只将目标转发给它；`scripts/dev.sh`
用于进入开发容器执行验收和开发命令，不替代项目 CLI。

## CLI 契约

| 子命令 | 行为 | 选项 |
|---|---|---|
| `config` | 打印解析后的最终配置（`DISTRO`/`IMAGE`/`MACHINE`/`RELEASE`/`REPO_MODE`/`TAG`/`VARIANT`，`LC_ALL=C sort`） | `--release`（必填）、`--variant`（必填）、`--machine`（必填） |
| `doctor` | 打印 8 个 release×variant 组合 + 磁盘水位检查，返回值沿用现状（水位超限非 0） | 无 |
| `test` | 跑 BATS：`bats -r tests/bats`，**不写报告**（报告归 `report`） | `--tags <tag>` → 追加 `--filter-tags <tag>` |
| `report` | 转发 `scripts/report.sh <release> --variant <v>`（三层报告，需求 §6） | `--release`（默认 `all`）、`--variant`（默认 `general`） |
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

## 典型流程

先查看某 release、variant 和 machine 的最终配置：

```bash
./project.sh config --release scarthgap --variant general --machine qemux86-64
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
    ├── report     ──> scripts/report.sh
    ├── lint       ──> scripts/ci/lint.sh
    ├── secret-scan──> scripts/ci/secret-scan.sh
    ├── ci-tools   ──> scripts/ci/install-tools.sh
    ├── image      ──> scripts/image.sh
    ├── shell      ──> scripts/container.sh
    └── source / build / qemu / review / e2e       （未实现占位）
```
