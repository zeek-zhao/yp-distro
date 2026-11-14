# 文档索引（INDEX）

> 分类编号 + 全量索引。新文档必须登记本表并归入对应编号目录。
> 机器管理区豁免编号：`docs/issues.md`（plan-sync 生成）、`docs/qa/`（report.sh/smoke.sh 证据归档）。

| 编号 | 类别 | 文档 | 说明 |
|---|---|---|---|
| 00 | 入口 | [README](README.md) | 工程入口与上手路线 |
| 00 | 入口 | 本文件 | 文档树索引 |
| 01 | 需求 | [01-requirements/README.md](01-requirements/README.md) | 需求包导览（生成器产物） |
| 01 | 需求 | [01-requirements/srs.md](01-requirements/srs.md) | SRS（ISO 29148 轻量） |
| 01 | 需求 | [01-requirements/traceability.md](01-requirements/traceability.md) | FR→Scenario→bats→归档 四向矩阵 |
| 01 | 需求 | [01-requirements/acceptance-plan.md](01-requirements/acceptance-plan.md) | 验收计划（ISO 12207 轻量，A1–A6） |
| 01 | 需求 | [01-requirements/scenarios/](01-requirements/scenarios/) | Gherkin 场景层（206，映射 205 bats） |
| 01 | 需求 | [01-requirements/features.md](01-requirements/features.md) | 功能说明书（数据唯源 config/features.txt） |
| 01 | 需求 | [01-requirements/verification-flow.md](01-requirements/verification-flow.md) | 验证流程与功能→证据矩阵 |
| 02 | 开发 | [02-development/design.md](02-development/design.md) | 总体设计 |
| 02 | 开发 | [02-development/naming.md](02-development/naming.md) | 命名规范 |
| 02 | 开发 | [02-development/distro-features.md](02-development/distro-features.md) | DISTRO_FEATURES |
| 02 | 开发 | [02-development/boot-chains.md](02-development/boot-chains.md) | 启动链 |
| 02 | 开发 | [02-development/boot-optimization.md](02-development/boot-optimization.md) | 启动优化 |
| 02 | 开发 | [02-development/adding-a-service.md](02-development/adding-a-service.md) | 新增服务指南 |
| 02 | 开发 | [02-development/functional-flow.md](02-development/functional-flow.md) | 功能流 |
| 02 | 开发 | [02-development/syntax-matrix.md](02-development/syntax-matrix.md) | 语法矩阵 |
| 03 | 构建 | [03-build/getting-started.md](03-build/getting-started.md) | 上手指南 |
| 03 | 构建 | [03-build/kas.md](03-build/kas.md) | kas 构建 |
| 03 | 构建 | [03-build/build-env.md](03-build/build-env.md) | 构建环境 |
| 03 | 构建 | [03-build/container.md](03-build/container.md) | 容器化构建 |
| 03 | 构建 | [03-build/cli.md](03-build/cli.md) | 工程 CLI |
| 03 | 构建 | [03-build/local-workspace.md](03-build/local-workspace.md) | 本地目录保留说明 |
| 03 | 构建 | [03-build/sdk.md](03-build/sdk.md) | SDK 导出与使用 |
| 04 | 测试 QA | [qa/README.md](qa/README.md) | **证据归档区（原位豁免）**：boot-baseline / variant-matrix / security / all / wrynose / acceptance |
| 05 | 发布 | [05-release/point-releases.md](05-release/point-releases.md) | 点版本流程（wrynose 单源） |
| 05 | 发布 | [05-release/compliance.md](05-release/compliance.md) | 合规（SPDX SBOM + CVE） |
| 05 | 发布 | [05-release/cve.md](05-release/cve.md) | CVE 管理 |
| 05 | 发布 | [05-release/scancode.md](05-release/scancode.md) | 许可证扫描（do-scancode，豁免登记） |
| 06 | 流程 | [06-process/branching.md](06-process/branching.md) | 分支与 PR 规范 |
| 06 | 流程 | [06-process/ci.md](06-process/ci.md) | CI 说明 |
| 06 | 流程 | [06-process/handover.md](06-process/handover.md) | 交接文档 |
| 06 | 流程 | [06-process/engineering-overview.md](06-process/engineering-overview.md) | 工程总览 |
| 06 | 流程 | [06-process/knowledge-base.md](06-process/knowledge-base.md) | 知识库 |
| 06 | 流程 | [06-process/backlog.md](06-process/backlog.md) | backlog |
| 06 | 流程 | [06-process/roadmap.md](06-process/roadmap.md) | 路线图 |
| 06 | 流程 | [06-process/plan/milestones.md](06-process/plan/milestones.md) | 里程碑 |
| 06 | 流程 | issues.md（docs 根） | 工程任务账（plan-sync 生成，豁免编号） |
| 07 | AI | [07-ai/AI-DEVELOPMENT.md](07-ai/AI-DEVELOPMENT.md) | AI 开发规范（身份/流程/工具链/禁区） |
| 07 | AI | [07-ai/ai-handover.md](07-ai/ai-handover.md) | AI 交接档案 |
| 08 | 任务 | [08-tasks/README.md](08-tasks/README.md) | 任务卡目录（含 23 张归档索引） |
