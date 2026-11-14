# 更新日志（CHANGELOG）

格式参考 Keep a Changelog；本仓库从 v1.0.0 起补记。发布判定与批次语义见
[`docs/06-process/plan/milestones.md`](docs/06-process/plan/milestones.md)。

## [1.0.2] - 2026-11-14

批次 B · 验证（测试能力，`2157a6c`）。随 #138 合并后单独点 tag，零功能。

- 新增 `config/features.txt` 第 6 列「证据级别」，「6.0 完成了多少」可数（#131）
- 新增 runtime smoke 三层镜像动作集（minimal/base/full 各自检查点，出 JUnit + 归档进 `docs/qa/wrynose/smoke-*.md`，#132）
- 新增 `docs/02-development/design.md`：分层 / class / 配方约定 / 注入点 / 扩展方式（#134）
- `tests/bats/99_coverage.bats` 校验 features 表头列数、第 6 列档位与 §6.1 矩阵一致、runtime feature ↔ smoke 动作集映射（2026-11-14 补强）

## [1.0.1] - 2026-11-14

批次 A · 修正（零功能 patch，`bf748c1`）。随 #138 合并后单独点 tag。

- `DISTRO_VERSION` → 1.0.0，`04_layer.bats` 断言改为 `git describe` 动态校验（#130）
- `config/supported-releases.txt` 成为「受保障版本」单一事实源（#127）
- CI 收缩到 6.0：删 `bats-release-matrix` job、显式 `BATS_TEST_RELEASE`、拉单镜像（#128）
- 合规收缩为 SPDX + CVE 两件，拆出 scancode 分支（#129）
- 全工程文档同步 batch1（#135，仍在途）

## [1.0.0] - 2026-11-05

四版收口（`1e1ff48`）。**注意：v1.0.0 宣称的四版全兼容是历史峰值，后续支持范围已收窄至 wrynose 6.0**（2026-11-09 决策，理由见 `docs/06-process/engineering-overview.md` §2.2）。`v0.5.0` / `v0.6.0` / `v0.7.0` 三个里程碑的内容全部累积进本版、从未单独打 tag（累积发布口径）。

- 四版 × 2 variant 回归 202/202/0/0，串口全命中（dunfell custom 的 `do_rootfs` 目录属性冲突 #109 已修复重建）
- 文档收口与发布（#86）、SDK / eSDK 恢复评估结论（#87）
- 累积：启动优化四项（内核裁剪 / systemd 精简 / rootfs 格式对比 / 收益-代价报告）、服务与 demo（yp-statusd / yp-collectd / 教程 / 服务数×耗时曲线）、5.0（scarthgap）对齐与四版补齐
- dm-verity 只读根路线二完成（篡改检出 + revert 验证）
