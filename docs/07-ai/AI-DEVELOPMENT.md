# AI 开发文档（AI-DEVELOPMENT）

> 本文档规定 AI（自动化代理）参与本工程开发时的身份、流程、工具链与禁区。
> 交接背景与历史决策见 [ai-handover.md](ai-handover.md)；分支规范见 [../06-process/branching.md](../06-process/branching.md)。

## 1. 身份与合规（不可协商）

- 提交身份统一 `zeek-zhao <GitHub noreply 邮箱>`（见 config/ 与 .githooks/commit-msg 默认值，PR #140）。
- `scripts/ci/identity-guard.sh` 全历史扫描企业邮箱残留；提交信息**禁止任何 AI 署名 trailer**（Co-authored-by / Generated with / 🤖）。
- 禁止重写已发布历史（force push main）；唯一例外=所有者明确授权（先例：#107 身份治理，2026-11-13）。
- force push main 需要：本地 `ALLOW_MAIN_PUSH=1`（pre-push 钩子紧急口）+ ruleset 临时 bypass（用后还原）。

## 2. 分支与 PR 流程

- 一切 main 变更走 PR（branch-guard 强制）；分支命名 `feat|chore|docs/<主题>`。
- 分支必须从**最新** origin/main 切出；重写后 fetch 一律用强制 refspec `+refs/heads/main:refs/remotes/origin/main`。
- 合并惯例=squash（标题带 `(#PR)`）；合并后本地 `checkout -f main + reset --hard origin/main`，远端分支依赖仓库 auto-delete。
- draft PR 转 ready：REST PATCH 对 draft 无效，用 GraphQL `markPullRequestReadyForReview`。

## 3. CI 门禁

- 五个必过 job：bats / lint / secret-scan / identity-guard / plan-sync；branch-guard、pull-check 为 push-main 附加。
- CI 未自动触发时可用 dispatch 通道：`POST /actions/workflows/ci.yml/dispatches {"ref":"<branch>"}`。
- plan-sync 红=main 的 docs/issues.md 落后（issue 状态变化），跑 `GH_TOKEN=<token> bash scripts/plan-sync.sh` 重新生成后随 PR 提交。

## 4. 工具链地图

| 工具 | 用途 | 备注 |
|---|---|---|
| `scripts/release-check.sh` | 全 release×variant 一轮构建+测试+新鲜度 | A1 验收判据；重活，后台跑 |
| `scripts/report.sh all` | 210 用例全量+JUnit+归档 | A2 判据；与 release-check 不要并发（构建锁竞争） |
| `scripts/ci/gen_requirements.py` | 从 features.txt+bats 生成 docs/01-requirements/ 产物 | 生成物勿手改；重跑 diff 必须为空 |
| `scripts/plan-sync.sh` | GitHub Issues → docs/issues.md | issues.md 为生成物 |
| `scripts/smoke.sh` | 起机动作集取证（JUnit+归档） | degraded 项不进动作集 |
| `scripts/cve-db.sh` | CVE 库离线维护 | work/downloads/CVE_CHECK/ |
| `scripts/container.sh` | 容器构建入口 | sstate 映射 /work/work/sstate |

## 5. 数据与生成物

- `config/features.txt` 是功能注册表**唯一事实源**（26 FR×6 列）；features.md / srs / scenarios / traceability 全部由其派生或引用。
- `docs/qa/` 为机器证据归档区（report.sh / smoke.sh 动态写入），不入分类树、QA 归档默认不进 PR。
- 降级/豁免一律登记 `config/degraded.txt`；CI 结构性 skip 按 docs/ci.md 口径不算缺陷。
- 验收流程与判据：[../01-requirements/acceptance-plan.md](../01-requirements/acceptance-plan.md)。

## 6. 文档维护约定

- 文档树按编号分类（见 [../INDEX.md](../INDEX.md)）；新文档必须登记索引并归入编号目录。
- `docs/qa/` 与 `docs/issues.md` 为机器管理区，豁免编号。
- 04 类（QA 证据）物理位置保持在 `docs/qa/`，由 report.sh 动态读写。
