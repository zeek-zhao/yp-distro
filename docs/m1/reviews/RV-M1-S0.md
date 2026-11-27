# YP-M1-RV-001 · M1-S0 QEMU 启动与串口基线评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-001 |
| 版本 | v1.0 |
| 评审对象 | YP-M1-DES-001（S0 QEMU 启动与串口基线设计） |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-27 |
| 关联 | YP-M1-AI-001 v1.0；`docs/m1/design/S0-qemu-boot.md`；DES-001 |
| 结论 | 设计通过（四问均通过）；代码与实测证据待评审后单独提交回填 |

## 1. 四问自评

**Q1 覆盖需求**：S0 目标「core-image-minimal 在 QEMU 可重复启动、串口可采集」由 qemu-run.sh（BOOT_OK + 串口落盘）+ qemu-smoke.sh（断言 login:）覆盖；AI-001 §2 的参数（--image/--machine/--timeout/--log）、超时清理、资源记录、TCG 口径、负向测试均在设计 §3/§4 逐条对应。eSDK/deploy/gdbserver/四步 CI 明确列为「不做」，不越界。✅

**Q2 失败模式列全且检测可执行**：设计 §3 列 8 类失败（无 QEMU / 无 KVM / root 设备名 / AVX invalid opcode / 串口无输出 / 超时残留 / 镜像损坏 / 容器限制），每类给出具体检测信号与处理。其中 F3（root=/dev/sda→vda）与 F4（qemu64 无 AVX→-cpu max）是实测发现并已验证修复路径的真实障碍，非理论推测。✅

**Q3 验收可执行**：验收命令全部为具体可执行命令（file/qemu-run/grep login:/qemu-smoke/bash -n/gate/vars），期望输出明确（BOOT_OK/QEMU_SMOKE_OK/login: 行/非 0），失败即红；镜像用已有 ext4 产物或从 ext4 提取内核，不下载 11 GiB、不全冷构建。✅

**Q4 回滚可行**：删除两个脚本与本套设计/评审文档即可，不改 M0 文件/配置/tag，无跨 Stage 影响；宿主 qemu-system 安装属执行环境、不在仓库回滚范围。✅

## 2. 设计阶段探测证据（真实，非仓库产物）

设计前做了只读可行性探测（宿主，无 KVM）：

- `qemu-system-x86_64 --version` → QEMU emulator version 8.2.2（TCG）。
- ext4 `/boot` 含 `bzImage-6.18.52-yocto-standard`（14M，`file` 识别为 Linux kernel x86 bzImage）；`debugfs -R dump` 可提取。
- `root=/dev/sda` → `VFS: Cannot open root device "/dev/sda"`，内核 panic（virtio-blk 实际为 `/dev/vda`）→ F3 来源。
- 默认 `qemu64` CPU → `traps: init[1] trap invalid opcode ... vzeroupper`，`Attempted to kill init` panic → F4 来源。
- `-cpu host` → 立即失败 `CPU model 'host' requires KVM or HVF`（TCG 下不可用，禁用）。
- `-cpu max` + `root=/dev/vda` → `VFS: Mounted root (ext4)` 且串口出现 `qemux86-64 login:`（内核约 3s 起，getty 有 `respawning too fast` 非致命警告）→ 可行路径确认。

以上为设计输入探测，最终实跑证据待代码提交后在 §3 回填。

## 3. 实测证据（代码提交后回填）

（本节在 qemu-run.sh / qemu-smoke.sh 提交并实跑后回填：BOOT_OK / QEMU_SMOKE_OK / login 行 / nproc / MemTotal / TCG 启动耗时 / 超时无残留 / 负向非 0 / gate/vars。）

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建：S0 设计四问评审 + 设计阶段真实探测证据（F3/F4 来源）；实测待回填 | zeek.zhao |
