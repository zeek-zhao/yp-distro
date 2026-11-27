# YP-M0.1-PLAN-001 · M0.1 证据闭环计划与进度

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0.1-PLAN-001 |
| 版本 | v1.3 |
| 状态 | Approved + M0.1.1 增补（E1–E5 见 v1.2；E6/E7/E8 资源并发与发布线增补见 RV-020；`m0.1` tag 仍对应历史 v1.2 的 `91adcc5`，不改写旧结论） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-26 |
| 关联 | AI-007 v1.1 §6（`docs/ai/m0-readme-prereq-and-pathb-closeout-prompt.md`）；AI-009 v1.0；RV-018 / RV-019 / RV-020 / CHG-020 / CHG-021 / ISS-036 / ISS-037 |

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
| E4 | 发布 CI 4 job 观察 | RV-018 §4：gate `45820896095` / publish `45820900729` 均 success，4 job 全绿，head_sha=`0ce4a5e` | 已验证 |
| E5 | 记录收口 + `m0.1` tag + `release-m0` | 本目录全套文档 + tag | 已完成 |
| E6 | 并发资源化 + bitbake 真生效（M0.1.1） | RV-020 §1：threads.sh=standard/32/-j16；fresh getvar=32/-j16（ISS-037 修复：cpu_count 动态分级）；变量契约防回归 | 完成 |
| E7 | 全配额构建复验 + 4c/8G 边界（M0.1.1） | RV-020 §2：容器 inspect 0/0/0；prod 构建 #1 14s / #2 314s、0 ERROR、all succeeded、ext4 42M；CPU ~400%/mem ~2.2GiB 无 OOM；4c/8G 全冷构建未跑 | 部分完成：全配额构建通过；4c/8G 全冷构建 UNVERIFIED |

## 2. 出口判据（§6.7）

E1 真实全量、E2 --parts 1 拒绝与 direct、E3 ghcr/K-8/布局、E4 publish 4 job、E5 记录与门禁，全部有真实输出或明确 UNVERIFIED；不以本地检查冒充远端，不以 sample 冒充 full。M0.1.1 增补 E6/E7/E8 另按 AI-009 §6 验收矩阵口径，核心是「32 线程真生效 + 容器无限制 + 无 OOM」，4c/8G 冷构建未跑记 UNVERIFIED（见 RV-020 §3）；E8 发布线 CI 已真实通过（RV-020 §5.2）。

## 3. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-26 | 建立 M0.1 证据闭环计划；E1–E3 完成，E4–E5 进行中 | zeek.zhao |
| v1.1 | 2026-11-26 | E4 CI 回填：workflow_dispatch 触发 gate/publish 均 success、4 job 全绿；E5 冻结待执行 | zeek.zhao |
| v1.2 | 2026-11-26 | E5 冻结完成：acceptance 状态 Final、E5 记录收口 + m0.1 tag + release-m0 分支打在本版提交 | zeek.zhao |
| v1.3 | 2026-11-26 | M0.1.1 增补：E6 并发资源化（threads.sh + cpu_count 动态分级，ISS-037/CHG-021）+ E7 全配额构建复验（RV-019/RV-020，4c/8G UNVERIFIED）；m0.1 tag 仍冻结于 91adcc5 | zeek.zhao |
