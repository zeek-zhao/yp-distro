# dm-verity 只读根可行性验证（#116，2026-11-03）

> **结论：可行。** wrynose-custom minimal + squashfs 只读根 + dm-verity 在现有
> `-kernel` 直启链上完成受保护起机到 `login:`，且篡改被**逐块精确检出**。
> 本页是 spike 记录；生产化（构建集成、签名、密钥管理）的差距见文末。

## 结论三选一的答案

**可行（含最小起机证据）**——不需要改启动链：内核 cmdline 直接建 dm 表
（`CONFIG_DM_INIT` 的 `dm-mod.create` 路径），无需 initrd、无需 OVMF/UEFI。

## 实验配置

| 项 | 值 |
|---|---|
| 镜像 | wrynose-custom minimal，squashfs（`kas/features/rootfs-squashfs.yml`）|
| 内核 | 6.18 + fragment 增补：`CONFIG_DM_VERITY=y` / `CONFIG_DM_INIT=y`（`BLK_DEV_DM` 本来就是 y）|
| 哈希树 | 宿主容器内 `veritysetup format data.img hash.img`（只算树，不需要内核 dm）|
| 数据 | 8698 块 × 4096B；root hash `5712d3a5…`；salt `d64294ba…` |
| 启动 | `dm-mod.create` 内核 cmdline 建表，`root=/dev/dm-0` |

## 起机证据（boot4）

```
device-mapper: ioctl: dm-0 (verityroot) is ready
device-mapper: verity: sha256 using "sha256-lib"
VFS: Mounted root (squashfs filesystem) on device 253:0
Welcome to YP (Yocto Platform) 0.3.0
yp-qemux86-64 login:
```

## 篡改证据（boot5）

翻转 data.img 偏移 10MB 处 1 个字节后重起：

```
device-mapper: verity: 253:0: data block 2560 is corrupted
```

`10MB / 4096 = 2560`——**逐块精确检出**，校验是真的在跑。

## 三个必须写下来的坑（复现时照抄）

1. **salt 是第 10 个必需参数**：内核 `verity` 表构造器缺 salt 直接
   `Not enough arguments (-EINVAL)`（cryptsetup 用了随机盐，必须原样带进表）。
2. **dm 表长度单位是 512 字节扇区**：长度 = 数据块数 × 8（4096B 块）。
   传块数会报 `len not aligned to h/w logical block size` →
   `Cannot calculate initial queue limits` → dm 设备建不出来。
3. **`hash_start=1` 跳过 cryptsetup superblock**：`veritysetup format` 在哈希
   设备块 0 写 4096B superblock，树从块 1 开始；内核的 `hash_start` 指树的
   起始块，传 0 会把 superblock 当树根读，报 `metadata block 0 is corrupted`。

完整复现命令（三步）在 PR #113 的 commit message 与本页对齐；
测试数据：`work/kas-wrynose-custom/dmv/{data,hash}.img`（可删）。

## 与生产化的差距（vNext，不是本 spike 的范围）

1. **构建集成**：`veritysetup format` 现在是宿主手工步骤。产品化要么收
   `cryptsetup-native`（自建 recipe），要么引入 `meta-security` 的
   `dm-verity-img.bbclass`（官方路线，含 wks 集成）——需要评估该 layer 对
   四版的兼容成本。
2. **保护边界要讲清楚**：root hash 走 cmdline 明文——防的是「盘上篡改 /
   持久化后门」，**不防整镜像替换**（攻击者连 kernel+cmdline 一起换）。
   完整闭环需要签名链：ARM 走 FIT+U-Boot 校验，x86/QEMU 是 UEFI Secure Boot
   （OVMF）或 U-Boot 验证 signed FIT——与现有 QFW 链的关系要先设计再动手。
3. **根分区可写性**：dm-verity 根是只读的；可写目录（/var 等）需 overlay
   到独立分区/tmpfs，#74 的 squashfs 结论（维持 ext4 可写）需要为安全场景
   重新权衡。
