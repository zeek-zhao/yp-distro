# 启动链开关（#61）。默认关：qemu 直接 -kernel 加载 bzImage，
# 这是 v0.3.0 之前所有构建与报告的既有口径，不能因为引入 bootloader 而变。
#
# YP_UBOOT=1 时把 U-Boot 作为 virtual/bootloader 编进镜像。两条链都要能跑，
# 才能量出「bootloader 本身占了多少」—— 只给一条链的数字，对外无法解释
# 「你说 1.8 秒开机，那是内核启动还是设备开机」。
#
# qemux86-64 的现实约束（写在这里，避免下一个人按 ARM 的经验踩空）：
#   * x86 的 U-Boot（qemu-x86_defconfig）产出的是 ROM（u-boot.rom），由 qemu 的
#     -bios 加载，再靠自身的 distro-boot 从磁盘找 extlinux.conf 引导内核；
#     它不是 ARM 那种「-kernel 加载 u-boot.bin，然后打印 Starting kernel」的链路。
#   * 因此这条链要求镜像带 /boot 布局与 extlinux.conf，属于镜像布局改动，
#     不是单纯换个变量。
#   * FIT（kernel-fitimage）对 x86 的 bzImage 不适用：FIT 是 ARM/PowerPC 的
#     容器格式，x86 上 U-Boot 直接引导 bzImage。所以本文件不含 FIT 配置。
YP_UBOOT ??= "0"

UBOOT_MACHINE ??= "qemu-x86_defconfig"
UBOOT_BINARY ??= "u-boot.rom"
UBOOT_IMAGE ??= "u-boot.rom"
UBOOT_SUFFIX ??= "rom"

# 空字符串 = 不指定 bootloader provider，qemu 仍走 -kernel 直启。
PREFERRED_PROVIDER_virtual/bootloader = "${@'u-boot' if d.getVar('YP_UBOOT') == '1' else ''}"
