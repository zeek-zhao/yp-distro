# yp-distro

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![ci](https://github.com/zeek-zhao/yp-distro/actions/workflows/ci.yml/badge.svg)](https://github.com/zeek-zhao/yp-distro/actions/workflows/ci.yml)

以 **wrynose 6.0** 为保障目标的 Yocto 发行版工程：版本锁、容器化构建、BATS 门禁、
镜像分发、SPDX / CVE 合规证据采集，外加一套**可复现、可核对**的验证管线。

仓库同时保留 dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 的配置与兼容层，作为**四版语法
差异的知识资产**（冻结、不构建、不保障）——迁移时不需考古。

> **当前保障范围只有 wrynose 6.0**（2026-11-09 决策）。3.1 / 4.0 / 5.0 的配置与配方
> 冻结保留在仓库中、退出构建与保障，待 6.0 达到完成门槛后回移。验证环境为
> QEMU + x86-64，未使用实体硬件。范围、理由与已知边界见
> [`docs/06-process/engineering-overview.md`](docs/06-process/engineering-overview.md) §2 与 §9。

> **本项目不是 Yocto Project 或 OpenEmbedded 的官方项目**，与 Linux Foundation
> 及其任何子项目无隶属或背书关系。文中出现的 release 名称（dunfell 等）仅指上游
> Yocto 版本代号。

## 当前状态（2026-11-14）

| 里程碑 | 内容 | 状态 |
|---|---|---|
| `v0.1.0` | P0 基线：容器化、4 镜像、L1 CI、BATS 零 skip | ✅ 已发布 |
| `v0.2.0` | P1 打通：kas 版本锁、四版解析、QA 报告链路 | ✅ 已发布 |
| `v0.3.0` | 6.0 发行版与镜像：U-Boot 启动链 + systemd 收口 | ✅ 已发布 |
| `v0.4.0` | 6.0 语法组：六构建系统 + 服务模板 | ✅ 已发布 |
| `v0.5.0` | 启动优化（内核裁剪 / rootfs 形态 / systemd 精简） | ✅ **随 v1.0.0 累积发布** |
| `v0.6.0` | 服务与 demo 扩展 + 服务数×耗时曲线 | ✅ **随 v1.0.0 累积发布** |
| `v0.7.0` | 5.0（scarthgap）对齐与四版补齐 | ✅ **随 v1.0.0 累积发布** |
| `v1.0.0` | 四版收口（回归 8/8 + 归档刷新 + 安全基线） | ✅ 已发布（2026-11-05，`1e1ff48`） |
| `v1.0.1` | A 修正：DISTRO_VERSION、断言动态化、CI 收缩、合规收缩、文档同步 | ✅ 已发布（2026-11-14，`bf748c1`） |
| `v1.0.2` | B 验证：证据级别列 + runtime smoke 动作集 + `design.md` | ✅ 已发布（2026-11-14，`2157a6c`） |

里程碑 `6.0 全面收口` 仍开放：余 #135 文档同步与 C 功能 `v1.1.0`（#133）。
判定表见 [`docs/06-process/plan/milestones.md`](docs/06-process/plan/milestones.md)。

> `v0.5.0` / `v0.6.0` / `v0.7.0` 三个里程碑**从未单独打 tag**——它们的全部内容挤在
> `v1.0.0` 指向的一个 squash commit 里，在同一 commit 上补三个 tag 等于伪造发布点。
> 所以口径是「累积发布」，不是「各自发过」。详见
> [`docs/06-process/engineering-overview.md`](docs/06-process/engineering-overview.md) §2。

计划与进度分三层看，别重复维护：

| 想知道 | 看哪里 |
|---|---|
| **这仓库是什么、承诺什么、不承诺什么** | [`docs/06-process/engineering-overview.md`](docs/06-process/engineering-overview.md) |
| **每条功能是什么、怎么用、边界在哪** | [`docs/01-requirements/features.md`](docs/01-requirements/features.md) |
| **工程结构为什么这样**（分层/class/注入点/扩展方式） | [`docs/02-development/design.md`](docs/02-development/design.md) |
| **从配置到镜像经过哪些环节**（功能流程图） | [`docs/02-development/functional-flow.md`](docs/02-development/functional-flow.md) |
| **怎么证明产物是对的、我自己怎么验**（测试说明） | [`docs/01-requirements/verification-flow.md`](docs/01-requirements/verification-flow.md) |
| **下一件该做什么（带优先级的待办）** | [`docs/06-process/backlog.md`](docs/06-process/backlog.md) |
| **现在到哪了 / 交接要点 / 踩坑结论** | [`docs/06-process/handover.md`](docs/06-process/handover.md) |
| **AI 协作者作业手册**（禁区/验证/决策边界） | [`docs/07-ai/ai-handover.md`](docs/07-ai/ai-handover.md) |
| **知识库与工程规范**（KB-01~32，normative） | [`docs/06-process/knowledge-base.md`](docs/06-process/knowledge-base.md) |
| **机器可读功能注册表**（含证据级别） | [`config/features.txt`](config/features.txt) |
| **什么才算做完**（每个版本的出口条件） | [`docs/06-process/plan/milestones.md`](docs/06-process/plan/milestones.md) |
| **各版本改了什么**（发布记录） | [`CHANGELOG.md`](CHANGELOG.md) |
| **有哪些活**（开放 issue 清单，脚本生成） | [`docs/issues.md`](docs/issues.md) |
| 阶段划分与约束 | [`docs/06-process/roadmap.md`](docs/06-process/roadmap.md) |
| 在线看板 | [issues](https://github.com/zeek-zhao/yp-distro/issues) · [Projects #4](https://github.com/users/zeek-zhao/projects/4) |

## 快速开始

```bash
bash scripts/dev.sh --build                  # 建开发容器 yocto-dev:local
bash scripts/dev.sh bash scripts/ci/lint.sh  # L1 四段：shellcheck/shfmt/hadolint/actionlint
bash scripts/dev.sh bats tests/bats/         # BATS 全量（零 skip 要求）
bash scripts/smoke.sh --release wrynose --variant custom --image full
                                             # runtime 取证：一次起机跑动作集，出 JUnit + 归档（#132）
./project.sh config wrynose                  # 打印某 release 的生效配置
make help                                    # 所有入口
```

真构建（需要 Docker、约 80 GB 磁盘、首次数小时）：

```bash
bash scripts/build.sh --release wrynose --variant custom            # 最小镜像
bash scripts/build.sh --release wrynose --variant custom --image full
```

### 发版 / 点版本 / 日常取证

```bash
bash scripts/release-check.sh                        # 受保障组合全量回归（清单 = config/supported-releases.txt，现仅 wrynose）：build→qemu→report→guard
bash scripts/release-check.sh --machine qemuarm64    # arm64 不在保障范围，仅手动抽查用
bash scripts/deploy-guard.sh --all                   # 构建产物新鲜度校验（指纹级）
bash scripts/boot-time.sh --release wrynose --variant custom --image minimal --runs 3
                                                     # 启动三段测量；文档见 docs/02-development/boot-optimization.md
```

点版本（x.y.z）跟进流程、安全基线（dm-verity）与启动优化结论：
[`docs/05-release/point-releases.md`](docs/05-release/point-releases.md)、
[`docs/qa/security/dm-verity-feasibility.md`](docs/qa/security/dm-verity-feasibility.md)、
[`docs/02-development/boot-optimization.md`](docs/02-development/boot-optimization.md)。

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
docs/08-tasks/     任务卡（历史卡已归档，见 docs/INDEX.md）
docs/              分支模型、CI、路线图、合规口径、qa 报告
```

## 开发方式

- **分支**：`main` 是唯一长期分支（可发布、可复现），改动一律走
  `feat/<ID>-<slug>` 短分支 + PR，合并即删；见 [`docs/06-process/branching.md`](docs/06-process/branching.md)
- **一次改动**：一个 issue → 一张任务卡 `docs/08-tasks/<ID>.md` → 一个任务分支 → 一个 PR
- **提交**：Conventional Commits，见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

## 约束（实践中踩出来的）

- 构建节点常为**共享** Jenkins 节点：不改全局 `~/.ssh/config`，用仓库级
  `core.sshCommand`；构建串行，低磁盘水位时阻断。
- `DL_DIR` / `SSTATE_DIR` 必须落在大容量卷上，不能落在系统盘。
- 构建镜像内不得含任何凭据 —— GHCR 上的镜像默认对外可见。
- 四个 release 的 `file://` 源码布局、SPDX 形态、CVE 采集通路各不相同，
  差异记录在 [`docs/05-release/compliance.md`](docs/05-release/compliance.md) 与
  [`docs/02-development/syntax-matrix.md`](docs/02-development/syntax-matrix.md)。

## 许可与声明

本仓库源码以 **MIT** 许可发布，全文见 [`LICENSE`](LICENSE)。

但构建产物与容器镜像包含大量第三方组件（GPL / LGPL / BSD / Apache-2.0 等），
**不适用** MIT。分发前的义务与源码获取方式见
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

Yocto 构建产物内的许可证清单由合规采集产出，归档在
`docs/qa/<release>/compliance-<date>-<sha>[-<variant>].md`。

## 贡献

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。提交需带 DCO `Signed-off-by`。
