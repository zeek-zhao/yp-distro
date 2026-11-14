# 分支模型（C41）

> 2026-11-01 修订：仓库转公开后 rulesets 已解锁，「不许直推 main」改由平台级规则
> 强制；同时 `dev` 集成线被取消，回到**单长期分支**的主干开发。
>
> 修订原因：`delete_branch_on_merge` 开启后，每次 `dev → main` 的 PR 合并都会把
> `dev` 一并删掉（已实际发生过一次），这套「双长期分支 + 自动删分支」的组合
> 本身自相矛盾。单人维护的公开仓库用主干开发更简单，也更符合外部贡献者的预期。

## 1. 分支一览

| 分支 | 角色 | 生命周期 |
|---|---|---|
| `main` | **唯一长期分支**：可发布、可复现。镜像与 tag 只从这里产生 | 永久 |
| `feat/<TASK-ID>-<slug>` | 单张任务卡的实现分支，如 `feat/72-kernel-trim` | 合并即删 |
| `fix/<slug>`、`docs/<slug>`、`chore/<slug>` | 缺陷、文档、杂务 | 合并即删 |

`master`（初始提交）与 34 条历史分支已于 2026-11-01 删除；`dev` 于同日随
`delete_branch_on_merge` 生效被自动删除，不再恢复。

## 2. 一次改动的完整路径

```
feat/72-kernel-trim ──PR──> main ──tag──> v0.5.0
```

1. 从 `main` 切分支：`git switch -c feat/<TASK-ID>-<slug>`
2. 在分支上提交（Conventional Commits：`feat|fix|docs|test|chore|refactor(scope): 摘要`）
3. 验收通过 → 开 PR 到 `main`，描述里贴验收命令与结果（`tasks/<ID>.md` 的验收节）
4. CI 全绿后合并；`delete_branch_on_merge` 会自动删掉任务分支
5. 阶段收口时在 `main` 打 annotated tag，触发 `images.yml` 产出 GHCR 镜像

## 3. CI 触发矩阵（改分支必须同步改这里）

| workflow | push | PR | 定时 | 手动 | 说明 |
|---|---|---|---|---|---|
| `ci.yml` | `main` | 全部 | — | ✅ | L1 静态 + BATS（含 4 版本矩阵）+ 密文扫描 + 身份门禁 + skip 门禁 |
| `images.yml` | 仅 `main` | — | — | ✅ | L2：4 镜像矩阵 → push GHCR |
| `pull-check.yml` | `main` | — | 每周一 06:00 | ✅ | 匿名拉取 + 非 root/工具链/UTF-8 断言 |

`ci.yml` 的 job 一览：`lint` / `bats` / `bats-release-matrix` / `secret-scan` /
`identity-guard` / `plan-sync` / `branch-guard`（备份）。

## 4. 门禁与约定

### 4.1 平台级（不可绕过）

转公开后 `POST /repos/.../rulesets` 已可用。`main` 上的 ruleset `protect-main`
（条件 `~DEFAULT_BRANCH`）实测生效的规则只有四条：

| 规则 | 效果 |
|---|---|
| `deletion` | 禁止删除 `main` |
| `non_fast_forward` | 禁止 force push |
| `pull_request` | 变更必须经 PR；`required_approving_review_count: 0`，但 `required_review_thread_resolution: true`（未解决的 review 讨论会挡合并） |
| `required_status_checks` | 必须通过的检查见下 |

必需状态检查共 9 项（名字就是 job 名，矩阵 job 带展开后缀）：

```
lint  bats  secret-scan  identity-guard  plan-sync
bats-release-matrix (dunfell)  (kirkstone)  (scarthgap)  (wrynose)
```

`strict_required_status_checks_policy: false`——不要求分支先 rebase 到最新
`main` 才能合并，所以并行 PR 之间不会互相排队。

> ⚠️ **`commit_author_email_pattern` 在仓库级 ruleset 上用不了**：创建该规则
> 返回 `422`（该参数只在组织级 ruleset 上生效，个人仓库没有组织）。
> 所以「提交作者邮箱」这一层**不在平台强制**，实际由前两层兜住：
> `commit-msg` 钩子（本地）+ `identity-guard`（CI 扫**全部历史**）。
> 这也正是 `identity-guard` 必须扫全历史、不能只扫本次 diff 的原因——
> 平台护栏缺了一角，最后一层就必须是全景的。

### 4.2 本地与 CI（可绕过，用于快速反馈与存量校验）

| 层 | 位置 | 管什么 | 绕过方式 |
|---|---|---|---|
| 本地钩子 | `.githooks/commit-msg`、`.githooks/pre-push` | 提交身份、AI 署名、多行 `\n`、直推 main | `--no-verify`（不要用） |
| CI 全历史 | `scripts/ci/identity-guard.sh` | 身份统一、内部信息、**AI 署名**（扫全部历史） | 无法绕过，红了就是真有问题 |
| CI 备份 | `ci.yml` 的 `branch-guard` | 校验 `main` 的 push 来自 PR | — |

> `identity-guard` 的 AI 署名检查**只匹配署名句式**（`Co-authored-by: <工具>`、
> `Generated with ...`、`🤖`），不做裸关键词匹配——`scripts/copilot-wrap.sh`
> 这类工具脚本仍在正常工作，提交消息提到它们属于正常工程记录。
>
> `identity-guard` 刻意放行 `noreply@github.com` 与 `*@users.noreply.github.com`：
> 那是平台在网页合并时生成的合成身份，不含个人信息；若也拦，每次网页合并都要
> force push 重写，反而会打断 PR 与提交的关联。

### 4.3 其他约定

- **PR 描述模板**：改动点 / 验收命令与输出 / 关联 Issue（`Closes #12`）/ 风险与回滚。
- **不改写已推送历史**：禁止 `push --force` 到 `main`。回滚用 `git revert`。
  确需重写（例如再次清理身份）必须先用 `git bundle create --all` 备份，并预期
  `branch-guard` 因 SHA 全变失效——恢复方式是**用 API 合并一个 PR**，不是 force push。
- **提交信息**：多行一律脚本文件 + `git commit -F <file>`（内联双引号会把 `\n` 变字面量，已踩过）。
- **任务卡与分支一致**：`tasks/<ID>.md` 元信息里的「分支」字段必须与实际任务分支同名。

## 5. ? AI ?????

?????????????? AI CLI ??**??????????**?
? `git switch -c feat/<TASK-ID>-<slug> main`?????????
?? WF3 ???? `scripts/wf3.sh` ?? 2026-11-14 ??????????
???????? `~/backup-wf3/`?`scripts/copilot-wrap.sh` ???
???? AI CLI ???? PAT ????????

## 6. 变更记录

| 日期 | 变更 | 触发 |
|---|---|---|
| 2026-10-28 | 初版；新增 `dev` 并设为默认分支 | 需求 §12 / C41 |
| 2026-10-28 | 记录 Free 私有仓库 rulesets 不可用，改用 pre-push 钩子 + CI 守卫 | 实测 403 |
| 2026-11-01 | 删除 34 条历史分支；历史重写统一身份 | 开源合规 |
| 2026-11-01 | 取消 `dev`，回到单长期分支；改用 ruleset 强制门禁 | 转公开 + `delete_branch_on_merge` 生效 |
