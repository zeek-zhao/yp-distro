# 交接文档

> 面向「下一个接手的人」——包括三个月后的你自己。只写**现在的事实**和**还没做完的事**，
> 过程记录留在 issue 与 `docs/qa/` 归档里。待办见 [`backlog.md`](backlog.md)；
> AI 协作者另有作业手册 [`ai-handover.md`](../07-ai/ai-handover.md)；踩坑结论的
> **规范条目**（KB-01~32）统一在 [`knowledge-base.md`](knowledge-base.md)。
>
> 最后更新：2026-11-14

## 一、这个仓库现在是什么状态

| 维度 | 现状 |
|---|---|
| 仓库 | `zeek-zhao/yp-distro`，公开，MIT，默认分支 `main`（**只有 `main` 一条长期分支**） |
| 版本 | `v1.0.0` 已发布（2026-11-05，`1e1ff48`）。批次 tag `v1.0.1`（修正，`bf748c1`）与 `v1.0.2`（验证，`2157a6c`）已发布（2026-11-14）。在途容器仍是里程碑 **`v1.0.1 · 6.0 全面收口`**（关闭条件 = 26 条功能各达证据档位 + DoD 五条，判定表只在 [`plan/milestones.md`](plan/milestones.md)），余下 #135 文档同步 + C 功能 `v1.1.0`（#133） |
| 保障范围 | **只有 wrynose 6.0**（2026-11-09 决策）。dunfell 3.1 / kirkstone 4.0 / scarthgap 5.0 **冻结保留**：配置与配方留仓、退出 CI 与回归、标 untested。理由见 `engineering-overview.md` §2.2 |
| 验证环境 | **QEMU + x86-64**。不用实体硬件（从未上板）、不覆盖 arm64。两者是主动声明，不是缺陷 |
| 门禁 | `ci.yml` 五个 job：lint / bats / secret-scan / identity-guard / plan-sync；bats **210 项**（JUnit 口径，0 失败 0 skip）。`bats-release-matrix` 已删（#128），branch-guard 仅 push main（ruleset 的备份门禁） |
| 回归 | `scripts/release-check.sh` 一条命令跑受保障组合（build→qemu→report→guard）；组合清单由 `config/supported-releases.txt` 驱动，现仅 wrynose × custom/general 两组合同源指纹归档 |
| 安全 | dm-verity 只读根**路线二已完成**（`b1dc237`，篡改检出 + revert 验证）；`/var` 可写方案待做（#133）。路线一（5.0 + UEFI）已砍 |

## 二、已经验证过的能力与结论（别重复验证）

这些是花过真机成本换来的，重跑一遍只是烧时间：

- **L3 真构建通**：9 配方 2184 tasks；full 镜像 4367/2944/4382 tasks（各版本）
- **回归 202/202/0/0**（v1.0.0 期口径），串口全命中 `login:`；入库归档仅
  wrynose 两份 `docs/qa/wrynose/20261104-ad7c52d*.md`（general/custom），其余组合
  当日报告未归档入库（远端留存与否未确认）
- **启动优化（#72–#75）三版移植**：唯一有启动收益的是裁调试设施（kernel_ms -6~-9% 三版一致）；
  ZSTD 定稿（bzImage -37.5%）；rootfs 换格式启动无收益（维持 ext4）；服务并行已由 systemd 实现
  （均摊 134ms/unit）。数据：`docs/qa/boot-baseline.md` §6–§10 + `docs/02-development/boot-optimization.md`
- **systemd 剖析**：userspace 瓶颈是 udev 冷插队列排空（~8s@6.0），非服务；mask
  `serial-getty@ttyS1`（null 口）已三版落地
- **5.0 U-Boot 链**：U-Boot 2024.01 无 `BOOTMETH_QFW`（2024.07+ 才有）→ 按预设降级，
  `degraded.txt` 已登记，5.0 bootloader 段 n/a
- **dm-verity 可行**（#116）：squashfs 只读根 + `dm-mod.create` cmdline 起机到 login；
  篡改逐块检出。三个坑（salt 必需 / dm 表长度是 512 扇区 / hash_start=1 跳 superblock）
  见 `docs/qa/security/dm-verity-feasibility.md`

### 语法与移植结论（被推翻过一次，别按老笔记改）

- **变量级** override：3.1 只认 `_append`，4.0+ 只认 `:append`。下划线版在 4.0+ 是
  **致命**解析错误。变量层用 `python __anonymous` 按 `LAYERSERIES_CORENAMES` 补。
- **任务级** override：`do_install:append()` **3.1 也认**，四版统一只留冒号一份。
- **KERNEL_FEATURES 的 scc 在 SRC_URI fragment 之后合并**：裁内核选项必须同步摘对应
  scc（debug-kernel/nfsd-enable/sound），否则被重新打开（#72 首版白测的原因）。
- **kas 的 local.conf 先于 distro conf 解析**：`IMAGE_FSTYPES` 类的覆盖要用
  `:remove` 收口（finalize 阶段晚于一切 append）。
- **bzImage 的 lz4/zstd 压缩用宿主命令**：缺 `lz4-native`/`zstd-native` 报 not found。
- **commit 后跑的构建必然指纹过时**：`deploy-guard` 报 stale 是正确行为；
  重跑 `build.sh`/`release-check.sh` 即刷新。

## 三、排查方法论（先做哪步，别猜）

1. **do_rootfs 目录属性冲突** → 先查 rpm 元数据（docker + rpm -qp 比对
   `(mode,owner,group)`），再怀疑配方；内容级污染只能 `cleansstate` 清。
2. **起不来** → 先看串口日志是不是目标镜像（runqemu 按 `qb_default_fstype`/
   `qb_default_bios` 解析，experiment overlay 会残留），再 `deploy-guard` 查新鲜度。
3. **boot-time 拿不到 json** → 内层 exit 3 = 没起机；其他 rc = 测量链 bug，看
   `boot-time.sh` 失败分支的 rc 区分。
4. **sstate 恢复旧内容** → 强制重跑任务会被同 PN 旧哈希归档复活污染，
   `cleansstate <pn>` 是唯一可靠清除。

## 四、还没做完的事

见 [`docs/06-process/backlog.md`](backlog.md)（按里程碑批次整理的待办）与
[`docs/06-process/plan/milestones.md`](plan/milestones.md)（出口条件）。要点：

- **里程碑 `v1.0.1 · 6.0 全面收口` 是唯一容器**，关闭条件 = 26 条功能各达证据档位
  + DoD 五条。条件 A/B 判定与当前计数只在 [`plan/milestones.md`](plan/milestones.md)
  维护（真源 `config/features.txt` + `config/degraded.txt`），此处不重复写数。
- **P0 已清零**：#130/#127/#128/#129 + #132/#131/#134 随 #138（batch1）于
  2026-11-12 合并关闭。
- **#135** 全工程文档同步进行中（2026-11-14 起，`feat/p0-review-fixes` 承接其
  文档同步批次）。
- **#133** 只读根 `/var` overlay 是唯一真功能缺口，属 `v1.1.0`。
- **#107** GitHub Support 工单（人工，外部阻塞，不阻塞完成判定）。
- **例行**：wrynose 点版本跟进（下一窗口 2026-12-07）。**5.0 已退出保障，不再跟。**

## 五、纪律（违反会留下永久痕迹）

- **提交身份**：author + committer 统一 `zeek-zhao <42319166+zeek-zhao@users.noreply.github.com>`（2026-11-12
  起仓库 local config 已切换；`identity-guard` 放行该格式）。
  企业身份 `zeek.zhao <zeek.zhao@foxmail.com>` 只存在于 2026-11-01 重写点之前的历史
  提交、三个旧 tag 的 Tagger 与部分 squash message 的 `Signed-off-by`，完整公开
  残留盘点记 #107，不再用于新提交。
  **已知例外（显式豁免，不是漏网）**：网页上直接 Merge 会产生 GitHub 合成 committer
  （`noreply@github.com`），现存 **13 条** squash 提交以 GitHub 身份落地。
  不重写历史的原因：第三次重写会再次重置全部 SHA，并再毁一次 `refs/pull` 引用
  （#107 已经够痛），而 noreply 身份不泄露真实信息。
- **禁 AI 署名**：`Co-authored-by: <工具>`、`Generated with ...`、`🤖` 一律拒。
  三层门禁：本地 `.githooks/commit-msg`、CI `identity-guard`、GitHub ruleset。
- **改历史前先备份**：`git bundle create --all`。改完 `branch-guard` 会因 SHA 全变
  失效，恢复方式是**用 API 合并一次 PR**，不是 force push。
- **绝不手工 `docker run` 跑 bitbake**：必须经 `scripts/container.sh`（passwd/group
  挂载缺一个就 sstatesig KeyError，#109 踩过）。
- **回归前工作区必须干净**：脏树让 `SOURCE_FINGERPRINT` 不可复现。

## 六、想了解「为什么这样设计」

- 构建入口与分层：`docs/03-build/cli.md`、`docs/03-build/container.md`
- 分支与发版：`docs/06-process/branching.md`；点版本跟进：`docs/05-release/point-releases.md`
- CI 门禁：`docs/06-process/ci.md`；合规与分发义务：`docs/05-release/compliance.md`、`THIRD_PARTY_NOTICES.md`
- 启动优化全记录：`docs/02-development/boot-optimization.md` + `docs/qa/boot-baseline.md`
- 历史决策记录：各 issue 正文（尤其 #56、#61、#64、#71、#72、#109、#114）
