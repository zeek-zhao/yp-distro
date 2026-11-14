# docs/requirements —— 需求与 BDD 场景层（ISO/IEC/IEEE 29148 轻量落地）

- `srs.md`：软件需求规格（29148 结构：引言/总体描述/具体需求/验收准则）
- `traceability.md`：FR/NFR → Gherkin 场景 → bats 用例 → QA 证据 的追溯矩阵（生成物）
- `scenarios/*.feature`：BDD 场景层，按 9 个模块组织，映射 205 个 bats 用例（生成物，勿手改用例名）
- `acceptance-plan.md`：ISO/IEC/IEEE 12207 验收流程与判据

**事实源约定**：功能清单唯一事实源仍是 `config/features.txt`；本目录全部生成物由 `scripts/ci/gen_requirements.py` 再生，bats 本体是唯一可执行事实。

