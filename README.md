# Yocto 多版本工程

4 个 Yocto release（dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 / wrynose 6.0）× 2 个 variant
（`general` / `custom` 独立 distro）的工程化流水线：版本锁、容器化构建、BATS 门禁、镜像分发。

> 需求真本在 Obsidian：`40-项目/YP/Yocto-多版本工程需求.md`（v1.1）。本仓库是它的落地实现。

## 当前状态（2026-10-28）

| 阶段 | 里程碑 | 状态 |
|---|---|---|
| **P0 基线** | [v0.1.0](https://github.com/zeek-zhao/yocto/milestone/1) | 进行中：4 镜像已推 GHCR 且**公开可拉**、L1 CI 三 job 全绿、BATS 30 用例零 skip；剩余 4 张卡（见下） |
| P1 打通 | [v0.2.0](https://github.com/zeek-zhao/yocto/milestone/2) | 未开始（依赖 kas 层） |
| P2 交付能力 | [v1.0.0](https://github.com/zeek-zhao/yocto/milestone/3) | 未开始 |

**P0 出口条件**：GHCR 4 镜像免登录可拉 ✅、L1 全绿 ✅、`project.sh test` 轻量用例可跑 ✅。

## 计划与问题在哪看

- **看板（Kanban）**：https://github.com/users/zeek-zhao/projects/4
- **里程碑**：`v0.1.0` = P0 基线、`v0.2.0` = P1 打通、`v1.0.0` = P2 交付能力
- **工程计划总览**：[`docs/roadmap.md`](docs/roadmap.md)（阶段 / 依赖 / 开放 Issue 索引）
- **开放问题**：带 `question` 标签的 Issue；实测缺陷带 `bug` 标签

## 快速开始

```bash
bash scripts/dev.sh --build                  # 建开发容器 yocto-dev:local
bash scripts/dev.sh bash scripts/ci/lint.sh  # L1 四段：shellcheck/shfmt/hadolint/actionlint
bash scripts/dev.sh bats tests/bats/         # BATS 全量（零 skip 要求）
./project.sh config wrynose                  # 打印某 release 的生效配置
make help                                    # 所有入口
```

## 镜像

```bash
docker pull ghcr.io/zeek-zhao/yocto/wrynose:latest      # 免登录
docker run --rm ghcr.io/zeek-zhao/yocto/dunfell:latest id -un
```

tag 语义：`sha-<7位>` = 某次提交、`3.1|4.0|5.0|6.0` = release 系列、`latest` = main 最新。

## 目录

```
config/          release / variant / machine 配置与版本锁
docker/          4 份构建镜像 + 开发镜像 + 共享依赖安装脚本
scripts/         入口脚本（dev / image / report / wf3 / ci / container）
meta-zeek/       Yocto layer（distro conf + image + recipes）
tests/bats/      BATS 用例（含 CI workflow 静态门禁）
tasks/           WF3 任务卡（一卡一分支一 PR）
docs/            分支模型、CI 说明、路线图、qa 报告
reference/legacy/ 从本地参考工程继承的历史脚本（不进 lint 范围）
```

## 开发方式

- **分支**：`main`（稳定）← PR ← `dev`（集成，默认分支）← PR ← `feat/<TASK-ID>-<slug>`；见 [`docs/branching.md`](docs/branching.md)
- **写代码**：不在本地写构建代码。任务卡 `tasks/<ID>.md` 派给 215 容器内的 Copilot CLI（`scripts/wf3.sh`），WorkBuddy 只负责派单 / 验收 / 提交。
- **一次改动**：一个 Issue → 一张任务卡 → 一个任务分支 → 一个 PR（`Closes #n`）。

## 约束（踩过的坑）

- 215 是共享 Jenkins 节点：**不改全局** `~/.ssh/config`，用仓库级 `core.sshCommand`；构建串行，磁盘 85% 水位阻断。
- `DL_DIR` / `SSTATE_DIR` 必须落 `/home`（1.2T 可用），不能落 `/`（349G）。
- 镜像内不得含任何凭据；GHCR public 意味着内容对外可见。
