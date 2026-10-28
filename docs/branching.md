# 分支模型（C41）

> 定稿 2026-10-28。三条长期分支 + 短生命周期任务分支，`dev` 为默认分支。

## 1. 分支一览

| 分支 | 角色 | 谁能推 | 生命周期 |
|---|---|---|---|
| `main` | **稳定线**：可发布、可复现。GHCR 镜像与 git tag 只从这里产生 | 只接受来自 `dev` 的 PR（或 `hotfix/*`） | 永久 |
| `dev` | **集成线**（默认分支）：日常合入，CI 必须绿 | 任务分支经 PR 合入；紧急小修可直接提交 | 永久 |
| `feat/<TASK-ID>-<slug>` | 单张任务卡的实现分支，如 `feat/P0-05-meta-zeek` | WF3 派单的 AI / 人工 | 合并即删 |
| `fix/<slug>`、`docs/<slug>` | 缺陷与文档小修 | 直接 PR 到 `dev` | 合并即删 |
| `hotfix/<slug>` | 线上/稳定线紧急修复 | PR 到 `main`，同时回灌 `dev` | 合并即删 |

`origin/master` 是历史遗留分支（`105c582 feat: init`），只作考古，不再提交。

## 2. 一次改动的完整路径

```
feat/P0-05-meta-zeek ──PR──> dev ──PR（阶段收口时）──> main ──tag──> v0.1.0
```

1. 派单前从 `dev` 切任务分支：`git switch -c feat/<TASK-ID>-<slug> dev`
2. AI/人工在任务分支上提交（Conventional Commits：`feat|fix|docs|test|chore|refactor(scope): 摘要`）
3. 验收通过 → PR 到 `dev`，描述里贴验收命令与结果（`tasks/<ID>.md` 的验收节）
4. 每个阶段（P0/P1/P2）收口时 `dev` → `main` 一个 PR，合并后打 `vX.Y.Z` tag
5. tag 触发/配合 `images.yml` 产出 GHCR 镜像

## 3. CI 触发矩阵（改分支必须同步改这里）

| workflow | push | PR | 定时 | 手动 | 说明 |
|---|---|---|---|---|---|
| `ci.yml` | `main`、`dev` | 全部 | — | ✅ | L1：shellcheck / shfmt / hadolint / actionlint + BATS + 密文扫描 |
| `images.yml` | 仅 `main` | — | — | ✅ | L2：4 镜像矩阵 → push GHCR |
| `pull-check.yml` | — | — | 每周一 06:00 | ✅ | 匿名拉取 + 非 root/工具链/UTF-8 断言 |

**为什么 `dev` 不跑 `images.yml`**：镜像 tag 含 `latest` 与 `<series>`（`3.1`/`4.0`/`5.0`/`6.0`），
这些 tag 的语义属于稳定线。若 `dev` 也推，任何人 `docker pull ...:latest` 拿到的可能是半成品，
破坏「免登录可拉 = 可信基线」这条 P0 出口条件。`dev` 上的 Dockerfile 改动由 `ci.yml`
的 hadolint 静态把关，真构建留到合并 `main` 时。

## 4. 门禁与约定

- **PR 必须 CI 绿**才能合 `main`；`dev` 允许红着迭代但不得带红进 PR。
- **GitHub 侧强制保护不可用（实测）**：本仓库是私有仓库 + GitHub Free 计划，
  `POST /repos/.../rulesets` 与经典分支保护均返回
  `403 Upgrade to GitHub Pro or make this repository public to enable this feature`。
  因此「不许直推 main」靠两层落地：
  1. **本地钩子**：`make hooks`（`git config core.hooksPath .githooks`）→ `.githooks/pre-push`
     拦截推 `refs/heads/main`，紧急放行用 `ALLOW_MAIN_PUSH=1`；
  2. **CI 校验**：`ci.yml` 在 `main` 的 push 上校验 HEAD 是否来自 PR 合并（见 job `branch-guard`）。
  仓库升 Pro 或转 public 后，应改用 ruleset 并在本节记录替换。
- **PR 描述模板**：改动点 / 验收命令与输出 / 关联 Issue（`Closes #12`）/ 风险与回滚。
- **不改写已推送历史**：禁止 `push --force` 到 `main`/`dev`；回滚用 `git revert` 在 `dev` 上做。
- **提交信息**：多行一律脚本文件 + `git commit -F -`（内联双引号会把 `\n` 变字面量，已踩过）。
- **任务卡与本分支一致**：`tasks/<ID>.md` 元信息里的「分支」字段必须与实际任务分支同名。

## 5. 与 WF3 的关系

WF3（`scripts/wf3.sh`）在 215 的仓库工作树里直接跑 Copilot CLI，因此**切分支是派单前置动作**：
派单脚本先 `git switch -c feat/<TASK-ID>-<slug> dev`，再 `wf3.sh start <TASK-ID>`。
验收通过后由验收方（WorkBuddy）执行 PR 与提交，AI 不直接推 `main`。

## 6. 变更记录

| 日期 | 变更 | 触发 |
|---|---|---|
| 2026-10-28 | 初版；新增 `dev` 并设为默认分支；`ci.yml` push 触发加 `dev` | 需求 §12 / C41 |
| 2026-10-28 | 记录 Free 私有仓库 rulesets 不可用，改用 pre-push 钩子 + CI 守卫 | 实测 403 |
