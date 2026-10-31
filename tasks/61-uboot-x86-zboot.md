# 任务卡：wrynose 6.0 U-Boot 启动链打通到登录（x86 zboot）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `61-uboot-x86-zboot` |
| 里程碑 | `v0.3.0` |
| 分支 | `feat/61-uboot-x86-zboot`（从 `dev` 切出） |
| 关联 Issue | `#61`（并顺带验证 `#63` 的 empty-root-password 修复） |
| 依赖 | 无（u-boot.rom 已能构建并加载，SPL/U-Boot proper 已正常） |
| 预计改动文件 | `layers/meta-yp/recipes-bsp/u-boot/u-boot_2026.01.bbappend`、`layers/meta-yp/recipes-bsp/u-boot/files/qemu-x86-zboot.cfg`（新增） |

## 背景

#61 要把 wrynose 6.0 的启动链切到 U-Boot：QEMU 用 `-bios u-boot.rom` 加载 U-Boot，
内核经 fw_cfg（`-kernel`/`-append`）交给 U-Boot 引导。目前：u-boot.rom 已正确构建（2MB，
binman 产出）、`-bios` 已生效、U-Boot SPL 到 U-Boot proper 都正常，但**卡在最后一步引导内核**。

根因（已定位，证据在 `work/logs/qemu-wrynose-custom.log`）：U-Boot 默认走 standard boot 的
**QFW bootmeth**，其 `qfw_boot()`（`boot/bootmeth_qfw.c`）硬编码先 `booti` 再 `bootz`——
这两个命令是 ARM/RISC-V 专用，x86 上根本不存在，串口报：
`Unknown command 'booti' - try 'help'` / `Unknown command 'bootz' - try 'help'`。
x86 引导 bzImage 必须用 `qfw load` + `zboot` 命令（见 U-Boot 官方文档
`doc/board/emulation/qemu-x86.rst`：先 `qfw load`，再 `zboot`）。

## 要做的事

1. 新建 cfg 片段 `layers/meta-yp/recipes-bsp/u-boot/files/qemu-x86-zboot.cfg`，至少包含：
   - `CONFIG_CMD_ZBOOT=y`（x86 引导 bzImage 的命令；defconfig 可能未默认开启，写死为 y）
   - `CONFIG_CMD_QFW=y`（qemu-x86_64_defconfig 已开，写上无害）
   - 覆盖默认 bootcmd：
     ```
     CONFIG_BOOTCOMMAND="qfw load ${kernel_addr_r} ${ramdisk_addr_r}; zboot ${kernel_addr_r} ${filesize} ${ramdisk_addr_r} 0"
     ```
     说明：
     - `qfw load <kaddr> <iaddr>` 从 fw_cfg 把内核/initrd 载入内存并设好 zboot，同时把
       内核大小写入 `filesize` 环境变量（见 `common/qfw.c` 的 `qemu_fwcfg_setup_kernel`，
       它会 `env_set_hex("filesize", kernel_size)`）。**该命令要求两个地址都传**，缺一个会报
       "missing load or initrd address"。
     - `zboot <kaddr> <ksize> <iaddr> <isize>` 单命令即完成 start 到 go 全流程
       （`cmd/x86/zboot.c` 的 parent 命令在首参为数字时走完整序列）。
     - `${kernel_addr_r}`/`${ramdisk_addr_r}` 是 standard boot 框架默认环境变量，x86 上通常
       为 `0x1000000` / `0x4000000`（之前 bootmeth 日志里内核正是载入 0x1000000）。
       若目标 `.config` 里这俩变量不存在（build 后 `grep -i addr_r build/.../u-boot/*/.config`
       查），自行补 `CONFIG_KERNEL_ADDR_R=0x1000000` / `CONFIG_RAMDISK_ADDR_R=0x4000000`，
       或直接把地址字面写死到 BOOTCOMMAND。
   - 若 merge_config 报 BOOTCOMMAND 与 `CONFIG_BOOTSTD_DEFAULTS` 默认值冲突（warning，非 fatal），
     确认最终 `.config` 里 `CONFIG_BOOTCOMMAND` 是你的字符串即可；必要时追加
     `CONFIG_BOOTSTD_DEFAULTS=n` 让片段稳赢（但不要删掉其它需要的 bootstd 特性）。

2. 在 `layers/meta-yp/recipes-bsp/u-boot/u-boot_2026.01.bbappend` 的 `SRC_URI:prepend` 里，
   与已有 `file://qemu-x86-nographic.cfg` 并列追加一行 `file://qemu-x86-zboot.cfg \`。
   （`FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` 已存在，无需重复。）

3. 重新构建并起机验证（见下验收）。

## 不要做的事

- 不要改 `scripts/qemu.sh` / `scripts/build.sh` / `runqemu`，也不要改镜像磁盘布局
  （`/boot`、extlinux.conf 一律不动——本方案不经磁盘引导）。
- 不要改 `layers/meta-yp/conf/distro/include/yp-uboot.inc` 里已有的
  `UBOOT_MACHINE`(qemu-x86_64_defconfig)、`UBOOT_BINARY`(=u-boot.rom)、`QB_DEFAULT_BIOS`、
  `EXTRA_IMAGEDEPENDS`、multilib provider 修复——这些已经是对的。
- 不要改 `qemu-x86-nographic.cfg`（关 SPL_VIDEO 已生效，正是为了绕过 -nographic 下 SPL 卡死）。
- 不要改门禁（BATS / shellcheck / report 等）；不要为取证方便改交付镜像的 IMAGE_FEATURES
  （full 层 `empty-root-password` 已在位，正是要验的，别动）。
- 不要引入新 layer 或新 recipe；只动这一个 bbappend + 这一个新增 cfg 片段。

## 验收标准

每条都可在容器内直接跑（构建/起机都在 215 容器内，KVM 由脚本自动挂入）：

```bash
# 1) 构建（必须 exit 0，且 u-boot.rom 为本次重新生成）
bash scripts/build.sh --release wrynose --variant custom --uboot
ls -l work/kas-wrynose-custom/build/tmp/deploy/images/qemux86-64/u-boot.rom

# 2) 起机抓串口（240s 超时，headless）
bash scripts/qemu.sh --release wrynose --variant custom --timeout 240
grep -aE 'U-Boot SPL 2026.01'           work/logs/qemu-wrynose-custom.log
grep -aE 'U-Boot 2026.01'               work/logs/qemu-wrynose-custom.log
grep -aE 'Booting Linux|Linux version|Decompressing' work/logs/qemu-wrynose-custom.log
grep -aE 'Reached target'               work/logs/qemu-wrynose-custom.log
grep -aE 'login:'                       work/logs/qemu-wrynose-custom.log

# 3) 空密码 root 登录取证（boot-exec.sh 经串口自动登录 root 后执行命令）
bash scripts/boot-exec.sh --release wrynose --variant custom --timeout 240 --cmd 'systemctl is-active systemd; cat /etc/hostname'
```

- [ ] `build.sh` exit 0，`u-boot.rom` 存在且时间戳为本次构建
- [ ] qemu 日志**同时**出现 `U-Boot SPL 2026.01`、`U-Boot 2026.01`、`Booting Linux`/`Linux version`、
      `Reached target`、`login:`
- [ ] 日志中**不再出现** `Unknown command 'booti'` / `Unknown command 'bootz'` /
      `Failed to set up video` / `Please RESET the board`
- [ ] `boot-exec.sh` 回显证明 root 空密码登录成功（出现命令输出、且无 `Password:` 拒绝 / 无 `Login incorrect`）
- [ ] `git status` 只含本次声明改动：`u-boot_2026.01.bbappend` + 新增 `files/qemu-x86-zboot.cfg`
- [ ] 提交遵循 Conventional Commits；commit 身份为 `zeek.zhao <zeek.zhao@foxmail.com>`
      （仓库 hook 强制，不要带 AI trailer；不要 `--no-verify`）

## 参考

- 现有同类片段：`layers/meta-yp/recipes-bsp/u-boot/files/qemu-x86-nographic.cfg`
- 现有 bbappend：`layers/meta-yp/recipes-bsp/u-boot/u-boot_2026.01.bbappend`
- U-Boot 源码（已解压在 /tmp/uboot-check/u-boot-2026.01）：
  `cmd/x86/zboot.c`（zboot 单命令做完整引导）、`cmd/qfw.c`（qfw load 签名）、
  `common/qfw.c`（`qemu_fwcfg_setup_kernel` 写 filesize）、
  `doc/board/emulation/qemu-x86.rst`（官方 x86 fw_cfg + zboot 引导示例）
- 失败日志：`work/logs/qemu-wrynose-custom.log`（之前 QFW bootmeth 报 Unknown command booti/bootz）

## 分支与提交

- 从 `dev` 切出：`git switch -c feat/61-uboot-x86-zboot dev`
- 在该分支提交，标题示例：`fix(boot): wrynose u-boot 改用 qfw load + zboot 引导 x86 内核（#61）`
