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
