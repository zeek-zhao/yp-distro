# L3 起机实测：四版切 systemd + 裁剪 DISTRO_FEATURES

日期：2026-10-31
分支：`feat/56-systemd`（HEAD `6f396e8`）
执行：宿主构建机手动触发，容器内 TCG 起机（`qemux86-64` / `custom` variant）

## 为什么需要这一份

`#56` 的解析级验收（`bitbake -e` + BATS + L1）只能证明「配置读起来是 systemd」。
`INIT_MANAGER` 的失效模式恰恰是**不报错但镜像仍跑 busybox**，所以本卡必须有真构建 +
真起机的现场证据。本文件记录这一轮的原始输出。

## 方法

```bash
# 1) 真构建（release 镜像，非 dev）
bash scripts/build.sh --release <release> --variant custom

# 2) 起机 + 客户机取证：串口自动登录 root，然后执行命令
bash scripts/boot-exec.sh --release <release> --cmd 'ps -eo pid,ppid,args --width 300'

# 3) 解析级：DISTRO_FEATURES 终值
./project.sh shell --release <release> --variant custom -- bash -lc \
  'set +u; source /work/work/kas-<release>-custom/<oec>/oe-init-build-env \
   /work/work/kas-<release>-custom/build >/dev/null; cd /work/work/kas-<release>-custom/build; \
   bitbake -e yp-image | grep "^DISTRO_FEATURES="'

# 4) 镜像内容：裁剪项是否真的没进镜像
tar -tjf work/kas-<release>-custom/build/tmp/deploy/images/qemux86-64/yp-image-qemux86-64*.rootfs.tar.*
```

本卡的取证工具已入库：`scripts/boot-exec.sh`（宿主入口）+ `scripts/lib/inner-boot-exec.sh`
（容器内串口注入）。`scripts/qemu.sh` 只抓启动日志、拿不到 `ps`，两者分工不重叠。
客户机命令先落盘到 `work/logs/guest-cmd-<release>.txt` 再由容器内脚本读取，
所以带管道/引号的命令不会被多层 shell 解析坏。

## 结果

| release | 构建 | PID 1 | systemd | `Reached target` | FAILED | `systemd-udevd` |
|---|---|---|---|---|---|---|
| 3.1 dunfell | exit 0（3683 任务，2782 命中 sstate） | `/sbin/init` | 244.5+ | 20 | 0 | PID 112 |
| 4.0 kirkstone | exit 0（3218 任务，3050 命中 sstate） | `/sbin/init` | 250.14+ | 22 | 0 | PID 177 |
| 5.0 scarthgap | exit 0（4528 任务，4308 命中 sstate） | `/sbin/init` | 255.21 | 21 | 0 | PID 161 |
| 6.0 wrynose | exit 0（4888 任务，4615 命中 sstate） | systemd[1] | 259.5 | 21 | 0 | 见下 |

四版全部起到 `login:`，`FAILED` 均为 0。

### 关于 PID 1 显示成 `/sbin/init`

systemd 自己的 argv 就是 `/sbin/init`，所以 `ps` 里看到的名字不能当判据。真正的判据是
PID 1 的内核日志：

```text
[    4.160411] systemd[1]: systemd 244.5+ running in system mode. (-PAM -AUDIT ... +SYSVINIT ...)
[    3.779263] systemd[1]: systemd 250.14+ running in system mode (... +SYSVINIT ...)
[    1.687693] systemd[1]: systemd 255.21^ running in system mode (... +SYSVINIT ...)
[    2.928495] systemd[1]: systemd 259.5 running in system mode (... -SYSVINIT ...)
```

`+SYSVINIT` 是 systemd 编进了 sysvinit 兼容层（接管老式 init 脚本），**不等于** init 是
sysvinit；`DISTRO_FEATURES` 里已无 `sysvinit`，6.0 连兼容层都关掉了（`-SYSVINIT`）。

### 关于 wrynose 的 `ps` 取不到

6.0 把 `debug-tweaks` 拆成 `allow-empty-password allow-root-login post-install-logging`，
但 `serial-getty` 仍然弹 `Password:`，回空行被拒（`Login timed out` / 退回 `login:` 提示）。
3.1~5.0 因为还有 `debug-tweaks` 的空密码后处理，可以免密登录。

wrynose 因此改用两条等价证据：

1. 启动日志里 udev 的 socket 已监听、规则已装载：

   ```text
   [  OK  ] Listening on udev Control Socket.
   [  OK  ] Listening on udev Kernel Socket.
   [  OK  ] Listening on udev Varlink Socket.
            Starting Load udev Rules from Credentials...
   ```

2. 镜像里有 435 个 `systemd` 单元/相关文件，`systemd-udevd` 与 `udevadm` 二进制都在位。

需要 `ps` 硬证据时可以给镜像临时加 `debug-tweaks`（6.0 用上面三项里的
`allow-empty-password` 不够，要同时把 `root` 的 shadow 条目置空），但那会污染交付镜像，
本卡不采用。

## DISTRO_FEATURES 终值（wrynose）

```text
DISTRO_FEATURES=" systemd usrmerge acl alsa debuginfod ext2 ipv4 ipv6 wifi xattr
pci nfc vfat seccomp pulseaudio gobject-introspection-data ldconfig ptest multiarch vulkan "
```

七个删除项（`x11 wayland opengl 3g bluetooth nfs zeroconf`）全不在；`systemd` 在；
`sysvinit` 不在。

> `wifi nfc alsa pulseaudio vulkan gobject-introspection-data` 不在本卡审计的七项里，
> 属产品化收口（#57 起的启动/体积优化）。写在这里防止后来人误判为漏删。

## 镜像内容

| release | 条目数 | `usr/lib/systemd/` 条目 | 裁剪项残留 |
|---|---|---|---|
| 3.1 dunfell | 5380 | 41 | 0 |
| 4.0 kirkstone | 4069 | 49 | 0 |
| 5.0 scarthgap | 4080 | 388 | 0 |
| 6.0 wrynose | 5087 | 435 | 0 |

残留检查的正则：`libX11|libxcb|libwayland|libGL\.|bluez|avahi|libnfs`。
**注意 `libGL` 必须带转义的点**，否则 `libglib-2.0.so.0` 会被大小写不敏感匹配命中
（首轮就是这样报出 2 条假阳性，已逐条核对为误报）。

## 结论

- 阶段 A（切 systemd）：**四版全部真构建 + 真起机通过**。
- 阶段 B（裁七项）：四版镜像里都没有对应组件，且镜像仍能起到 `login:`。
- 未覆盖：`qemuarm64` machine 维度的起机（`#27` 已单独验过机制，本卡不重复）。
