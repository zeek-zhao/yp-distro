# YP-M1-RV-001 · M1-S0 QEMU 启动与串口基线评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-001 |
| 版本 | v1.1 |
| 评审对象 | YP-M1-S0 实现（qemu-run.sh / qemu-smoke.sh）；设计 YP-M1-DES-001 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-27 |
| 关联 | YP-M1-AI-001 v1.0；`docs/m1/design/S0-qemu-boot.md`；DES-001 |
| 结论 | S0 通过（R1–R6）：BOOT_OK / QEMU_SMOKE_OK、串口 login 行、TCG 9–10s、超时无残留、负向非 0、门禁绿；无 KVM 用 TCG 不写硬件加速 |

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

## 3. 实测证据（代码提交后，宿主 TCG）

镜像：`/workspace/m012-build-artifacts/core-image-minimal-qemux86-64.rootfs-20261127090522.ext4`（`file` → Linux rev 1.0 ext4），内核由脚本从 ext4 `/boot/bzImage-6.18.52-yocto-standard` 自动提取。

### 3.1 正向

- `bash scripts/dev/qemu-run.sh --image <ext4> --timeout 180 --log /tmp/qemu-final.log` →
  - `RESOURCE nproc=32 MemTotal_kb=129308484 docker_inspect=N/A(host-is-nested-container)`
  - `ACCEL=tcg（TCG 为软件仿真，不视为硬件加速通过）`
  - `BOOT_OK image=<ext4> log=/tmp/qemu-final.log timeout=180`
  - `BOOT_ELAPSED=10s ACCEL=tcg nproc=32 MemTotal_kb=129308484`（exit 0）
- 串口登录行原文：`395:qemux86-64 login: INIT: Id "S1" respawning too fast: disabled for 5 minutes`（`respawning too fast` 为 getty 非致命警告，不影响 login 出现）。
- `bash scripts/dev/qemu-smoke.sh --image <ext4> --log /tmp/qemu-final-smoke.log` → `QEMU_SMOKE_OK image=<ext4> ... marker=login:` + 同一 login 行（exit 0）。
- 资源口径：宿主 32c / MemTotal=129308484 kB（达 32c/128G 基线）；无 `/dev/kvm` → TCG；QEMU 进程未加 `--cpus`/`--memory`/`--cpu-quota`/`--cpuset-cpus`（脚本内无这些参数）；沙箱为嵌套容器、无法 inspect 自身，故 docker 三项标 `N/A(host-is-nested-container)`，不冒充 `0/0/0`。

### 3.2 负向（均非 0，错误指向镜像/启动失败）

| 命令 | rc | 关键输出 |
|---|---|---|
| `qemu-run.sh --image /tmp/not-an-image --timeout 10 --log /tmp/qemu-bad.log` | 1 | `BOOT_FAIL reason=image not ext4: ... (ASCII text)` |
| `qemu-run.sh --image /tmp/does-not-exist --timeout 10 --log /tmp/qemu-bad2.log` | 1 | `BOOT_FAIL reason=image not found: ...` |
| `qemu-smoke.sh --image /tmp/not-an-image --log /tmp/qemu-bad-smoke.log` | 1 | `QEMU_SMOKE_FAIL reason=qemu-run.sh failed ...` |

### 3.3 超时清理（R2）

`qemu-run.sh --image <ext4> --timeout 3 --log /tmp/qemu-timeout.log` → rc=1、wall=3s、`qemu-system-x86_64: terminating on signal 15`；等待 2s 后 `pgrep -af qemu-system-x86_64` → `NO_QEMU_RESIDUE_AFTER_TIMEOUT`。正向/smoke 后同样 `NO_RESIDUE`，无僵尸残留。

### 3.4 门禁（R5/R6）

`bash -n scripts/dev/qemu-run.sh scripts/dev/qemu-smoke.sh` → SYNTAX_OK（gate G1 亦覆盖全部 36 个脚本）；`bash scripts/gate.sh` → **GATE_PASS**；`bash scripts/check-vars.sh` → **VARS_OK checked=36 drift=0**；token 扫描 0、无大二进制、工作区干净。

**CI 状态（如实）**：push `db91de3` 到 `feat-m1-dev-platform` 后，按 head_sha 查询 GitHub Actions `total_count=0`——因 gate/publish workflow 的 push 分支限制为 `feat-m0*`/`release-m0*`，本分支 `feat-m1-*` 不匹配，且 `scripts/dev/**` 不在 `m0.yml` paths 内，故未触发 CI。本轮 AI-001 §4/§5 未要求改 workflow、观察 CI 或打 `m1.0` tag，故**不为让 CI 跑而改 paths**（遵循前序硬边界）；以本地 GATE_PASS/VARS_OK 为质量证据，远端 CI 记为「未触发（分支不匹配）」，不冒充 success。M1 后续 Stage 若需 CI，应单独评审 workflow 的 M1 分支触发策略。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建：S0 设计四问评审 + 设计阶段真实探测证据（F3/F4 来源）；实测待回填 | zeek.zhao |
| v1.1 | 2026-11-27 | 回填实测：BOOT_OK/QEMU_SMOKE_OK、login 行、TCG 9–10s、超时无残留、三个负向非 0、GATE_PASS/VARS_OK；修 qemu-run 内核提取 awk（$5→$NF）、qemu-smoke 的 qemu-run 路径（BASH_SOURCE/..→dirname）；结论 S0 通过 | zeek.zhao |
