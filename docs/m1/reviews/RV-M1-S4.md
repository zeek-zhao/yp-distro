# YP-M1-RV-005 · M1-S4 四问评审（buildhistory、层自检与四步 CI）

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-005 |
| 版本 | v1.0（设计评审；实测证据待实现提交后回填 v1.1） |
| 评审对象 | YP-M1-S4 实现（buildhistory 配置+diff 归档、check-layer 正/负向、four-step.sh、m1-dev.yml）；设计 DES-005 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-28 |
| 关联 | `docs/m1/plan.md` §M1-S4 §3.4 §5 §7；`docs/m1/design/S4-ci-buildhistory.md`（DES-005）；S3=`b858798` |
| 结论 | 待实现回填（设计阶段 Q1–Q4 通过；D-06/D-08 本地实测、D-09 远端 CI 3 次 green 待回填，分层口径按真实证据） |

## 1. 四问自评

**Q1 覆盖需求**：S4 目标「buildhistory diff 可读并归档（D-06）、check-layer 正/负向（D-08）、四步流程 CI（D-09）」由 `kas/editions/dev.yml`（buildhistory 配置）、`scripts/ci/buildhistory-diff.sh`（归档）、`scripts/ci/check-layer.sh`（正/负向）、`scripts/dev/four-step.sh` + `.github/workflows/m1-dev.yml`（四步 CI）逐项覆盖；D-07 bblock 为 P2 可选、不进 gate。devshell 交互按 plan §3 标 UNVERIFIED，不冒充四步之一。不打 m1.0、不改 M0、不建 M2、不引入 self-hosted、不改 M0 workflow paths。✅

**Q2 真实证据**：所有技术结论来自设计阶段容器内真实探测（buildhistory 变量默认值、GitPython 3.1.37、check-layer 用例逐项 ok/FAIL、test_world 触发 `bitbake -S lockedsigs world`）；正向 FAIL 原因（缺 README/SECURITY.md）如实记录并在实现阶段补文档修复；CI「3 次连续 green」以 GitHub Actions 实际 run 为准，本地通过只写「单次/本地通过」，不伪造。✅

**Q3 失败处理**：check-layer 正向 FAIL 先定位到具体用例与断言（`test_readme`/`test_security`），补合规文档而非屏蔽检查；`test_world` 因资源卡住标 `RESOURCE_PARTIAL`/`UNVERIFIED`、开 ISS；CI 未触发/未跑满 3 次按前序口径如实记「未触发（分支不匹配）」或 `SINGLE_PASS`，不降级成「未跑也通过」。✅

**Q4 边界与卫生**：新增文件不含真实 token、不含远程缓存服务器配置（`SSTATE_MIRRORS=`/远程 hashserv，gate G3）、不含阈值数值字面值（gate G2）；commit 身份 `zeek.zhao <zeek.zhao@foxmail.com>` 一次性 `-c`，不写 git config；归档为文本 diff/日志，无大二进制入库。✅

## 2. 设计阶段真实探测证据

- **buildhistory**：`buildhistory.bbclass` 默认值 `BUILDHISTORY_FEATURES="image package sdk"`、`BUILDHISTORY_DIR=${TOPDIR}/buildhistory`、`BUILDHISTORY_COMMIT=1`；`scripts/buildhistory-diff` 依赖 `import git` → `3.1.37`；现有 `local.conf` 未启用。
- **check-layer**：工具与 wrapper 齐全；依赖 `yocto`=meta-poky，可行组合为 wrapper（干净 build）+ `--dependency <meta-poky> <meta-oe>`；正向用例实测 `test_layerseries_compat/parse/patches_upstream_status/show_environment/signatures` ok，`test_readme`/`test_security` FAIL（缺 README/SECURITY.md），`test_world` 触发 `bitbake -S lockedsigs world`（重）。负向构造 = 仅含 `conf/layer.conf` 无 README 的临时层，确定性 FAIL。
- **四步 CI**：`m0-gate.yml`/`m0.yml` 过滤 `feat-m0*`/`release-m0*`，本分支不匹配（前序 S0–S3 CI `total_count=0`）；`ci.yml` 过滤 `[main]`。需新增 `m1-dev.yml`（`feat-m1*` + `workflow_dispatch`），资源口径按 plan §3.4（hosted、无限制、打印 nproc/MemTotal、低于基线标 RESOURCE_PARTIAL）。

## 3. 实测证据（实现提交后回填 v1.1）

待回填：buildhistory 两次构建 diff 实际输出与归档路径；check-layer 正向补 README/SECURITY 后的用例结论（含 test_world 口径）、负向临时坏层 FAIL 输出；four-step.sh 四步 `STEP_*` 日志段与失败路径；m1-dev.yml 语法/触发配置与远端 Actions 实际 run 状态（是否触发、3 次 green 是否达成）；GATE_PASS/VARS_OK；CI 状态（如实）。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S4 设计四问评审 + 设计阶段真实探测证据（buildhistory 变量/GitPython、check-layer 依赖解析与正/负向用例、test_world 重型结论、四步 CI 资源与分支口径）；实测待回填 | zeek.zhao |
