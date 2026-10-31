# 启动链：`-kernel` 与 U-Boot

v0.3.0 的出口条件之一是「U-Boot 链与 `-kernel` 链都能到 login」。这份文档说清两条链
的差别、怎么切、以及在 qemux86-64 上为什么 U-Boot 链不是「改个变量」那么简单。

## 两条链

| | `-kernel` 直启（默认） | U-Boot 链（`YP_UBOOT=1`） |
|---|---|---|
| 谁加载内核 | qemu 的 `-kernel` 参数直接交给 CPU | U-Boot 经 QFW（fw_cfg）读 `-kernel` 的内核再引导 |
| 有没有 bootloader 段 | 没有，墙钟从内核第一条 printk 算起 | 有，从上电到 `Starting kernel` 都是 U-Boot 的时间 |
| 产物 | `bzImage` + rootfs | `u-boot.rom`（`-bios` 加载）+ 同样的 `bzImage`/rootfs |
| 用在哪 | 日常构建、报告基线、启动优化 | 只用于量「bootloader 引入多少开销」 |

**为什么必须两条都留**：只有 U-Boot 链，历史数据全部不可比（v0.3.0 之前的基线都是
`-kernel` 口径）；只有 `-kernel` 链，启动时间对外无法解释——真机从上电到内核接管之间
那 1~3 秒不在任何指标里。

## 怎么切

```bash
# 默认：-kernel 直启，行为与 v0.2.0 完全一致
bash scripts/build.sh --release wrynose --variant custom

# U-Boot 链：多一层 kas overlay，只改 YP_UBOOT，不动 8 份 target
bash scripts/build.sh --release wrynose --variant custom --uboot
```

开关的落点是 `layers/meta-yp/conf/distro/include/yp-uboot.inc`，由 `yp.conf` include。
`YP_UBOOT=0` 时 `PREFERRED_PROVIDER_virtual/bootloader` 是空串，等于没有 bootloader，
与改动前完全一致。

## qemux86-64 上的现实约束

写这一节是因为按 ARM 的经验会直接踩空：

1. **x86 的 U-Boot 是 ROM，不是 `u-boot.bin`**。`qemu-x86_64_defconfig` 产出
   `u-boot.rom`，由 qemu 的 `-bios` 加载；而 ARM 是 `-kernel u-boot.bin` 之后
   U-Boot 再 `bootm` 加载内核。两者在串口日志上的形态完全不同。
2. **内核经 QFW（fw_cfg）交给 U-Boot，不改磁盘布局**。qemu 命令行仍保留
   `-kernel bzImage -append ...`，U-Boot 的 standard boot 用 QFW bootmeth 自动从
   fw_cfg 读内核/initrd/cmdline 并引导（`booti` 先、`bootz` 回退）。defconfig 已开
   `CONFIG_BOOTSTD_FULL` + `CONFIG_CMD_QFW`。**不需要** `/boot` 分区或
   `extlinux.conf`——那是「distro-boot 从磁盘找 extlinux」的另一条路径，本项目不用。
3. **FIT 对 x86 不适用**。`kernel-fitimage` 产出的是 ARM/PowerPC 的容器格式，
   x86 的 bzImage 不在里面打包。所以 `yp-uboot.inc` 只设 `UBOOT_*`，不含 FIT。
   想要 FIT，得在 `qemuarm64` 上做——那是另一条独立的验证路径。

## 验收（U-Boot 链）

```bash
# 串口日志里必须能按顺序看到三段
grep -E 'U-Boot 20|Starting kernel|login:' work/logs/serial-uboot-*.log

# -kernel 链不能被弄坏
bash scripts/build.sh --release wrynose --variant custom   # 不带 --uboot
```

## 当前状态

见 GitHub #61 与 `docs/qa/` 下的记录。这里只写链路定义与切换方式，
不写「已验证通过」之类会过期的结论。
