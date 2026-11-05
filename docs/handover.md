# 交接文档

> 面向「下一个接手的人」——包括三个月后的你自己。只写**现在的事实**和**还没做完的事**，
> 过程记录留在 issue 与 `docs/qa/` 归档里。待办见 [`backlog.md`](backlog.md)；
> AI 协作者另有作业手册 [`ai-handover.md`](ai-handover.md)；踩坑结论的
> **规范条目**（KB-01~32）统一在 [`knowledge-base.md`](knowledge-base.md)。
>
> 最后更新：2026-11-04

## 一、这个仓库现在是什么状态

| 维度 | 现状 |
|---|---|
| 仓库 | `zeek-zhao/yp-distro`，公开，MIT，默认分支 `main`（**只有 `main` 一条长期分支**） |
| 版本 | `v0.4.0` 已发布；**PR #113 待合并**——v0.5.0/v0.6.0/v0.7.0 出口条件与 v1.0.0 回归归档全部在内（含 6.0 优化移植到 5.0/4.0）。合并即关 14 个 issue |
| 支持 4 版 | dunfell 3.1（EOL，冻结：能编不跑）/ kirkstone 4.0（EOL，能编 + 内核优化已移植）/ **scarthgap 5.0 LTS**（官方支持至 2028-04，全能力）/ **wrynose 6.0 LTS**（官方支持约 4 年，全能力、参考实现）|
| 门禁 | bats 206 项（0 失败 0 skip）+ 四版 release-matrix + secret/identity/plan-sync/lint，CI 全绿 |
| 回归 | `scripts/release-check.sh` 一条命令跑全量回归（build→qemu→report→guard），8 组合同源指纹归档 |
| 安全 | dm-verity 只读根可行性已验证（CRA secure defaults 第一步，`docs/qa/security/`） |

## 二、已经验证过的能力与结论（别重复验证）

这些是花过真机成本换来的，重跑一遍只是烧时间：

- **L3 真构建通**：9 配方 2184 tasks；full 镜像 4367/2944/4382 tasks（各版本）
- **八组合回归 8/8**：`docs/qa/*/20261104-ad7c52d*.md`，每份 202/202/0/0，串口全命中 `login:`
- **启动优化（#72–#75）三版移植**：唯一有启动收益的是裁调试设施（kernel_ms -6~-9% 三版一致）；
  ZSTD 定稿（bzImage -37.5%）；rootfs 换格式启动无收益（维持 ext4）；服务并行已由 systemd 实现
  （均摊 134ms/unit）。数据：`docs/qa/boot-baseline.md` §6–§10 + `docs/boot-optimization.md`
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

见 [`docs/backlog.md`](backlog.md)（带优先级的待办清单）。要点：
PR #113 合并 + 发版（人工）、#107 工单（人工）、#116 dm-verity 生产化评估、
LTS 点版本跟进（下一窗口 2026-12-07）。

## 五、纪律（违反会留下永久痕迹）

- **提交身份**：author + committer 都必须是 `zeek.zhao <zeek.zhao@foxmail.com>`，
  带 DCO `Signed-off-by`。
- **禁 AI 署名**：`Co-authored-by: <工具>`、`Generated with ...`、`🤖` 一律拒。
  三层门禁：本地 `.githooks/commit-msg`、CI `identity-guard`、GitHub ruleset。
- **改历史前先备份**：`git bundle create --all`。改完 `branch-guard` 会因 SHA 全变
  失效，恢复方式是**用 API 合并一次 PR**，不是 force push。
- **绝不手工 `docker run` 跑 bitbake**：必须经 `scripts/container.sh`（passwd/group
  挂载缺一个就 sstatesig KeyError，#109 踩过）。
- **回归前工作区必须干净**：脏树让 `SOURCE_FINGERPRINT` 不可复现。

## 六、想了解「为什么这样设计」

- 构建入口与分层：`docs/cli.md`、`docs/container.md`
- 分支与发版：`docs/branching.md`；点版本跟进：`docs/point-releases.md`
- CI 门禁：`docs/ci.md`；合规与分发义务：`docs/compliance.md`、`THIRD_PARTY_NOTICES.md`
- 启动优化全记录：`docs/boot-optimization.md` + `docs/qa/boot-baseline.md`
- 历史决策记录：各 issue 正文（尤其 #56、#61、#64、#71、#72、#109、#114）
