# yp-distro

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![ci](https://github.com/zeek-zhao/yp-distro/actions/workflows/ci.yml/badge.svg)](https://github.com/zeek-zhao/yp-distro/actions/workflows/ci.yml)

4 个 Yocto release（dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 / wrynose 6.0）× 2 个 variant
（`general` / `custom` 独立 distro）的工程化流水线：版本锁、容器化构建、BATS 门禁、
镜像分发、SBOM / CVE / FOSS 合规证据采集。

> **本项目不是 Yocto Project 或 OpenEmbedded 的官方项目**，与 Linux Foundation
> 及其任何子项目无隶属或背书关系。文中出现的 release 名称（dunfell 等）仅指上游
> Yocto 版本代号。

## 当前状态（2026-11-01）

| 里程碑 | 内容 | 状态 |
|---|---|---|
| `v0.1.0` | P0 基线：容器化、4 镜像、L1 CI、BATS 零 skip | ✅ 已发布 |
| `v0.2.0` | P1 打通：kas 版本锁、四版解析、QA 报告链路 | ✅ 已发布 |
| `v0.3.0` | 6.0 发行版与镜像：U-Boot 启动链 + systemd 收口 | ✅ 已发布 |
| `v0.4.0` | 6.0 语法组：六构建系统 + 服务模板 | ✅ 已发布 |
| `v0.5.0` | 6.0 启动优化（内核裁剪 / rootfs 形态 / systemd 精简） | 🚧 进行中 |
| `v0.6.0` | 6.0 服务与 demo 扩展 | 🚧 进行中 |
| `v0.7.0` | 5.0（scarthgap）对齐与四版补齐 | 🚧 进行中 |
| `v1.0.0` | 四版收口 | 🚧 进行中 |

路线与依赖关系见 [`docs/roadmap.md`](docs/roadmap.md)。
开放问题见 [issues](https://github.com/zeek-zhao/yp-distro/issues)，
阶段看板见 [Projects #4](https://github.com/users/zeek-zhao/projects/4)。

## 快速开始

```bash
bash scripts/dev.sh --build                  # 建开发容器 yocto-dev:local
bash scripts/dev.sh bash scripts/ci/lint.sh  # L1 四段：shellcheck/shfmt/hadolint/actionlint
bash scripts/dev.sh bats tests/bats/         # BATS 全量（零 skip 要求）
./project.sh config wrynose                  # 打印某 release 的生效配置
make help                                    # 所有入口
```

真构建（需要 Docker、约 80 GB 磁盘、首次数小时）：

```bash
bash scripts/build.sh --release wrynose --variant custom            # 最小镜像
bash scripts/build.sh --release wrynose --variant custom --image full
```

## 镜像

```bash
docker pull ghcr.io/zeek-zhao/yp-distro/wrynose:latest      # 免登录
docker run --rm ghcr.io/zeek-zhao/yp-distro/dunfell:latest id -un
```

tag 语义：`sha-<7位>` = 某次提交（不可变，合规基准用这个）、
`3.1|4.0|5.0|6.0` = release 系列、`latest` = `main` 最新。

这些镜像只提供**构建环境**，不是 Yocto 产物；产物由本地构建得到。

## 目录

```
config/            release / variant / machine 配置与版本锁
docker/            4 份构建镜像 + 开发镜像 + 共享依赖安装脚本
scripts/           入口脚本（dev / build / image / report / compliance / ci）
scripts/container.sh  构建容器入口（命名/UID/磁盘落点）
layers/meta-yp/    Yocto layer（distro conf + image + recipes）
tests/bats/        BATS 用例（含 CI workflow 静态门禁）
tasks/             任务卡（一卡一分支一 PR）
docs/              分支模型、CI、路线图、合规口径、qa 报告
```

## 开发方式

- **分支**：`main`（稳定，发布线）← PR ← `dev`（集成）← PR ← `feat/<slug>`；
  见 [`docs/branching.md`](docs/branching.md)
- **一次改动**：一个 issue → 一张任务卡 `tasks/<ID>.md` → 一个任务分支 → 一个 PR
- **提交**：Conventional Commits，见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

## 约束（实践中踩出来的）

- 构建节点常为**共享** Jenkins 节点：不改全局 `~/.ssh/config`，用仓库级
  `core.sshCommand`；构建串行，低磁盘水位时阻断。
- `DL_DIR` / `SSTATE_DIR` 必须落在大容量卷上，不能落在系统盘。
- 构建镜像内不得含任何凭据 —— GHCR 上的镜像默认对外可见。
- 四个 release 的 `file://` 源码布局、SPDX 形态、CVE 采集通路各不相同，
  差异记录在 [`docs/compliance.md`](docs/compliance.md) 与
  [`docs/syntax-matrix.md`](docs/syntax-matrix.md)。

## 许可与声明

本仓库源码以 **MIT** 许可发布，全文见 [`LICENSE`](LICENSE)。

但构建产物与容器镜像包含大量第三方组件（GPL / LGPL / BSD / Apache-2.0 等），
**不适用** MIT。分发前的义务与源码获取方式见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

Yocto 构建产物内的许可证清单由合规采集产出，归档在
`docs/qa/<release>/compliance-<date>-<sha>[-<variant>].md`。

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。提交需带 DCO `Signed-off-by`。
