# yp-distro · M0（kas bootstrap）

本分支为 **M0 里程碑专用孤立分支**，与 `main` 不共享历史。`main` 仅作写法参考：kas 文件结构、Docker 分层、GitHub Actions 组织；本分支不复制其四版兼容层与全量测试套件。

## 目标

只装 Docker 的机器，拉取预置镜像后一条命令产出 prod 镜像；下载目录与缓存目录以挂载复用；缓存可打包、可切分、可恢复；无缓存服务器、无 root 构建。

## AI 与人类协作者的入口

```bash
scripts/ai-entry.sh          # 当前 Step + 必读清单 + 下一步
scripts/ai-entry.sh --next   # 可直接粘贴给 AI 的单步提示词
```

**文档先行**：每个 Step 先写设计（`docs/m0/design/`）并过四问评审（`docs/m0/reviews/`），再写代码；遇到的问题先开 `docs/m0/issues/` 单，再修；阈值与契约变更先开 `docs/m0/changes/` 单。记录规范见 [`docs/m0/iso-mapping.md`](docs/m0/iso-mapping.md)。进度以 [`docs/m0/plan.md`](docs/m0/plan.md) 为唯一事实源。

## 现状

状态与 [`docs/m0/plan.md`](docs/m0/plan.md) §1 进度表逐格一致；验收见 [`docs/m0/acceptance.md`](docs/m0/acceptance.md)（状态 `Final`，判据 1–8 全部 `通过`）。

| Step | 内容 | 状态 |
|---|---|---|
| S0 | 空分支、提示词、AI 入口 | 完成 |
| S1 | 发行版层骨架 | 完成 |
| S2 | kas 入口与层锁定 | 完成 |
| S3 | Ubuntu 容器镜像（jenkins 用户） | 完成 |
| S4 | 下载与缓存分卷挂载 | 完成 |
| S5 | 首次构建与缓存命中 | 完成 |
| S6 | 缓存打包与切分（80% 阈值） | 完成（Stage E 接线 + 契约收紧） |
| S7 | 缓存分片发布到容器仓库 | 完成 / 端到端已验 |
| S8 | PR 门禁 | 完成 |
| S9 | 验收与变量索引 | 完成 |

验收结论：判据 1–8 全部 `通过`，`docs/m0/acceptance.md` 状态 `Final`。

## 三步上手（容器内构建）

宿主机只需要 Docker：**宿主机没有 kas**，`kas build` 必须在 builder 容器内执行。

**首次使用必须先取回 S5 缓存**：没有缓存的冷构建在 4 核/8 GB 配额下耗时约 2h51m（prod edition，RV-005），命中缓存的二次构建约 200–300s（**ci edition**，RV-005；prod edition 见 RV-014，时长依配额与 edition 而异）。取缓存（release 8 分片重组、sha256 校验、**direct 单层解包**得到 `downloads/` 与 `sstate/`）与换机完整命令序列见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §3；正常顺序是 fetch → bootstrap → preflight，不使用 `--force`。S5 缓存取回入口只在 runbook，不在 README 复制会漂移的命令。

```bash
# 1. 拉镜像（匿名可拉）
docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0

# 2. 先按 runbook §3 步骤 4 取回缓存（目标为空，无需 --force），再归一属主：
#    fetch 命令不在 README 复制以免漂移（见 docs/runbook-new-machine.md §3 步骤 4）；
#    若已先 bootstrap，fetch 后必须重跑本步——root 解包会把属主变为归档 UID。
#    bootstrap 幂等，不覆盖已有下载/缓存。
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate

# 3. 容器内构建 —— 此为示意，不可直接粘贴执行（见下方说明）
# docker run --rm ... ghcr.io/zeek-zhao/yp-builder:wrynose-m0 kas build kas/yp.yml:editions/prod.yml
```

> 注意：builder 镜像只内置 `kas` 与依赖，**不含仓库的 `kas/` 配置**。上面第 3 步（注释行）是概念示意，照抄会因找不到 `kas/` 配置而失败；**可执行写法必须用命名容器把仓库挂载到 `/mnt/repo:ro` 并复制到 `/work/build-run`，完整命令见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §3 步骤 7（本轮 RV-014 已按该写法实跑通过）**。

执行规则见 [`docs/ai/m0-prompt.md`](docs/ai/m0-prompt.md)。
