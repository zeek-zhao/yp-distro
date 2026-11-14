> **历史记录（#135，2026-11-12）**：本文是 #116 后续的生产化评估快照（只评估，
> 未引入任何新 layer 或 recipe）。现行保障范围只有 wrynose 6.0
> （`config/supported-releases.txt`），涉及其他版本的路线比较按历史记录看待。
> 正文一字未动。

# dm-verity 生产化评估（#116 后续，2026-11-04）

> spike（`dm-verity-feasibility.md`）证明可行后，本文评估「从手工步骤到构建
> 集成」的两条路线。**本文只是评估，未引入任何新 layer 或 recipe。**

## 事实基础（全部经远程核实，2026-11-04）

| 项 | 状态 |
|---|---|
| `cryptsetup`（含 `veritysetup`）配方 | 在 **meta-oe**（`meta-oe/recipes-crypto/cryptsetup`），oe-core/meta-security 均不带 |
| meta-security `scarthgap` 分支 | 存在，`LAYERSERIES_COMPAT = "nanbield scarthgap"`，`dm-verity-img.bbclass` 在位 |
| meta-security 对 6.0 系列 | **无 wrynose 分支**；master 的 compat 已指向下一系列 "blacksail"——6.0 只能等上游分支或自改 compat 声明 |
| `dm-verity-img.bbclass` 的运行时模型 | 构建：hash 追加到镜像 + 生成含 root hash 的 `.env`；运行：**initramfs 里跑 veritysetup** 挂根（与我们 spike 的 initramfs-free `dm-mod.create` 是两条不同路线）|
| 本项目 spike 路线 | 无 initramfs、内核 cmdline `dm-mod.create` 建表——已验证，但 root hash 的注入目前是手工步骤 |

## 路线对比

### 路线 1：meta-security + meta-oe（官方集成）

- 优点：镜像构建期自动生成哈希树与 `.env`；wic/GPT discoverable partition
  GUID 集成成熟；initramfs 挂根方案顺带解决只读根的 `/var` 可写问题
  （overlay 在 initramfs 配置）
- 成本：引入 **两个新 layer**（meta-security + meta-oe，后者体量大）；
  5.0 可直接走 scarthgap 分支，**6.0 被上游分支缺口阻塞**（bbappend 改
  `LAYERSERIES_COMPAT_security` 可绕，但要自担兼容验证）；启动链多出
  initramfs——三段启动测量口径要重新定义（#85 基线不可比）
- 估算：5.0 上 1–2 人日集成 + 回归；6.0 视上游

### 路线 2：meta-yp 自持最小集成（spike 路线产品化）

- 优点：不引新 layer；启动链与三段测量口径**不变**（无 initramfs，cmdline
  建表）；把 spike 的三步手工活变成一个 `do_image[postprocess]` 任务：
  veritysetup format → hash 追加/独立 hash 镜像 → root hash 写进
  `qemuboot.conf` 的 `QB_KERNEL_CMDLINE_APPEND`
- 成本：需要 `veritysetup` 的 **native** 配方——cryptsetup 做
  `BBCLASSEXTEND = "native"` 的构建依赖链（libdevmapper/lvm2 native、
  popt、openssl native）要自己背；cryptsetup 配方本体从 meta-oe 拷入
  meta-yp 后，**安全工具的版本跟踪义务落在我们自己头上**（讽刺但必须写明）
- 估算：2–3 人日（native 依赖链是主要风险）

## 决策（2026-11-05，v1.0.0 发布时定）

**路线一 + 路线二综合使用**（issue #117 跟踪实施）：

- **路线一**用于 5.0：分支/class 齐备，走官方 initramfs 集成，长期维护成本低
- **路线二**用于 6.0：上游 meta-security 尚无 6.0 分支，wrynose 先以已验证的
  `dm-mod.create`（无 initramfs）路线落地，保持启动测量口径不变，并作为 5.0
  的对照实现
- 共享件：内核 fragment（DM_VERITY/DM_INIT 三版通用）与篡改检测测试口径

## 建议（原评估保留）

1. **5.0 先走路线 1**：分支与 class 都在位，官方路线长期维护成本低；
   接受 initramfs 改动（单独开 issue，并把启动测量口径的变化写进
   boot-baseline）。
2. **6.0 观望上游**：meta-security 出 6.0 分支后再平移；在此之前 wrynose
   保留 spike 记录（可行性已证），不开生产化。
3. **路线 2 仅作 fallback**：只有当「必须无 initramfs」成为硬需求
   （比如要保持启动测量口径稳定）时才走，native 依赖链先做 1 人日
   摸底再决定。
4. 无论哪条路线，**只读根的 /var overlay 与签名链**（cmdline 明文 root hash
   的保护边界）都是前置设计项——见 `docs/06-process/backlog.md` P2。
