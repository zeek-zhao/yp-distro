# yp-distro · M0（kas bootstrap）

本分支为 **M0 里程碑专用孤立分支**，与 `main` 不共享历史。`main` 仅作写法参考：kas 文件结构、Docker 分层、GitHub Actions 组织；本分支不复制其四版兼容层与全量测试套件。

## 目标

宿主机具备 Docker 与 git / bash / python3 / curl / tar / sha256sum（不需 kas / bitbake），拉取预置镜像后一条命令产出 prod 镜像；下载目录与缓存目录以挂载复用；缓存可打包、可切分、可恢复；无缓存服务器、无 root 构建。宿主工具清单与缺失处理见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §1。

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

验收结论：判据 1–8 全部 `通过`，`docs/m0/acceptance.md` 状态 `Final`。M0 遗留的「真实全量 / `--mode ghcr` / GHCR 源 tar 布局 / K-8」已由 M0.1 证据闭环补齐（基线 `m0.0`），见 [`docs/m0.1/`](docs/m0.1/)（`RV-018` / `CHG-020` / `ISS-036`）。

## 三步上手（容器内构建）

宿主机需要 **Docker + git / bash / python3 / curl / tar / sha256sum**；**不需要 kas / bitbake**，`kas build` 必须在 builder 容器内执行。这些工具是 `git clone`、fetch 缓存、环境预检的前置；Ubuntu 24.04 默认具备大部分，缺失见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §1「宿主工具」。路径 A 另需 `sudo`（root 用户可去掉 `sudo` 直接执行）；路径 B 不需要 `sudo`；若当前 UID=1000 但非 root 且无 `sudo`，走路径 B。

构建容器必须使用宿主**全部 CPU/内存**：`docker run` / `docker build` 不得加 `--cpus`、`--memory` 等限制；标准执行机为 **32 核 / 128 GiB 内存档**。低于此基线仍用实际全部资源，但须在记录中标 `RESOURCE_PARTIAL`，不得写成 full-quota PASS。硬性细则见 [`AGENTS.md`](AGENTS.md) §2.1。

**首次使用必须先取回 S5 缓存**：没有缓存的冷构建在 4 核/8 GB 配额下耗时约 2h51m（prod edition，RV-005），命中缓存的二次构建约 200–300s（**ci edition**，RV-005；prod edition 见 RV-014，时长依配额与 edition 而异）。取缓存（release 8 分片重组、sha256 校验、**direct 单层解包**得到 `downloads/` 与 `sstate/`）与换机完整命令序列见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §3；正常顺序是 fetch → bootstrap → preflight，不使用 `--force`。S5 缓存取回入口只在 runbook，不在 README 复制会漂移的命令。

**第 2 步先取缓存、再归一属主**：先按 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §3 步骤 4 取回缓存（目标为空，无需 `--force`；fetch 命令不在 README 复制以免漂移），然后按下面**二选一**执行第 2 步（不要顺序执行两条）。若你已先执行 bootstrap，fetch 后必须重跑第 2 步——root 解包会把属主变为归档 UID。

**第 1 步 · 拉镜像（路径 B 可跳过本行，改用 runbook §5.2 的 `yp-builder:local`；不要把 GHCR 1000 镜像用于路径 B 构建）**

```bash
docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0
```

**第 2 步 · 归一属主（二选一）**

路径 A（当前 UID=1000 或 root，卷保持镜像 1000；需 `sudo`，root 可去掉 `sudo` 直接执行，非 root 且无 `sudo` 请走路径 B）：

```bash
sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid 1000 --gid 1000
```

路径 B（当前 UID≠1000，卷保持当前 UID；先按 runbook §5.2 构建 `yp-builder:local`）：

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
```

**第 3 步 · 容器内构建 —— 此为示意，不可直接粘贴执行（见下方说明）**

```bash
# docker run --rm ... ghcr.io/zeek-zhao/yp-builder:wrynose-m0 kas build kas/yp.yml:editions/prod.yml
```

> 注意：builder 镜像只内置 `kas` 与依赖，**不含仓库的 `kas/` 配置**。上面第 3 步（注释行）是概念示意，照抄会因找不到 `kas/` 配置而失败；**可执行写法必须用命名容器把仓库挂载到 `/mnt/repo:ro` 并复制到 `/work/build-run`，完整命令见 [`docs/runbook-new-machine.md`](docs/runbook-new-machine.md) §3 步骤 7（本轮 RV-014 已按该写法实跑通过）**。

执行规则见 [`docs/ai/m0-prompt.md`](docs/ai/m0-prompt.md)。
