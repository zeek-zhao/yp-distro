# YP-M1-AI-001 · M1-S0 QEMU 启动与串口基线提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-AI-001 |
| 版本 | v1.0 |
| 状态 | Ready（M1 规划 v0.3 已确认 D-01/S0/资源口径） |
| 基线 | `m0.1.3` = `300007e`；分支 `feat-m1-dev-platform` |
| 目标 | 只做 M1-S0：让 M0 的 `core-image-minimal` 在 QEMU 中可重复启动、串口可采集，为后续 deploy/gdbserver 提供靶子 |
| 不在范围 | M1-S1 镜像/包组、eSDK、deploy-target、gdbserver、四步 CI；M2/M3/M4；改 M0 结论；移动旧 tag；`--force`；全冷构建 |

## 0. 先读

```bash
cd <repo>
git fetch origin '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*' --prune --force
git switch feat-m1-dev-platform
git rev-parse HEAD
git rev-parse 'm0.1.3^{commit}'
```

先读：

- `docs/m1/plan.md` §3.1/§3.2/§M1-S0/§7；
- `docs/m0/acceptance.md` 判据 1（M0 只验证 ext4，不证明启动）；
- `scripts/gate.sh`、`scripts/build/threads.sh`；
- `kas/base.yml`、`kas/editions/ci.yml`。

基线必须是 `m0.1.3` 的后代；不要从 `m0.1.2` 或旧分支拉。M0 tag 不动。

## 1. 设计先行（必须先提交/评审，再写脚本）

新建 `docs/m1/design/S0-qemu-boot.md`，至少写：

1. 目的与不做的事；
2. 输入：已有 `core-image-minimal-qemux86-64.rootfs.ext4` 或按缓存重建；
3. 失败模式：无 QEMU、无 KVM、串口无输出、超时、镜像不完整、容器资源限制；
4. 验收命令与期望输出；
5. 回滚方式。

新建 `docs/m1/reviews/RV-M1-S0.md` 回答四问。设计未过，不写代码。

## 2. 交付

### 2.1 `scripts/dev/qemu-run.sh`

要求：

- 参数至少：`--image <ext4>`、`--machine qemux86-64`、`--timeout 180`、`--log <path>`；
- 启动 QEMU，串口输出落盘；`timeout` 到点必须清理 QEMU 进程，不能留僵尸；
- 成功打印 `BOOT_OK image=<path> log=<path> timeout=<n>`；失败打印 `BOOT_FAIL` 并非 0；
- 不硬编码 32c/128G；容器运行时不加 `--cpus`、`--memory`、`--cpu-quota`、`--cpuset-cpus`；
- 每次运行记录实际 `nproc`、`/proc/meminfo` 的 `MemTotal`；若在容器内，另记 `docker inspect` 的 `NanoCpus/Memory/CpuQuota`；
- 没有 `/dev/kvm` 时用 TCG，记录实际启动耗时；**不得写成硬件加速通过**；
- 不下载 11 GiB；优先用已有产物或本地缓存重建。

### 2.2 `scripts/dev/qemu-smoke.sh`

- 调用 `qemu-run.sh`；
- 断言串口日志出现登录提示（例如 `login:`）或设计文档声明的等价启动标记；
- 输出 `QEMU_SMOKE_OK` / `QEMU_SMOKE_FAIL`；
- 支持传入一个故意损坏/不存在的镜像做负向测试，必须非 0。

### 2.3 可选：builder 依赖

若 `runqemu` 在 builder 内不可用，允许在 `docker/Dockerfile` 补 QEMU 运行依赖；必须：

- 说明为什么必须补、补了什么包；
- 不改变 M0 的 jenkins 非 root、kas 5.5、UID/GID；
- 在 RV 里记录镜像重建与 `whoami`/`id -u` 复核。

## 3. 实跑与证据

### 3.1 正向

```bash
# 先用已有产物；没有则按 M0 缓存路径构建 core-image-minimal
file <ext4>
bash scripts/dev/qemu-run.sh --image <ext4> --timeout 180 --log /tmp/qemu-s0.log
grep -n 'login:' /tmp/qemu-s0.log
bash scripts/dev/qemu-smoke.sh --image <ext4> --log /tmp/qemu-s0-smoke.log
```

必须贴：

- `BOOT_OK` / `QEMU_SMOKE_OK`；
- 串口日志中的登录行；
- 实际 `nproc` / `MemTotal` / `NanoCpus=0 Memory=0 CpuQuota=0`（若容器）；
- 实际启动耗时与超时值。

### 3.2 负向

```bash
bash scripts/dev/qemu-run.sh --image /tmp/not-an-image --timeout 10 --log /tmp/qemu-bad.log
echo "BAD_RC=$?"
bash scripts/dev/qemu-smoke.sh --image /tmp/not-an-image --log /tmp/qemu-bad-smoke.log
echo "SMOKE_BAD_RC=$?"
```

期望非 0，且错误信息指向镜像/启动失败，不是静默 `BOOT_OK`。

### 3.3 门禁

```bash
bash -n scripts/dev/qemu-run.sh scripts/dev/qemu-smoke.sh
bash scripts/gate.sh
bash scripts/check-vars.sh
```

`GATE_PASS` / `VARS_OK`；若新增变量，必须进 `docs/m0/variable-index.md` 并跑 drift。

## 4. 记录与提交

- `docs/m1/design/S0-qemu-boot.md`；
- `docs/m1/reviews/RV-M1-S0.md`：四问 + 真实输出；
- 若 QEMU 依赖/脚本契约变更：`docs/m1/changes/CHG-M1-00N.md`；
- 若遇到非预期：先 `docs/m1/issues/ISS-M1-00N.md` 再修；
- 提交身份只允许 `zeek.zhao <zeek.zhao@foxmail.com>`，无 AI 署名；
- 提交信息：

```text
feat(m1): add qemu boot and serial smoke baseline

Refs: YP-M1-S0 / YP-M1-DES-00N
Doc: docs/m1/design/S0-qemu-boot.md
```

- 不在本 Stage 打 `m1.0`，不改 `m0.1.3`；不建 M2 分支。

## 5. 验收

| # | 项 | 通过条件 |
|---|---|---|
| R1 | 启动 | `BOOT_OK`，串口出现登录/等价标记 |
| R2 | 超时清理 | 超时后无残留 QEMU 进程 |
| R3 | 负向 | 坏镜像非 0，不误报 |
| R4 | 资源 | 容器不加限制；记录实际 nproc/MemTotal；低于 32c/128G 不写 full-quota |
| R5 | 记录 | DES/RV/CHG/ISS 完整，版本头=最后日志 |
| R6 | 卫生 | 无大二进制、无 token、工作区干净 |

## 6. 回报

1. 改动文件清单；
2. 执行的命令（含失败）；
3. 已验证项与原始输出；
4. 未验证项及原因；
5. 新增记录编号；
6. 下一步建议（只到 M1-S1，不跳 eSDK）。

**不要**在本轮写 `yp-image-dev`、eSDK、deploy-target、gdbserver 或四步 CI；不要用已有 ext4 的 `file` 输出冒充“已启动”；不要把 TCG 写成 KVM。
