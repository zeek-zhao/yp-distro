# 交接文档

> 面向「下一个接手的人」——包括三个月后的你自己。只写**现在的事实**和**还没做完的事**，
> 过程记录留在 issue 与 `docs/qa/` 归档里。
>
> 最后更新：2026-11-01

## 一、这个仓库现在是什么状态

| 维度 | 现状 |
|---|---|
| 仓库 | `zeek-zhao/yp-distro`，公开，MIT，默认分支 `main`（**只有 `main` 一条长期分支**） |
| 版本 | `v0.4.0` 已发布（6.0 语法组：六构建系统 + 服务模板）；下一站 `v0.5.0` 启动优化 |
| 构建 | 4 发行版（dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 / wrynose 6.0）× 2 variant（general/custom）。CI 只做静态；**真构建要在构建机上跑** |
| 镜像 | `ghcr.io/zeek-zhao/yp-distro/{dunfell,kirkstone,scarthgap,wrynose}` 四个都公开，带 OCI 许可标签 |
| 许可 | 仓库源码 MIT；**构建镜像与 Yocto 产物不是 MIT**，见 `THIRD_PARTY_NOTICES.md` |

## 二、已经验证过的能力（别重复验证）

这些是花过真机成本换来的结论，重跑一遍只是烧时间：

- **L3 真构建通**：9 个配方 `2184 tasks all succeeded`；full 镜像 `4367 tasks all succeeded`
- **起机取证通**：`yp-statusd` / `yp-collectd` 两个服务 `enabled`+`active`，
  `/status` 返回 JSON，`journalctl` 有采集记录
- **四个发行版镜像可匿拉**：`pull-check` 工作流每推一次 `main` 验一遍

## 三、还没做完的事

按「能不能马上动手」排序，详细出口条件见 `docs/plan/milestones.md`：

1. **v0.5.0 启动优化（#72–#75）** —— 已解除阻塞，缺的是测量轮次。
   内核裁剪 / systemd 精简 / rootfs 格式这三个是**同一组实验的三个变量**，要串行做才有可比性。
2. **v0.6.0 只剩 #78** —— 服务数 × 启动耗时曲线，`boot-exec.sh` 与 `boot-time.sh` 都可用。
3. **v0.7.0 scarthgap 对齐（#80–#84）** —— 五个 issue 挂在同一个前置上：scarthgap 首构建。
   前置没通之前并行等于五个一起卡住。
4. **v1.0.0 收口（#85–#87）** —— 四版本全回归、文档收口、SDK 评估。

## 四、纪律（违反会留下永久痕迹）

- **提交身份**：author + committer 都必须是 `zeek.zhao <zeek.zhao@foxmail.com>`。
  外部贡献者可以提交，但要带 `Signed-off-by`（DCO，见 `CONTRIBUTING.md`）。
- **禁 AI 署名**：`Co-authored-by: <工具>`、`Generated with ...`、`🤖` 一律拒。三层门禁：
  本地 `.githooks/commit-msg`、CI `identity-guard`（扫全历史）、GitHub ruleset。
- **禁自己 co-author 自己**：单人仓库里没有意义，钩子会拒。
- **改历史前先备份**：`git bundle create --all`。改完 `branch-guard` 会因 SHA 全变而失效，
  恢复方式是**用 API 合并一次 PR**，不是 force push。
- **`wf3 tokens` 会改 `docs/tokens.html` 与 `metrics/token-usage.tsv`**，提交前 `git checkout --` 还原。

## 五、想了解「为什么这样设计」

- 构建入口与分层：`docs/cli.md`、`docs/container.md`
- 分支与发版：`docs/branching.md`
- CI 门禁：`docs/ci.md`
- 合规与分发义务：`docs/compliance.md`、`THIRD_PARTY_NOTICES.md`
- 历史决策记录：各 issue 正文（尤其 #56、#61、#64、#71 的讨论）
