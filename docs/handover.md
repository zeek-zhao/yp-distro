# 交接文档

> 面向「下一个接手的人」——包括三个月后的你自己。只写**现在的事实**和**还没做完的事**，
> 过程记录留在 issue 与 `docs/qa/` 归档里。
>
> 最后更新：2026-11-03

## 一、这个仓库现在是什么状态

| 维度 | 现状 |
|---|---|
| 仓库 | `zeek-zhao/yp-distro`，公开，MIT，默认分支 `main`（**只有 `main` 一条长期分支**） |
| 版本 | `v0.4.0` 已发布（6.0 语法组：六构建系统 + 服务模板）；四版回归 8/8 已恢复（2026-11-03），当前在做 `v0.5.0` 启动优化（#72–#75 串行实验） |
| 构建 | 4 发行版（dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 / wrynose 6.0）× 2 variant（general/custom）。CI 只做静态；**真构建要在构建机上跑** |
| 镜像 | `ghcr.io/zeek-zhao/yp-distro/{dunfell,kirkstone,scarthgap,wrynose}` 四个都公开，带 OCI 许可标签 |
| 许可 | 仓库源码 MIT；**构建镜像与 Yocto 产物不是 MIT**，见 `THIRD_PARTY_NOTICES.md` |

## 二、已经验证过的能力（别重复验证）

这些是花过真机成本换来的结论，重跑一遍只是烧时间：

- **L3 真构建通**：9 个配方 `2184 tasks all succeeded`；full 镜像 `4367 tasks all succeeded`
- **八组合回归 8/8 通过**：`f66f35b` 时 7/8（归档在 `docs/qa/*/20261101-f66f35b*.md`），
  dunfell custom 于 2026-11-03 重建恢复（2944 tasks 全绿 + `boot-exec` 起机取证）。
  #109 的根因是 11-01 实验期在 deploy 里留下的新旧混合 rpm（`yp-collectd` 与
  **python3 全系**带 0700 目录，含纯上游的 python3-tkinter），配方本身无罪——
  `install -d` 在容器里实测 0755。教训：**do_rootfs 报目录属性冲突时先查 rpm
  元数据再怀疑配方**，`deploy/rpm` 里新旧产物混存时错误线索会指向自家包互撞。
- **四版 SDK/eSDK 都能出**：SDK 466 MB、eSDK 3003 MB，内含 gcc 13，`devtool` 可用，
  结论与命令见 `docs/sdk.md` §8
- **起机取证通**：`yp-statusd` / `yp-collectd` 两个服务 `enabled`+`active`，
  `/status` 返回 JSON，`journalctl` 有采集记录
- **四个发行版镜像可匿拉**：`pull-check` 工作流每推一次 `main` 验一遍

### 语法结论（被推翻过一次，别按老笔记改）

- **变量级** override：3.1 只认 `VAR_append`，4.0+ 只认 `VAR:append`。下划线版在 4.0+
  是**致命**解析错误（`data_smart.py`「old override syntax」），而且报错会挂到所有求值到
  同名变量的 recipe 上（连上游 `base-files` / `systemd` 一起红）。变量层只能用
  `python __anonymous` 按 `LAYERSERIES_CORENAMES` 给 3.1 补下划线版。
- **任务级** override：`do_install:append()` / `do_configure:prepend()` 这种函数语法
  **3.1 也认**。曾经把「变量不认冒号」推广到「函数也不认」，给每个 `do_install:append`
  又补一份 `do_install_append`，结果同一个 `do_install` 里被调了两次（症状是
  `xxx: not found` 的 exit 127）。任务级一律只留冒号一份。

  > 取证方式：把 python 补丁全删掉后 `bitbake -c install -f <recipe>`，看 dunfell 生成的
  > `do_install` 里有没有那个函数调用。这比读版本号靠谱。

- **不能为了兼容 3.1 改用「独立任务 + `addtask`」**：自定义任务不在 `PSEUDO_TASKS` 里，
  不经 pseudo，装出来的文件属主是真实宿主 uid，`do_package_qa` 立刻判 `host-user-contaminated`。

## 三、还没做完的事

按「能不能马上动手」排序，详细出口条件见 `docs/plan/milestones.md`：

1. **v0.5.0 启动优化（#72–#75）** —— 测量链前置（#110）已修（PR #113）。内核裁剪 /
   systemd 精简 / rootfs 格式这三个是**同一组实验的三个变量**，必须串行做才有可比性；
   #75 把结果汇总成 `docs/boot-optimization.md`。
2. **v0.6.0 只剩 #78** —— 服务数 × 启动耗时曲线（三层镜像 × runs 5）。
3. **v0.7.0 scarthgap 对齐（#80–#84）** —— 五个 issue 挂在同一个前置上：scarthgap 首构建。
   前置没通之前并行等于五个一起卡住。
4. **#85 四版全量回归与报告归档** —— 回归 8/8 已恢复，但 #85 的验收（全量 bats 0 失败
   0 skip、8 份归档、启动基线落盘）要等上面的优化实验做完后**最后**跑，否则归档马上过时。
5. **#107 清 `refs/pull/*/head` 里的旧 commit 引用** —— 要 GitHub Support 介入，不占本地工期。

## 四、纪律（违反会留下永久痕迹）

- **提交身份**：author + committer 都必须是 `zeek.zhao <zeek.zhao@foxmail.com>`。
  外部贡献者可以提交，但要带 `Signed-off-by`（DCO，见 `CONTRIBUTING.md`）。
- **禁 AI 署名**：`Co-authored-by: <工具>`、`Generated with ...`、`🤖` 一律拒。三层门禁：
  本地 `.githooks/commit-msg`、CI `identity-guard`（扫全历史）、GitHub ruleset。
- **禁自己 co-author 自己**：单人仓库里没有意义，钩子会拒。
- **改历史前先备份**：`git bundle create --all`。改完 `branch-guard` 会因 SHA 全变而失效，
  恢复方式是**用 API 合并一次 PR**，不是 force push。
- **`wf3 tokens` 会改 `docs/tokens.html` 与 `metrics/token-usage.tsv`**，提交前 `git checkout --` 还原。
- **绝不手工 `docker run` 跑 bitbake**：必须经 `scripts/container.sh`。理由不是洁癖——
  它除了挂 `/etc/passwd` 还挂 `/etc/group`，手工跑漏掉任何一个，`do_package` 阶段的
  `sstatesig` 就会用 `pwd.getpwuid()` / `grp.getgrgid()` 抛 KeyError，报成
  「owned by uid N, gid N, which doesn't match any user/group」（#109 排查时踩过）。
  同一原因也会让 `package/` 属主变成真实宿主 uid 而 pseudo 库无记录，之后只能
  `rm -rf tmp` 全清重建。

## 五、想了解「为什么这样设计」

- 构建入口与分层：`docs/cli.md`、`docs/container.md`
- 分支与发版：`docs/branching.md`
- CI 门禁：`docs/ci.md`
- 合规与分发义务：`docs/compliance.md`、`THIRD_PARTY_NOTICES.md`
- 历史决策记录：各 issue 正文（尤其 #56、#61、#64、#71 的讨论）
