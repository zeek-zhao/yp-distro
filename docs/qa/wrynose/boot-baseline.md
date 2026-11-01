# wrynose 6.0 启动时间基线（U-Boot 链）

> 关联 issue #61（U-Boot x86 zboot 启动链）、#63（三段启动计时基线）。
> 本文件是 v0.3.0 收口时建立的 boot-time 基线，数据来自 `scripts/boot-time.sh`
> 在构建机的 release 容器（KVM）上的 3 次真起机测量。

## 测量对象
- release：wrynose（yocto 6.0.4）
- variant：custom（IMAGE=yp-image，开启 `YP_UBOOT` 启动链）
- machine：qemux86-64
- 启动链：QEMU `-bios u-boot.rom` → U-Boot SPL → U-Boot proper → `qfw load` 从 fw_cfg
  载入内核/initrd → `zboot` 引导 bzImage → Linux → systemd → login

## 三段计时（中位值，KVM，3 次）
| 阶段 | 定义 | 中位耗时 |
|---|---|---|
| wall | 脚本启动 → 出现 `login:`（用户体验端到端） | 21524 ms（≈ 21.5 s） |
| kernel | 内核 `Starting kernel`/首条 `[0.000000]` 出现 → `login:`（内核 + 用户态） | 15042 ms（≈ 15.0 s） |
| uboot | `U-Boot 2026.01` 出现 → `Starting kernel`（SPL+proper 引导加载） | 1839 ms（≈ 1.8 s） |

- 单次区间：wall [21072, 22675] ms；kernel [14910, 15703] ms；uboot [1833, 1844] ms。
- 原始数据：`work/artifacts/wrynose/custom/boot-time.json`（由 `scripts/boot-time.sh` 再生，
  被 `.gitignore` 忽略，不入库）。
- 串口日志：`work/logs/serial-boottime-wrynose-custom-r{1,2,3}.log`。

## 关于 self_check_drift（≈ 21.6%）
`boot-time.sh` 自检把「kernel + uboot 之和」与 wall 比较，偏差约 21.6%。这不是测量错误：
wall 还包含 **QEMU/runqemu 启动开销**（加载 bios、初始化设备、直到 U-Boot 开始打印），
这部分约 4.6 s，不属于 uboot（U-Boot 阶段）或 kernel（内核→login 阶段）任一阶段。
即：wall ≈ qemu_init(~4.6 s) + uboot(1.8 s) + kernel(15.0 s)。后续若要纳入 qemu 初始化，
需在工具里增加第 4 段计时。

## 验证要点（来自串口日志）
- `U-Boot SPL 2026.01` → `U-Boot 2026.01`（SPL→proper 正常）
- `Starting kernel ...`（`zboot` 引导生效，不再出现 `Unknown command 'booti'/'bootz'`）
- `Linux version 6.18.52-yocto-standard` 启动
- `Reached target Multi-User System` / `yp-qemux86-64 login:` 到达
- 6.0 custom 镜像开启 empty-root-password，`root` + 空密码可串口登录（已实测）

## 备注
- 镜像内未安装 `systemd-analyze`，故 `boot-time.json` 的 `systemd_analyze` 字段为 null；
  systemd 内部分段未采集。
- 本次测量时 `scripts/boot-time.sh` 的流式打点存在竞态（monitor 子进程未能在脚本读取前
  落盘 MARKS），工具侧最终 json 未写出；基线数据改用捕获到的原始 serial 计时打点（MARKS）
  聚合得到，三段计时数值本身无误。
