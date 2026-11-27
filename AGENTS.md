# AGENTS.md · AI 开发入口（唯一入口）

> 任何 AI 编码代理进入本仓库，**先读本文件**，再按「必读顺序」继续。不读本文件直接改代码视为违规。
> 人类协作规范见 `CONTRIBUTING.md`（合并后从 main 补齐）；本分支当前以文档先行推进 M0。

## 1. 三分钟上手

```bash
scripts/ai-entry.sh          # 打印当前里程碑、当前 Step、下一步命令、必读清单
scripts/ai-entry.sh --next   # 打印可直接粘贴给 AI 的单步提示词
```

## 2. 必读顺序（不可跳读）

| 顺序 | 文件 | 读它解决什么 |
|---|---|---|
| 1 | `AGENTS.md`（本文件） | 边界、入口、记录要求 |
| 2 | `README.md` | 项目目标与三步上手 |
| 3 | `docs/ai/m0-prompt.md` | M0 约束、Step 表、验收命令 |
| 4 | `docs/m0/plan.md` | 当前进度与下一步（唯一事实源） |
| 5 | `docs/m0/iso-mapping.md` | 记录怎么写、放哪里、对应哪条规范 |
| 6 | 当前 Step 对应的 `docs/m0/design/*.md` | 本步的设计与接口 |
| 7 | `docs/ai/m0-resume-prompt.md` | 续做提示词（按 RV-010 审计排的 A→F 阶段），接手时必读 |

## 2.1 执行机与 Docker 资源基线（强制）

- 标准执行机：Ubuntu 24.04、**32 个 CPU 核**、**128 GiB 内存档**（裸机标称 128 GB，系统可见约 123.3 GiB）、≥300 GB 空闲磁盘。
- 所有 `docker build` / `docker run` / 构建容器**不得设置** `--cpus`、`--memory`、`--cpu-quota`、`--cpuset-cpus`，也不得在 compose / kas 配置中限制；容器默认继承 Docker daemon 可见的全部 CPU 与内存。
- 每次启动构建容器前必须记录四项：`nproc`、`/proc/meminfo` 的 `MemTotal`、`docker info --format 'NCPU={{.NCPU}} MemTotal={{.MemTotal}}'`、`docker inspect <容器> --format 'NanoCpus={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}} CpuQuota={{.HostConfig.CpuQuota}}'`。四项必须显示宿主全部资源，且 `NanoCpus=0`、`Memory=0`、`CpuQuota=0`；不满足则停止，不得继续构建，也不得把结果写成 full-quota PASS。
- Docker 无限制不等于 bitbake 用满：构建并发（`BB_NUMBER_THREADS` / `PARALLEL_MAKE`）必须按实际 CPU/内存配置；32c/128G 不得沿用 8 GB 配额的 `4` / `-j 2` 固定值。并发取值须由设计/变更单明确，并在 RV 记录实际核数、内存与并发。
- `scripts/build/threads.sh` 仅输出 Docker daemon 级诊断，不是 bitbake 并发控制通道；不得在 runbook 中用 `eval` / `export` 注入环境变量。实际并发由 `kas/base.yml` 的 `yp_build_threads(d)` 按容器 cgroup 内存（cgroup v2/v1，回退 `/proc/meminfo`）与可见 CPU 计算，使用容器内 `bitbake-getvar` 验收（M0.1.2 / CHG-022 / ISS-039）。
- 宿主 shell 自身被 cgroup 限到 4 核/8 GB，不代表 Docker daemon 受限；不要用宿主 shell 的 `nproc` / 内存上限判断容器能力。若 Docker daemon 实际只有 4 核/8 GB，按 `RESOURCE_PARTIAL` 记录，只声明该配额下的结果。
- 适用范围：本地/独立执行机上的 bitbake 构建与缓存操作容器。GitHub 托管 runner 不是该基线，CI 结果不得冒充 32c/128G 全配额构建证据。
- 机器不足 32 核 / 128 GiB 时，仍使用实际全部资源，但在 RV 与报告中写 `RESOURCE_PARTIAL`、实际核数与内存；不得伪称 32c/128G。标准 32c/128G 结论只能在该基线上产生。

## 3. 十一条硬约束（摘要，全文见 m0-prompt）

1. 只在本分支工作；本分支为孤立分支，不向 `main` 开 PR（方案 A，见 YP-M0-ADR-002）
2. 提交身份 `zeek-zhao`，禁止 AI 署名 trailer
3. 未实际执行不得声称成功，未验证写 `UNVERIFIED`
4. 主分支只作写法参考，禁止复制多版本兼容层
5. 不做 BSP / 业务 / OTA 服务
6. 禁止缓存服务器（远程 sstate、远程 hashserv）
7. 容器内禁止 root，固定 `jenkins` 用户
8. 切分阈值只在 `scripts/cache/threshold.conf` 定义
9. 一次一步，提交后停止等评审
10. 不新增 PRD 之外的需求，偏离记 `docs/m0/deviations.md`
11. 构建/运行容器必须使用宿主全部 CPU/内存：不得加 `--cpus` / `--memory` 等限制；标准机 32 核/128 GiB，低于基线用实际全量并标 `RESOURCE_PARTIAL`

## 4. 文档先行（Doc-First Gate）

**顺序是硬性的：文档 → 评审 → 实现 → 验证 → 记录。**

一个 Step 开工前，必须先有该 Step 的设计文档，且包含：目的、输入、接口与变量、失败模式、验收命令、回滚方式。没有设计文档的代码提交一律打回。

| 阶段 | 产物 | 编号 |
|---|---|---|
| 阶段计划 | `docs/m0/plan.md` | YP-M0-PLAN-001 |
| 设计 | `docs/m0/design/S<N>-*.md` | YP-M0-DES-0NN |
| 决策 | `docs/m0/adr/ADR-0NN.md` | YP-M0-ADR-0NN |
| 评审 | `docs/m0/reviews/RV-0NN.md` | YP-M0-RV-0NN |
| 问题 | `docs/m0/issues/ISS-0NN.md` | YP-M0-ISS-0NN |
| 变更 | `docs/m0/changes/CHG-0NN.md` | YP-M0-CHG-0NN |
| 验收 | `docs/m0/acceptance.md` | YP-M0-REC-001 |

模板在 `docs/m0/templates/`，复制后填写，不要自由发挥格式。

## 5. 问题与解决必须留痕

任何非预期现象（构建失败、脚本报错、镜像拉取失败、权限错误、性能异常）都必须开一张 `ISS-` 单，**先记录再修**。修复提交必须在信息里带 `Refs: YP-M0-ISS-0NN`。修完要有验证证据，不允许「改完看起来好了」就关单。字段与状态机见 `docs/m0/templates/issue.md`。

## 6. 提交与记录

```text
<type>(m0): <一句话动作>            # type: feat|chore|docs|ci|test|fix
Refs: YP-M0-DES-0NN                 # 关联设计
Refs: YP-M0-ISS-0NN                 # 如修复问题，必带
Doc: docs/m0/design/S<N>-xxx.md     # 本提交的文档出处
```

## 7. 分工：谁写代码，谁审记录

- 代码由外部 AI 执行方写；本仓库的记录质量与结论一致性由文档维护方核对，口径见 `docs/m0/handoff.md`。
- 每个 Step 交付必须包含：设计、四问评审、代码、命令真实输出、问题单（如有）、变更单（如有）。
- 结论缺证据 = 打回；记录缺失 = 打回，不代补。

## 8. 完成后必须回报的六件事

改动的文件清单、执行的命令清单、已验证项、未验证项及原因、新增的记录编号、下一步建议。
