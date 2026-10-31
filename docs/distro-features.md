# YP distro features

`DISTRO_FEATURES` inherits the Poky baseline. The measured wrynose value before
this change was:

```text
systemd usrmerge acl alsa debuginfod bluetooth ext2 ipv4 ipv6 wifi xattr nfs
zeroconf pci 3g nfc x11 vfat seccomp pulseaudio
gobject-introspection-data ldconfig opengl ptest multiarch wayland vulkan
```

`yp-common.inc` removes only the seven audited features below. The modern
`:remove` operation handles kirkstone and later. Dunfell's `_remove` operation
is set dynamically only when `LAYERSERIES_CORENAMES` is `dunfell`: BitBake 6.x
rejects even an inactive legacy `_remove` assignment during parsing. This
leaves the Poky and machine feature baselines intact.

| feature | 决定（留/删/待定） | 理由 |
|---|---|---|
| `x11` | 删 | 关闭 X11 相关启用路径，可避免 libX11/libxcb、xauth 及 X server 相关脚本进入无图形需求的 QEMU 镜像。 |
| `wayland` | 删 | 关闭 Wayland client/compositor 依赖及 wayland-tools、Weston 等相关构建选项；QEMU 镜像不运行图形桌面。 |
| `opengl` | 删 | 关闭 OpenGL/EGL/GLES 相关构建选项，避免 Mesa/libglvnd 图形栈及其驱动依赖。 |
| `3g` | 删 | 阻止 `packagegroup-base-3g` 被选入；它引入 oFono 和 CDC ACM/WDM 蜂窝调制解调器内核模块。 |
| `bluetooth` | 删 | 阻止 `packagegroup-base-bluetooth` 被选入；它引入 bluez5 及 Bluetooth、L2CAP、RFCOMM 等内核模块推荐项。 |
| `nfs` | 删 | 阻止 NFS 支持包组引入 rpcbind 和 NFS 内核模块，避免镜像携带网络文件系统客户端支持。 |
| `zeroconf` | 删 | 阻止 `packagegroup-base-zeroconf` 引入 avahi-daemon 与 libnss-mdns，减少 mDNS/本地服务发现运行时。 |
| `systemd` | 留 | 本卡将 `INIT_MANAGER` 设为 systemd；该 feature 同时启用 systemd 配方和集成所需配置。 |
| `sysvinit` | 删（不回填） | systemd include 将 sysvinit 加入 `DISTRO_FEATURES_BACKFILL_CONSIDERED`（3.1–5.0）；6.0 已删除该变量且其基线本身不含 sysvinit。 |
| `ipv4` | 留 | 保持 IPv4 网络栈和 BusyBox IPv4 ifupdown 配置可用。 |
| `ipv6` | 留 | BusyBox 会据此启用 IPv6/IPv6 ifupdown，网络工具与 network 脚本会走 IPv6 分支。 |
| `pci` | 留 | 保留 QEMU 虚拟设备的 PCI 总线支持及其 feature-gated 工具配置。 |
| `usbhost` | 留（未出现在本次 DISTRO_FEATURES dump） | 不在删除列表中；该 feature 由 machine 能力决定，本卡不重写 machine 配置或 feature 基线。 |
| `rtc` | 留（未出现在本次 DISTRO_FEATURES dump） | 不在删除列表中；本卡不更改 RTC 相关 machine 配置或 feature 基线。 |
| `ext2` | 留 | 保留 ext2 镜像/文件系统支持；oe-core 的基础包组可据此选择 e2fsprogs 检查和格式化工具。 |
| `ldconfig` | 留 | glibc 按此 feature 推荐 `ldconfig` 包，rootfs 处理也依赖 `ld.so.conf`；不能随意裁掉。 |
| `acl` | 留 | 保留 POSIX ACL 支持，避免文件权限能力随镜像基线变化。 |
| `alsa` | 留 | 保留 ALSA 音频接口及设备支持；本卡不扩大已审计的删除范围。 |
| `debuginfod` | 留 | 保留 debuginfod 调试信息服务支持；本卡不改变调试能力基线。 |
| `wifi` | 留 | 保留无线网络 feature-gated 支持；本卡不裁剪 Wi-Fi 网络能力。 |
| `xattr` | 留 | 保留扩展文件属性支持，维持文件系统与包行为基线。 |
| `nfc` | 留 | 保留 NFC feature-gated 支持；它未纳入本次明确审计的七项删除范围。 |
| `vfat` | 留 | 保留 FAT 文件系统支持，适用于启动介质及可移动介质场景。 |
| `seccomp` | 留 | 保留 seccomp 沙箱能力，避免降低进程隔离能力。 |
| `pulseaudio` | 留 | 保留 PulseAudio feature 配置；本卡只删明确定义的图形和外设特性。 |
| `gobject-introspection-data` | 留 | 保留 GObject Introspection 元数据生成，避免影响基于 introspection 的语言绑定。 |
| `ptest` | 留 | 保留配方测试包支持，维持现有测试能力。 |
| `multiarch` | 留 | 保留多架构包支持，维持 oe-core 的架构兼容配置。 |
| `vulkan` | 留 | 保留 Vulkan feature 配置；图形 API 裁剪范围本卡限定为 `opengl`。 |
| `usrmerge` | 依版本保留 | 5.0/6.0 的上游 systemd include 会加入它；3.1/4.0 不会加入。本卡不强行为旧版启用 usrmerge。 |

## 四版 systemd include 差异

以下差异来自各 release 的 `init-manager-systemd.inc`。本层只在
`yp.conf` 的 `require conf/distro/poky.conf` 之前选择
`INIT_MANAGER = "systemd"`，不复制或统一上游的版本实现。

| 版本 | append 语法 | 加入 `usrmerge` | `BACKFILL_CONSIDERED` | `initscripts` | `dev_manager` | `ROOT_HOME` |
|---|---|---|---|---|---|---|
| 3.1 dunfell | `_append` | 否 | `_append = " sysvinit"` | `systemd-compat-units` | 未设置 | 未设置 |
| 4.0 kirkstone | `:append` | 否 | `:append = " sysvinit"` | `systemd-compat-units` | `systemd` | 未设置 |
| 5.0 scarthgap | `:append` | 是 | `:append = " sysvinit"` | `systemd-compat-units` | `systemd` | `/root` |
| 6.0 wrynose | `:append` | 是 | 已删除该行 | 空串 `""` | `systemd` | `/root` |

3.1 未强制启用 `usrmerge`：该版需要额外的 `CONVERSION_CMD` 和 QA 调整，
而这一差异只影响 `/bin` 等目录的实体/软链布局。3.1 的
`VIRTUAL-RUNTIME_dev_manager` 也不预先补值；`systemd-udevd` 是否运行须待
L3 起机后检查。

## 验证记录

实测（2026-10-31，容器内真跑 `bitbake -e yp-image`，非 `-n`、非 dry-run）：

| 版本 | LAYERSERIES_CORENAMES | INIT_MANAGER | VIRTUAL-RUNTIME_init_manager | 残留项 | DISTRO_FEATURES 条目 |
|---|---|---|---|---|---|
| 3.1 dunfell | dunfell | systemd | systemd | 无 | 23 |
| 4.0 kirkstone | kirkstone | systemd | systemd | 无 | 25 |
| 5.0 scarthgap | scarthgap | systemd | systemd | 无 | 23 |
| 6.0 wrynose | wrynose | systemd | systemd | 无 | 22 |

「残留项」= 最终 `DISTRO_FEATURES` 里仍能找到 `x11` / `wayland` / `opengl` / `3g` /
`bluetooth` / `nfs` / `zeroconf` / `sysvinit` 中的任一个。

BATS：`12_distro.bats` 3 条 + `04_layer.bats` 12 条，15/15 通过。

### 两个工具链前提（缺一个都测不出来）

1. **dev 镜像必须含 poky 的 HOSTTOOLS 最小集**：
   `chrpath cpio diffstat gawk zstd lz4 pzstd unzstd`。
   否则 `bitbake -e` 在 sanity 的 HOSTTOOLS 检查处直接退出，连解析都到不了。
   注意各版列表不同 —— kirkstone / scarthgap 还要 `lz4c`，wrynose 不要。
2. **3.1 必须用它自己的构建镜像**：dev 镜像是 Ubuntu 24.04 + Python 3.12，
   dunfell 的 bitbake 1.46 会卡在 `import pyinotify`（依赖 Python 3.12 已移除的
   `asyncore`）。3.1 的解析验证只能走 `ghcr.io/zeek-zhao/yocto/dunfell:local`（Python 3.8）。

### 一个语法陷阱（本卡最贵的一课）

`DISTRO_FEATURES:remove` 与 `DISTRO_FEATURES_remove` **不能写在同一个文件里**。
在 4.0+ 上，`DISTRO_FEATURES_remove`（下划线）不是「无害的冗余」，
而是致命解析错误：

```
ERROR: Variable DISTRO_FEATURES_remove ... contains an operation using the old
override syntax. Please convert this layer/metadata before attempting to use
with a newer bitbake.
ERROR: Unable to parse .../bitbake/lib/bb/__init__.py
```

「两种分隔符各写一行」这个直觉在 3.1 上下文里成立（`:` 在 3.1 静默失效），
反方向不成立（`_` 在 4.0+ 硬失败）。所以只能：**4.0+ 用字面 `:remove`，
3.1 用运行时 `d.setVar("DISTRO_FEATURES_remove", ...)` 且用
`LAYERSERIES_CORENAMES` 守卫**。运行时赋值绕过了「字面语法检查」，
这是唯一能在单文件里同时满足四版的办法。

### L3 实测（2026-10-31）

四版真构建 + 真起机，完整命令与原始输出见 `docs/qa/l3-systemd-boot.md`。

| release | PID 1 | `Reached target` | FAILED | `systemd-udevd` |
|---|---|---|---|---|
| 3.1 dunfell | systemd 244.5+ | 20 | 0 | PID 112 |
| 4.0 kirkstone | systemd 250.14+ | 22 | 0 | PID 177 |
| 5.0 scarthgap | systemd 255.21 | 21 | 0 | PID 161 |
| 6.0 wrynose | systemd 259.5 | 21 | 0 | 串口登录受限，见下 |

**3.1 缺 `VIRTUAL-RUNTIME_dev_manager` 不影响 udev。** 3.1 的
`init-manager-systemd.inc` 确实没设这一项，但 `systemd` 配方自身
`RRECOMMENDS` 了 `udev`，镜像里 `systemd-udevd` 正常起在 PID 112，`udevadm`
也在位。**不要为 3.1 补这一项** —— 补了就是与 poky 默认值分叉，而实测没有收益。

**wrynose 拿不到 `ps` 输出。** 6.0 把 `debug-tweaks` 拆成
`allow-empty-password allow-root-login post-install-logging`，但 `serial-getty`
仍然弹 `Password:`，空密码被拒（`Login timed out`）。改用两条等价证据：
启动日志里 udev 的 Control/Kernel/Varlink socket 均已监听且规则已装载，
镜像里含 435 个 systemd 单元/相关文件、`systemd-udevd` 与 `udevadm` 二进制在位。
**不为了取证方便去改交付镜像的 `IMAGE_FEATURES`。**

**裁掉七项后镜像仍可起机。** 四版镜像里
`libX11|libxcb|libwayland|libGL\.|bluez|avahi|libnfs` 残留均为 0，
且四版都起到 `login:`。
