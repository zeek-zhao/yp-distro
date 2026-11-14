# 启动优化对比报告：每项措施的收益与代价

> v0.5.0（#72/#73/#74 + #78）的汇总。数字全部来自 `docs/qa/boot-baseline.md`
> 第 6/7/8 节的实测（可追溯到 `work/artifacts/wrynose/custom/boot-time-*.json`），
> 口径：wrynose-custom、KVM、中位数；标「噪声内」的差异 < 400ms（≈3%）。
> 实验对象的实现与踩坑记录在对应小节，这里只做横向对比与取舍。

## 一、措施总表

| 措施 | kernel_ms 变化 | wall_ms 变化 | 代价 / 风险 | 值不值 |
|---|---|---|---|---|
| 内核裁调试设施（DEBUG_INFO/FTRACE/KPROBES） | 12861 → 11714（**-8.9%**） | 17390 → 15969（-8.2%） | 无法内核调试，gdb 无符号；bzImage -13.4% | **值** —— 唯一有真实启动收益的内核措施，DWARF 段直接影响解压量 |
| 内核裁不用文件系统（btrfs/nfs/cifs） | 噪声内 | 噪声内 | 换硬件/换存储后端要重编内核；bzImage 再 -13.5% | 不值（作为启动优化）；体积纯收益，顺手保留 |
| 内核裁不用设备（sound/wlan/bt/非virtio网卡） | 噪声内 | 噪声内 | 动态设备识别变弱，换硬件要重编；bzImage 再 -6.3% | 不值（作为启动优化）；同上 |
| 内核压缩 ZSTD（gzip → zstd） | 噪声内 | 噪声内 | 无（zstd-native 进 DEPENDS） | **值** —— 三种压缩启动等价，ZSTD 体积比 gzip 小 11%，白捡 |
| mask serial-getty@ttyS1（#73） | —（userspace 9.059 → 8.939s，analyze 口径） | 噪声内 | 无 —— ttyS1 是 runqemu 的 `-serial null`，永远没有输入 | **值** —— 架构上正确，关键链少等一个设备单元 |
| rootfs 换 squashfs / cpio.gz（#74） | 噪声内 | 噪声内 | squashfs 只读要动 QB_KERNEL_ROOT/QB_DEFAULT_FSTYPE；cpio.gz 全量驻留 RAM | 不值 —— 维持 ext4（唯一可写、零额外配置、体积持平） |

## 二、「到此为止」的理由

1. **内核侧只剩调试设施一项有启动收益，已经拿走**。G2/G3 证明「裁东西」与
   「快起来」之间隔着惰性初始化——驱动不在启动路径上，裁得再干净也只减体积。
2. **userspace 的结构性瓶颈是 udev 冷插队列排空**（`dev-ttyS0.device`/`dev-vda.device`
   要 ~6-8s 才 active，login 等最慢的设备事件）。压它要么继续减设备事件（#72 已做，
   收益已体现），要么改 systemd 的 settle 语义（改发行版核心行为，收益/风险比转负）。
   服务侧的 blame 头部（dbus/logind/udevd）都不在关键链上，砍了墙钟不变。
3. **rootfs 格式是死胡同**：QEMU virtio + 主机页缓存下磁盘读取近乎免费，
   三种格式的启动时间等价，换格式只有工程成本没有启动收益。

## 三、服务数量 × 启动耗时（#78）

三层镜像 × 5 次（同一内核、同一 systemd 配置，唯一变量是装的包）：

| 镜像 | 自研 unit 数 | kernel_ms | wall_ms | 每 unit 均摊 |
|---|---:|---:|---:|---:|
| minimal | 0 | 11326 | 15553 | — |
| base | 0（工具包，无服务） | 11357 | 15592 | — |
| full | 10（yp-hello-svc / yp-statusd / yp-collectd + 7 个 yp-demo-*） | 12665 | 16995 | **~134ms/unit** |

**结论**：

- **服务是并行的**（systemd 并行拉 unit）：blame 里三个 yp-demo 服务各 ~750ms
  且互相重叠，10 个 unit 只让 login 推迟 ~1.3s——若串行，按 blame 时长相加应
  是 ~6s。所以「改成并行」这件事 systemd 已经做了，没有可捡的收益。
- 每服务均摊 ~134ms，主要成本是 unit 的启动依赖等待（demo 服务都是
  `After=multi-user` 之前的简单 oneshot/simple），不在 login 关键路径上也能并行。
- **值不值得再优化服务**：不值得。要快就砍 unit（服务数 × 耗时接近线性），
  而服务是这个发行版的演示主体；样本方差（QEMU 冷启动 ±15%）也盖住了
  单个简单服务的抖动。
- 口径提醒：本表的「耗时」到 login 提示为止；服务自身就绪（如 yp-statusd
  监听端口）晚于 login，要测服务就绪得看 `systemd-analyze blame` 里各自的
  时长，不能拿 login 时刻冒充。

## 四、复现

```bash
# 三层基线（本表数据）
for i in minimal base full; do
    bash scripts/boot-time.sh --release wrynose --variant custom --image "$i" --runs 5 --timeout 60
    cp work/artifacts/wrynose/custom/boot-time.json "work/artifacts/wrynose/custom/boot-time-$i.json"
done
# 各项优化的实验过程与命令见 docs/qa/boot-baseline.md 第 6/7/8 节
```
