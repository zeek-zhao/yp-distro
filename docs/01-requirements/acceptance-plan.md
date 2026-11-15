# 验收计划与判据（ISO/IEC/IEEE 12207 轻量落地）

> 配套 [`srs.md`](srs.md)（29148 需求基线）。验收对象：yp-distro v1.0.x 工程能力全集（FR-001…FR-026 + NFR-001…NFR-008）。

## 1. 验收输入
- 需求基线：`docs/01-requirements/srs.md` + `traceability.md`
- 可执行事实：`tests/bats/`（205 个非 meta 用例 + 99_coverage 6 个元测试）
- QA 归档证据：`docs/qa/<release>/`（report.sh 产物）
- 降级登记：`config/degraded.txt`

## 2. 验收方法与步骤

| # | 步骤 | 判据 | 证据产物 |
|---|---|---|---|
| A1 | `bash scripts/release-check.sh`（全 release × variant 一轮） | 退出码 0，全部 FRESH，无 stale | 控制台 + docs/qa 归档 |
| A2 | `bash scripts/report.sh all`（205+6 用例全量） | 全绿（degraded 特性的 skip/降级须在 degraded.txt 有登记） | reports/bats-all-general-*.xml + docs/qa/all/*.md |
| A3 | 追溯矩阵核验：`gen_requirements.py` 重跑后 git diff 为空 | scenarios/traceability 与 features.txt 一致（无手改漂移） | git diff 输出 |
| A4 | 四向追溯抽查：FR → Scenario → bats 用例 → QA 归档路径 | traceability.md 每行 FR 均能走到一份真实归档 | 抽查记录写入验收报告 |
| A5 | CI 门禁：PR 的五个 job 全绿 | bats/lint/secret-scan/identity-guard/plan-sync success | GitHub Actions run |
| A6 | NFR 抽验：NFR-001…NFR-008 证据指针逐一有效 | 指针指向的脚本/测试/文档存在且语义匹配 | 验收报告 NFR 节 |

## 3. 缺陷与豁免口径
- **缺陷**：任何 FR 判据失败且未在 degraded.txt 登记的项。验收不允许「跳过即通过」。
- **豁免**：degraded 登记（foss-scan、do-scancode、distro-backfill）按登记原因豁免，但须在验收报告的缺陷节列出并注明登记 id/原因。
- CI 上的结构性 skip（如 99_coverage 归档依赖、03_container 镜像依赖）按 `docs/06-process/ci.md` 与用例内 skip 理由核验，不算缺陷。

## 4. 验收产物
- `docs/qa/acceptance/<date>-<sha>.md` 验收报告，固定章节：
  1. 验收范围与基线（SRS 版本/commit SHA）
  2. A1–A6 执行记录（命令、退出码、产物路径）
  3. 缺陷与豁免清单
  4. 四向追溯结论（需求→场景→用例→归档，覆盖率 100%）
  5. 验收结论（通过/有条件通过/不通过）
- 验收报告归档后由 99_coverage/report.sh 的动态机制自然纳入后续报告。

## 5. 角色与流程
- 验收执行：本工程自动化（release-check + report.sh）。
- 验收判定：验收报告生成后由仓库所有者（用户）review 归档并确认结论；验收 commit 走正规 PR（CI 五 job 门禁）。
- 重复验收：任何影响 FR 判据的变更合入后，重跑 A1–A3 并更新验收报告（点版本时随 release-check 顺带执行）。
