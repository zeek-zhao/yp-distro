# 启动链开关（#61）。默认关：qemu 直接 -kernel 加载 bzImage，
# 这是 v0.3.0 之前所有构建与报告的既有口径，不能因为引入 bootloader 而变。
#
# YP_UBOOT=1 时把 U-Boot 作为 virtual/bootloader 编进镜像。两条链都要能跑，
# 才能量出「bootloader 本身占了多少」—— 只给一条链的数字，对外无法解释
# 「你说 1.8 秒开机，那是内核启动还是设备开机」。
#
# qemux86-64 上 U-Boot 链怎么走（写在这里，避免下一个人按 ARM 的经验踩空）：
#   * x86 的 U-Boot（qemu-x86_64_defconfig）产出 u-boot.rom，由 qemu 的 -bios
#     加载；它不是 ARM 那种「-kernel 加载 u-boot.bin，再打印 Starting kernel」。
#   * 内核怎么交给 U-Boot：走 QFW bootmeth（qemu 的 fw_cfg 接口）。qemu 命令行
#     仍保留 -kernel bzImage -append ...，U-Boot 的 standard boot 自动从 fw_cfg
#     读内核/initrd/cmdline 并引导（booti 先、bootz 回退）。defconfig 已开
#     CONFIG_BOOTSTD_FULL + CONFIG_CMD_QFW，无需改磁盘布局。
#   * 因此这条链不需要 /boot 分区或 extlinux.conf —— 那是「distro-boot 从磁盘
#     找 extlinux」的路径，本项目不采用（qemu 上 QFW 更直接）。
#   * FIT（kernel-fitimage）对 x86 的 bzImage 不适用：FIT 是 ARM/PowerPC 的
#     容器格式，x86 上 U-Boot 直接引导 bzImage。所以本文件不含 FIT 配置。
YP_UBOOT ??= "0"

UBOOT_MACHINE ??= "qemu-x86_64_defconfig"
UBOOT_BINARY ??= "u-boot.rom"
UBOOT_IMAGE ??= "u-boot.rom"
UBOOT_SUFFIX ??= "rom"

# 空字符串 = 不指定 bootloader provider，qemu 仍走 -kernel 直启。
# 注意：qemux86-64.conf 已 `PREFERRED_PROVIDER_virtual/bootloader ?= "u-boot"`，
# 所以这里不必再设 provider —— 关键是下面两点（EXTRA_IMAGEDEPENDS + QB_DEFAULT_BIOS）
# 让 u-boot 真正被编译并被 runqemu 加载。只设 provider 不拉依赖，u-boot 不会编。
PREFERRED_PROVIDER_virtual/bootloader = "${@'u-boot' if d.getVar('YP_UBOOT') == '1' else ''}"

# YP_UBOOT=1 时让镜像依赖 u-boot：ext4.zst 不走 wic，do_image_wic 的 recrdeptask
# do_deploy 不触发，所以必须靠 EXTRA_IMAGEDEPENDS 显式把 u-boot 拉进来编译并
# deploy 到 DEPLOY_DIR_IMAGE（u-boot.rom），否则 virtual/bootloader 只是声明、
# 实际不编 —— 首版就踩了这个空（4003 任务里一个 u-boot 都没有）。
EXTRA_IMAGEDEPENDS += "${@'u-boot' if d.getVar('YP_UBOOT') == '1' else ''}"

# YP_UBOOT=1 时让 runqemu 用 -bios u-boot.rom 启动（而不是裸 -kernel 直启）。
# runqemu 的 check_bios 只认 QB_DEFAULT_BIOS 的 basename，为空/ none 才不加 -bios；
# qemux86-64 默认没有 QB_DEFAULT_BIOS，所以这里空串即维持「无 bios」的现状。
# 注意：-kernel 仍要保留 —— QFW bootmeth 靠 fw_cfg 里的 bzImage 才有内核可加载，
# 去掉 -kernel 会退化成「U-Boot 起来但找不到内核」。
QB_DEFAULT_BIOS = "${@'u-boot.rom' if d.getVar('YP_UBOOT') == '1' else ''}"
