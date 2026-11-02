# 启动时间基线（wrynose 6.0，三层镜像）

> 归档口径：一份文档对应一次测量。数字变了就新开一份，**不要就地改**——改了就
> 没法回答「优化前后差多少」。
>
> 测量命令：`bash scripts/boot-time.sh --release wrynose --variant custom --image <层> --runs 3`
> 原始产物：`work/artifacts/wrynose/custom/boot-time-<层>.json`（脚本默认写
> `boot-time.json`，按层测量的结果要另存，否则后一层覆盖前一层）

## 0. 当前状态：数字还空着（阻塞于 #110）

**本文件的方法论与口径是定稿的，结果表是空的。** 不是没测，是测量链本身有问题：

- `scripts/boot-time.sh` 的真实起机模式每次等满 `--timeout`，然后报「run N 未拿到
  login，跳过」，最终没有可用样本；
- 但对应的串口日志末尾明确有 `yp-qemux86-64 login:`（证据：
  `work/logs/serial-boottime-wrynose-custom-r1.log`）；
- 说明**起机是好的，打点没抓到**。落点已定位到 `scripts/lib/inner-boot-time.sh`：

  ```bash
  timeout ... runqemu "${RUNQEMU_ARGS[@]}" nographic slirp snapshot <"${FIFO}" 2>&1 |
      tee >(monitor_stream) >"${LOG}"
  ```

  `monitor_stream` 用 `while IFS= read -r -n 1 ch` 匹配 `login:` 并写 `${MARKS}.login`，
  但那个文件从未生成——进程替换那一路没收到数据。

**为什么不先填 0 或「约 N 秒」**：基线一旦失真，后面 v0.5.0 的四项实验全部失去对照面，
而且没人会回头怀疑基线。宁可空着并写明阻塞项，也不要一个看起来完整的假表。

修好后按第 1 节口径重跑，把第 2 节填满，并把本段换成实测环境说明。
#110 的修复建议与回归方式（用 `--from-log` 回放一份含 `login:` 的串口日志）写在 issue 里。

## 1. 口径（先看这段，否则数字会被误读）

| 项 | 口径 |
|---|---|
| 加速 | **KVM**（构建容器带 `--device /dev/kvm`）。TCG 模式的数字不能与本表比较，同一镜像能差十倍 |
| 采样 | 每层起机 3 次，取**中位数**；离群值不剔除，超时视为失败 |
| 三段 | `bootloader`（U-Boot 起到内核入口）/ `kernel`（内核起到 init）/ `userspace`（init 起到 login 提示） |
| 判定 | 三段之和与墙钟吻合才采信；串口日志缺失 login 提示直接判 FAIL |

三段分开记的原因：单一「开机 N 秒」没法归因——到底是 bootloader 慢、内核慢，
还是用户态在等某个 unit。v0.5.0 的内核裁剪 / systemd 精简 / rootfs 格式三个实验
都靠这三段做对照。

## 2. 结果

（测量完成后填；当前阻塞见第 0 节）

| 层 | 镜像 | bootloader | kernel | userspace | 墙钟中位数 | 3 次原始值 |
|---|---|---|---|---|---|---|
| minimal | `yp-image-minimal` | | | | | |
| base | `yp-image-base` | | | | | |
| full | `yp-image` | | | | | |

## 3. 怎么读这三行

三层是刻意做出来的对照面，不是「随便打个包」：

- **minimal**：只有内核 + systemd + 串口。这一行是「裸底有多快」。
- **base**：加上日常工具（`curl` / `tar` / `procps` / `util-linux`）。这一行是
  「有工具之后慢多少」——如果它和 minimal 差不多，说明慢的不是包，是 unit。
- **full**：加上业务包与 demo（六个构建系统 + 两个服务）。这一行是「有服务再慢
  多少」，也是 v0.5.0 各项优化的主战场。

三层必须满足 `minimal ⊂ base ⊂ full`（体积单调），这条由 `12_distro.bats` 断言，
本表的耗时也应该同向递增；**如果出现 full 比 base 快，先怀疑测量而不是优化生效**。

## 4. 与历史数据的关系

历史测量分散在 `docs/qa/wrynose/` 的月度归档与 `metrics/` 里，那些是不同提交、
不同负载下的数，**不要混着比**。要比就重跑一遍同样的命令，用同一份文档存档。

## 5. 已知干扰项

- 构建机是共享节点：别的 Jenkins 作业满载时，同一镜像的 userspace 段能慢出 1~2 秒。
  所以取中位数、不取单次。
- `rm_work` 之后重新解包、sstate 冷热不同，会让 rootfs 的内容布局略有差异，
  影响的是 `userspace` 段的文件读取，通常 < 100 ms，但足以让「优化 3%」的结论失真。
  要下这种结论，固定 sstate 状态再测。
- dunfell（3.1）的 `runqemu` 要 machine 位置参数、wrynose 的 `.zst` 只支持 `snapshot`，
  这些差异在 `inner-qemu.sh` 里处理；**基线只取 wrynose**，跨版本比启动耗时不成立
  （内核版本、systemd 版本、initramfs 策略都不同）。

## 6. 内核裁剪实验（#72，2026-11-03）

wrynose-custom **minimal** 层，每配置起机 3 次取中位数，KVM，`--timeout 60`。
实现：`layers/meta-yp/recipes-kernel/linux/linux-yocto/yp-minimal.cfg` +
`linux-yocto_%.bbappend`（按 LAYERSERIES 门控，只在 6.0 生效）。G1~G3 按组串行启用，
压缩组在 G3 全开状态上三选一各测一遍。

| 配置 | kernel_ms | wall_ms | bzImage 字节 | 相对上一行 |
|---|---:|---:|---:|---|
| G0 基线（defconfig，gzip） | 12861 | 17390 | 13784064 | — |
| G1 调试设施（DEBUG_INFO/FTRACE/KPROBES 关） | 11714 | 15969 | 11936768 | **-8.9%**，体积 -13.4% |
| G2 +文件系统（btrfs/nfs/cifs 关） | 11987 | 16191 | 10331136 | 启动时间与 G1 差异在噪声内，体积再 -13.5% |
| G3 +设备（sound/wlan/bt/非virtio网卡关） | 11640 | 15941 | 9679872 | 启动时间与 G1 差异在噪声内，体积再 -6.3% |
| G3 + LZ4 | 11764 | 15827 | 12088320 | 比 gzip 大 25%，启动无收益 |
| G3 + ZSTD（**定稿**） | 11669 | 15924 | 8614912 | 启动无差异，体积比 gzip 小 11% |

**结论**：

1. **只有 G1（调试设施）有真实启动收益**（约 -1.1s）。DEBUG_INFO 的 DWARF 段直接影响
   bzImage 解压量，是「体积 → 启动」传导最直接的一项。
2. G2/G3 是**体积优化不是启动优化**：btrfs/nfs/声卡这些驱动惰性初始化，不进启动路径。
   保留它们的代价只是镜像/内存占用，对 QEMU 场景收益有限，裁掉属于顺手。
3. 压缩算法在 KVM 下**三选一启动时间等价**（解压 10MB 级内核的耗时低于测量噪声）。
   定稿 ZSTD：体积最小（8614912，比基线小 37.5%），`zstd-native` 已进 DEPENDS。
4. **坑（写下来防止重踩）**：KERNEL_FEATURES 里的 scc 在 SRC_URI fragment **之后**
   合并，`debug-kernel.scc` 会把 fragment 关掉的 DEBUG_INFO 重新打开（首版 G1 的
   .config 里 DEBUG_INFO 回到 =y，靠 bzImage 体积对不上才发现）。每启用一组裁剪必须
   在 bbappend 里同步摘掉对应 scc。

各配置的原始 boot-time.json 在测量机上 `/tmp/bt-measure-{g0,g1,g2,g3,lz4,zstd}.json`
（测量过程产物，不入库；本表数字均可由表内命令复现）。

## 7. systemd 启动剖析与精简（#73，2026-11-03）

wrynose-custom **full** 层真起机（`boot-exec.sh`），systemd 257。注意口径：
`systemd-analyze` 的数字是 guest 内部时钟（不含 runqemu 起容器/内核加载的 ~4s 墙钟开销），
与第 6 节的墙钟不可直接相加。

**改造前**（内核为 #72 定稿态）：

```
Startup finished in 1.621s (kernel) + 9.059s (userspace) = 10.700s
multi-user.target reached after 8.869s in userspace.
```

blame 头部（时长并行会重叠，只用于排序，不可相加）：
`dev-vda.device 6.578s`、`systemd-udev-trigger 2.826s`、`dbus 1.518s`、
`systemd-logind 1.030s`、`systemd-udevd 796ms`、三个 yp-demo 服务各 ~750ms。

**关键链**（决定 login 时刻的链）：

```
multi-user.target @8.770s ← getty.target @8.768s
  ← serial-getty@ttyS1.service ← dev-ttyS1.device @8.406s
```

**处置**（只有出现在关键链上的才值得动）：

| unit | 处置 | 理由 |
|---|---|---|
| `serial-getty@ttyS1` | **mask**（bbappend 见 `yp-common.inc` 的 YP_MASKED_UNITS） | runqemu 串口布局是 `-serial mon:stdio -serial null`，ttyS1 永远不会有输入，等它的 device unit 纯浪费 |
| `systemd-udev-settle` | 不动 | 实测 **static**（未启用），issue 里点的头号候选在本镜像根本不在跑 |
| `systemd-random-seed` / `machine-id-commit` | 不动 | 同上，static，不在关键链 |
| `systemd-network-generator` | 不动 | enabled 且 515ms，但**不在关键链**——砍了墙钟不变，只让 blame 好看 |
| `systemd-udev-trigger` | 不动 | coldplug 本体，mask 会导致 `/dev` 不全 |

**改造后**：userspace 9.059s → **8.939s**；关键链改走
`serial-getty@ttyS0 ← dev-ttyS0.device @8.442s`，少等一个设备单元。
minimal 层墙钟变化（15941 → 16281ms）在噪声内。

**结构性结论**：userspace 的大头不是服务，是 **udev 冷插队列的排空时刻**——
`dev-ttyS0.device`/`dev-vda.device` 都要等到 ~6-8s 才 active（settle 语义下，
login 要等最慢的那个设备事件处理完）。继续压它的路径是减少设备事件本身（#72 的
内核裁剪已经做了）和加快 vda 的 blkid 探测，都不属于 unit 裁剪的范畴，
在本 issue 到此为止。

## 8. rootfs 格式对比（#74，2026-11-03）

wrynose-custom **minimal** 层，同一份内核（#72 定稿 + SQUASHFS/OVERLAY_FS=y，
见下）+ 同一套 systemd 配置，只换 rootfs 格式。每格式起机 3 次取中位数，KVM。
实验开关：`kas/features/rootfs-{squashfs,cpio}.yml`（构建时叠加，不进默认 target）。

| 格式 | kernel_ms | wall_ms | 产物体积 | 可写 | 内存 | 需要的额外配置 |
|---|---:|---:|---:|---|---|---|
| ext4（默认，virtio 磁盘） | 11353 | 15554 | 34.5MB（.zst，解压后 ~140MB） | ✅ | 低 | 无 |
| squashfs（virtio 磁盘，只读） | 11375 | 15488 | 35.5MB | ❌（只读） | 低 | `QB_KERNEL_ROOT` 带 `ro rootfstype=squashfs rootwait` + `QB_DEFAULT_FSTYPE` |
| cpio.gz（initramfs 全量入内存） | 11742 | 15884 | 35.5MB | ❌（tmpfs） | **高**（rootfs 全量驻留 RAM） | 无（runqemu 自动走 -initrd） |

**结论**：三种格式启动时间**等价**（差异 < 400ms，在测量噪声内）。ext4 的读取
在 QEMU virtio + 主机页缓存下本来就近乎免费，squashfs 省不了读取，cpio.gz 的
解包反而多花 ~300ms。**推荐维持 ext4**：唯一可写、无额外配置、体积与压缩格式
持平。换格式的真实收益场景是「无盘/只读固件」而非「更快开机」。

**踩坑记录**（复现实验前必读）：

1. **defconfig 里 SQUASHFS/OVERLAY_FS 根本没开**（连 `=m` 都不是）——上一版
   fragment 的「保留清单」是空头支票。首测 `error -19` panic 就是它：设备 253:0
   存在但文件系统未注册。已在 fragment 显式 `CONFIG_SQUASHFS=y` / `CONFIG_OVERLAY_FS=y`。
2. **runqemu 默认给 root= 追加 `rw`**，squashfs 必须 `QB_KERNEL_ROOT` 显式带
   `ro`（runqemu 只看 QB_KERNEL_ROOT 里有没有 ro/rw token）+ `rootwait`（virtio
   磁盘注册晚于挂载尝试会直接 panic）。
3. `QB_DEFAULT_FSTYPE ?= "ext4.zst"` 是 qemuboot.bbclass 的默认值，且 **kas 的
   local.conf 在 distro conf 之前解析**——distro 追加的 ext4.zst 会盖回来，
   feature 里要 `IMAGE_FSTYPES:remove` 收口，且 `:remove` 在 finalize 阶段晚于
   一切 append，这个顺序依赖要在注释里写明。
4. 多种格式并存时 runqemu 按 `qb_default_fstype` 解析，**实验时 deploy 里只留
   一种格式**，否则测的和想测的不是同一个文件（首版 squashfs 数据就是 ext4 冒充的）。
