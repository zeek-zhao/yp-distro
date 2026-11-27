# YP-M1-DES-001 · M1-S0 QEMU 启动与串口基线设计

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-DES-001 |
| 版本 | v1.0 |
| 状态 | Approved（设计先行；本提交只含设计与四问评审，代码在评审后单独提交） |
| 关联 | YP-M1-AI-001 v1.0；`docs/m1/plan.md` §M1-S0；基线 `m0.1.3`=`300007e`；分支 `feat-m1-dev-platform` |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-27 |

## 1. 目的与不做的事

**目的**：让 M0 的 `core-image-minimal-qemux86-64.rootfs.ext4` 在 QEMU 中可重复启动、串口输出落盘并可采集登录提示，作为 M1-S1 之后 deploy-target / gdbserver 的目标机靶子。

**不做**（AI-001 §0 不在范围）：不写 `yp-image-dev`、镜像/包组、eSDK、deploy-target、gdbserver、四步 CI；不改 M0 结论、不移动 M0 tag、不建 M2 分支；不下载 11 GiB、不跑全冷构建；不打 `m1.0` tag。

## 2. 输入与前提

- **镜像**：已有产物 `/workspace/m0*-build-artifacts/core-image-minimal-qemux86-64.rootfs-*.ext4`（M0 判据 1 产出，42M，ext4）；没有则按 M0 缓存路径 `kas build kas/yp.yml:editions/prod.yml` 重建（复用 `/workspace/m01-e1/{downloads,sstate}`，不下载 11 GiB）。
- **内核**：ext4 内含 `/boot/bzImage-<ver>-yocto-standard`（实测 14M，`bzImage` 是指向它的符号链接）。脚本用 `debugfs` 提取到临时文件作为 `-kernel`；或接受 `--kernel <path>` 覆盖。ext4 无独立内核文件导出，故从镜像内取是唯一不重建的方式。
- **QEMU**：宿主 `qemu-system-x86_64`（TCG 模式，无 `/dev/kvm`）；实测 Debian/Ubuntu `qemu-system` 包可用（QEMU 8.2.2）。builder 镜像不含 QEMU，本 Stage 在宿主跑 QEMU（不改 Dockerfile，避免动 M0 的 jenkins/kas 基线）。
- **资源口径**：机器有多少用多少，容器/QEMU 不加 `--cpus`/`--memory`/`--cpu-quota`/`--cpuset-cpus`；每次记录实际 `nproc`、`/proc/meminfo MemTotal`；无 KVM 时明确标 TCG，不写硬件加速通过。

## 3. 失败模式与检测

| # | 失败模式 | 检测信号 | 处理 |
|---|---|---|---|
| F1 | 无 QEMU / `qemu-system-x86_64` 不在 PATH | `command -v` 失败 | `BOOT_FAIL`，提示安装 `qemu-system` |
| F2 | 无 `/dev/kvm`（当前宿主即如此） | `test -e /dev/kvm` 失败 | 用 TCG，记录启动耗时，明确写 TCG，不写 KVM |
| F3 | `root=` 设备名错误 | 内核日志 `VFS: Cannot open root device` + panic | 脚本固定 `root=/dev/vda`（virtio-blk 实测设备名）；非 virtio 时允许 `--root` 覆盖 |
| F4 | 默认 `qemu64` CPU 无 AVX，init 执行 `vzeroupper` 触发 `trap invalid opcode` panic | 串口日志 `traps: init[1] trap invalid opcode` / `Attempted to kill init` | 用 `-cpu max`（TCG 下传递 AVX 等扩展）；`-cpu host` 在 TCG 下不可用（报 `requires KVM or HVF`），不得使用 |
| F5 | 串口无输出 / getty 未起 | 日志无 `login:` | 断言失败 → `QEMU_SMOKE_FAIL`；先查 `-append console=ttyS0` 与 `-nographic` |
| F6 | 超时到点 QEMU 残留僵尸 | `timeout` 返回后 `pgrep qemu-system-x86_64` 仍有本轮 pid | 脚本 trap/清理：kill 本轮 QEMU PID 并 wait，退出前确认无残留 |
| F7 | 镜像损坏 / 不存在 | `file` 非 ext4、`debugfs` 提取内核失败、`qemu-img`/QEMU 启动失败 | `BOOT_FAIL` 非 0，错误信息指向镜像/内核，不静默 `BOOT_OK` |
| F8 | 容器资源限制（若在容器跑 QEMU） | `docker inspect` 三项非 0 | 本 Stage 在宿主跑，不经容器；如未来容器化须三项 0/0/0 |

## 4. 验收命令与期望输出

```bash
# 正向（宿主，TCG）
file /workspace/m0*-build-artifacts/core-image-minimal-qemux86-64.rootfs-*.ext4
bash scripts/dev/qemu-run.sh --image <ext4> --timeout 180 --log /tmp/qemu-s0.log
# 期望：BOOT_OK image=<path> log=/tmp/qemu-s0.log timeout=180；日志含 qemux86-64 login:
grep -n 'login:' /tmp/qemu-s0.log
bash scripts/dev/qemu-smoke.sh --image <ext4> --log /tmp/qemu-s0-smoke.log
# 期望：QEMU_SMOKE_OK

# 负向
bash scripts/dev/qemu-run.sh --image /tmp/not-an-image --timeout 10 --log /tmp/qemu-bad.log; echo "BAD_RC=$?"
bash scripts/dev/qemu-smoke.sh --image /tmp/not-an-image --log /tmp/qemu-bad-smoke.log; echo "SMOKE_BAD_RC=$?"
# 期望：均非 0，错误信息指向镜像/启动失败

# 门禁
bash -n scripts/dev/qemu-run.sh scripts/dev/qemu-smoke.sh
bash scripts/gate.sh && bash scripts/check-vars.sh
```

**证据要求**：`BOOT_OK` / `QEMU_SMOKE_OK`、串口登录行原文、实际 `nproc` / `MemTotal`、无 KVM 的 TCG 说明、实际启动耗时与超时值、超时后无残留 QEMU 进程、负向非 0。

## 5. 回滚

删除 `scripts/dev/qemu-run.sh`、`scripts/dev/qemu-smoke.sh` 及本设计/评审/记录文档即可；不改 M0 任何文件、配置、tag，无跨 Stage 影响。宿主安装的 `qemu-system` 是执行环境依赖，不属于仓库回滚范围。

## 6. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建 S0 QEMU 启动设计（含实测 F3/F4 失败模式与 TCG 口径） | zeek.zhao |
