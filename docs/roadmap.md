# 工程计划（roadmap）

> 计划分三层，各管一件事，**不要重复维护**：
>
> | 层次 | 真源 | 管什么 |
> |---|---|---|
> | 有哪些活 | GitHub Issues | 具体任务、讨论、验收 |
> | 什么叫做完 | [`docs/plan/milestones.md`](plan/milestones.md) | 每个版本的**出口条件** |
> | 现在到哪了 | [`docs/handover.md`](handover.md) | 当前状态与下一件该做的事 |
>
> 本文件只给全景与阶段划分。开放问题清单由 `scripts/plan-sync.sh` 从 API 生成到
> [`docs/issues.md`](issues.md)，不要手改。

## 全景

```
基线 v0.1.0 ──→ 打通 v0.2.0 ──→ U-Boot/systemd v0.3.0 ──→ 语法组 v0.4.0
                                                              │
                              ┌───────────────────────────────┘
                              ▼
                    启动优化 v0.5.0 ──→ 服务与 demo v0.6.0 ──→ 5.0 对齐 v0.7.0 ──→ 四版收口 v1.0.0
```

**当前位置**：`v0.4.0` 已发布；PR #113 待合并——它一次收口 v0.5.0（#72–#75 启动
优化，boot-baseline §6-§8）、v0.6.0（#78）、v0.7.0（#80–#84，含 6.0 优化移植到
5.0/4.0，§10）与 v1.0.0 的回归归档（#85，8/8 全绿）；外加 #110/#114 两个修复与
新门禁。合并后 v1.0.0 只剩发版动作（tag + Release）与 #107 的 GitHub 工单。

## 阶段与出口条件

| 阶段 | 版本 | 出口条件（一句话） | 状态 |
|---|---|---|---|
| 基线 | v0.1.0 | 四镜像可拉、配置骨架、报告链、CLI 齐 | ✅ |
| 打通 | v0.2.0 | 每版本 × 每 variant 一次真构建 + QEMU 通过，报告归档 | ✅ |
| 启动链 | v0.3.0 | 镜像能起，`init` 管理器可切换，U-Boot 链完整 | ✅ |
| 语法组 | v0.4.0 | 六构建系统配方真构建 + 装进 full 镜像 + 语法对照表 | ✅ |
| 启动优化 | v0.5.0 | 四项优化各有测量数据**与代价说明** | 出口条件达成（待合并） |
| 服务 | v0.6.0 | 服务可起 + 采集可见 + 服务数×耗时曲线 | 出口条件达成（待合并） |
| 5.0 对齐 | v0.7.0 | scarthgap 与 wrynose 能力对齐 | 出口条件达成（待合并） |
| 收口 | v1.0.0 | 四版全回归 + 文档收口 + SDK 结论 | 出口条件达成（待合并） |

细节（每条出口条件的验收项）见 [`docs/plan/milestones.md`](plan/milestones.md)。

## 约束（比计划更容易忘）

1. **跨 release 的能力不能假设可移植**：dunfell 3.1 与 wrynose 6.0 之间隔了三代
   语法（`S`→`UNPACKDIR`、sysvinit→systemd、`DISTRO_FEATURES_BACKFILL` 移除）。
   任何「在 6.0 上成立」的结论，在 5.0 上要重新验证。
2. **构建顺序固定为 wrynose → scarthgap → kirkstone → dunfell**：先在已热的
   sstate 上拿第一份报告，把风险后置。
3. **同一组实验的三个变量必须串行**：#72/#73/#74（内核 / systemd / rootfs 格式）
   互相影响启动耗时，同时改就推不出单项收益。

## 阶段收口动作

1. 该里程碑下开放的 issue 清零；
2. 开一个 PR 合入 `main`（ruleset 与 `branch-guard` 都只认 PR 合并），描述里贴验收结论；
3. 在 `main` 上打 annotated tag `vX.Y.Z`，tagger 必须是 `zeek.zhao <zeek.zhao@foxmail.com>`；
4. 建 Release，关闭里程碑；
5. 更新 `docs/plan/milestones.md` 的勾选与 `docs/handover.md` 的「当前位置」。
