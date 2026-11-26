# YP-M0.1-PLAN-001 · M0.1 证据闭环计划与进度

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-PLAN-001 |
| 版本 | v1.0 |
| 状态 | Approved（评审通过 AI-007 v1.1 §6 后执行；基线 `m0.0` = `06543c4`） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-26 |
| 关联 | AI-007 v1.1 §6（`docs/ai/m0-readme-prereq-and-pathb-closeout-prompt.md`）；RV-018 / CHG-020 / ISS-036 |

## 0. 范围与边界

- 分支：`feat-m0.1-evidence`（基于 `m0.0`）；只做证据闭环，不新增发行版功能、不碰 `main`、不改 M0 Final 结论。
- 真实全量测试在独立隔离目录执行，不下载替代资产、不手工 tar 替代 fetch。
- 编号顺延 M0：DES-010（本次无需新设计单，布局确认记 CHG-020）、RV-018、CHG-020、ISS-036，不跳号。

## 1. 工作项进度

| 项 | 内容 | 证据 | 状态 |
|---|---|---|---|
| E1 | 真实 release 8 片正常顺序全量（verify-env→fetch→bootstrap→preflight） | RV-018 §1：REASSEMBLE_OK 11153387520 / SHA256_OK=1c8126d4… / STRUCT_OK direct | 完成 |
| E2 | 8 片重组边界（--parts 1 拒绝、unpack-only 布局、回退用例） | RV-018 §2 | 完成 |
| E3 | ghcr 全链路 + K-8 + GHCR 源 tar 布局确认 + ISS-036 | RV-018 §3；CHG-020；ISS-036 | 完成 |
| E4 | 发布 CI 4 job 观察 | RV-018 §4（push 后回填） | 进行中 |
| E5 | 记录收口 + `m0.1` tag + `release-m0` | 本目录全套文档 + tag | 进行中 |

## 2. 出口判据（§6.7）

E1 真实全量、E2 --parts 1 拒绝与 direct、E3 ghcr/K-8/布局、E4 publish 4 job、E5 记录与门禁，全部有真实输出或明确 UNVERIFIED；不以本地检查冒充远端，不以 sample 冒充 full。

## 3. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-26 | 建立 M0.1 证据闭环计划；E1–E3 完成，E4–E5 进行中 | zeek.zhao |
