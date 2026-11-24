# 偏离记录

> PRD 之外必要的偏离，逐条记录：偏离什么、为什么、影响、批准人、何时复核。无偏离时保留本文件与表头。

| # | 偏离内容 | 理由 | 影响 | 批准人 | 复核条件 |
|---|---|---|---|---|---|
| 1 | 无法按 m0-prompt 第六节第 4 条开 draft PR：本分支按第 1 条为孤立分支（与 main 无共同历史），GitHub 拒绝创建 PR | 规范内部互斥；GitHub 要求 base/head 有共同祖先，实测报错（见 YP-M0-ISS-002） | S1 提交与 push 正常；评审改用 commit diff + RV 记录；CI 由 workflow_dispatch 触发（S8 落地） | zeek.zhao（人类批准方案 A，2026-11-24，见 YP-M0-ADR-002） | 若将来决定并入 main，须新开 ADR 并走 CHG 重新评估 |
