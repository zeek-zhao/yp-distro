# YP-M1-DES-004 · M1-S3 deploy-target 与调试链路设计

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-DES-004 |
| 版本 | v1.0 |
| 状态 | Approved（设计先行；本提交只含设计与四问评审，脚本/配方在评审后单独提交） |
| 关联 | `docs/m1/plan.md` §M1-S3 §3.1 §7；基线 `feat-m1-dev-platform`=`a441f91`（S2 已合入并 push）；S1 产物 `yp-image-dev`（含 gdb/gdbserver）为靶机，S2 eSDK 的交叉 gdb/gcc 为宿主调试器 |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-28 |

## 1. 目的与不做的事

**目的**：把「一条命令把改过的程序部署到 QEMU，并用 gdbserver 远程断点、gdb 定位源码行」从规划变成可执行的脚本链路，使 D-03（deploy-target 一条命令 + 目标机 marker）与 D-05（远程断点命中 + 源码行定位）可取证；debuginfod/minidebuginfo 按 plan §7 分层处理，未闭环标 UNVERIFIED。

**不做**（plan §M1-S3 边界）：不写 buildhistory / yocto-check-layer / 四步 CI / `m1-dev.yml`（S4）；不打 `m1.0`、不改 M0 tag 与结论、不建 M2 分支；不新增 PRD 之外的需求；不把 gdbserver 通过写成 D-05 全通过（plan §7 明令）。

**D-05 分层口径**（plan §M1-S3 + §7 已确认项）：

- D-05-a 远程断点命中：`gdbserver` + 宿主交叉 gdb，可跑通 → `GDB_BREAKPOINT_HIT`；
- D-05-b 源码行定位（带 `-g` 符号）：宿主 gdb 加载带符号二进制 `list` 出源码行 → `SOURCE_LINE_OK`；
- D-05-c 无符号表定位（`minidebuginfo` 注入 `.gnu_debugdata`）+ `debuginfod` 本地服务：依赖 `DISTRO_FEATURES` 全量重编（8G cgroup 下 S2 实测首编 3h+ 且归档 OOM），**本轮不宣称闭环，标 UNVERIFIED**，D-05 整体不宣称全通过，留 M1.1 补（符合 plan §7 第 4 条确认项）。

## 2. 输入与前提（容器内 + 宿主实测，非推测）

### 2.1 目标镜像与工具（dev 镜像 `/work/s2build/.../yp-image-dev-qemux86-64.rootfs.ext4`，`debugfs` 只读实测）

| 事实 | 证据 | 对方案的影响 |
|---|---|---|
| `/usr/bin/gdb`、`/usr/bin/gdbserver` 存在且可执行（mode 100755） | `debugfs -R 'ls -l /usr/bin'`（gdb 12277944B、gdbserver 672000B） | D-05-a 的 gdbserver 已就位，S1 包组产物可复用，不重复安装 |
| `/usr/sbin` **无 `sshd` / `dropbear`** | `debugfs -R 'ls -l /usr/sbin' \| grep -iE 'sshd\|dropbear'` 空 | `devtool deploy-target`（`deploy.py` 用 scp/ssh）无法直接连目标，必须给 dev 镜像补 `openssh-sshd` 才能走 SSH 部署 |
| `/etc/passwd` root 存在、`/etc/issue*` 有 login 提示 | `debugfs -R 'cat /etc/passwd'` → `root:*:0:0:...` | dev.yml 已有 `debug-tweaks`，配合 openssh 允许空密码 root 登录（实现阶段验证 `PermitEmptyPasswords`） |
| 镜像无现成 demo 二进制 | `debugfs -R 'ls -l /usr/bin' \| grep hello/demo/smoke` 空 | 需在实现阶段由 SDK 交叉 gcc 编译 `yp-demo` 并部署，不能假装已有 |

### 2.2 宿主/eSDK 工具（实测）

- **宿主 QEMU**：`/usr/bin/qemu-system-x86_64` = QEMU emulator 8.2.2（Debian），无 `/dev/kvm` → TCG（S0 已验证 `-cpu max` + `root=/dev/vda` 可启动到 `login:`，TCG 约 10s）。
- **宿主网络工具**：`ssh`/`scp` 在 PATH；`python3 pexpect 4.9.0` 可用（串口/SSH 非交互自动化兜底）。
- **SDK 交叉调试器**：`/work/yp-sdk-test/tmp/sysroots/x86_64/usr/bin/x86_64-poky-linux/x86_64-poky-linux-gdb` = GNU gdb 17.2；同目录有 `x86_64-poky-linux-gcc`（交叉编译 yp-demo）。
- **eSDK**：S2 已安装到 `/work/yp-sdk-test`，`environment-setup-x86-64-v3-poky-linux` 在（`source` 后 `devtool`/交叉工具进 PATH）。

### 2.3 Yocto 机制（oe-core 固定 commit 实测）

- **`devtool deploy-target` 实现**（`scripts/lib/devtool/deploy.py`）：`scp` 传目录 + `ssh <target> 'sh <script>'` 执行；`parser_deploy` 接受 `target = user@hostname[:destdir]`、`-P/--port`、`-c/--no-host-check`、`-i/--ssh-key`。→ 部署链路 = SSH/scp，需目标 sshd 监听，QEMU 用 slirp `hostfwd` 把宿主端口映射到目标 22。
- **`minidebuginfo`**：`meta/classes-global/package.bbclass:237` 按 `DISTRO_FEATURES` 含 `minidebuginfo` 注入依赖 `xz-native`；`meta/lib/oe/package.py:888 inject_minidebuginfo()` 在 strip 时把 debug 信息压入 `.gnu_debugdata`。代码路径真实存在，但启用会改变所有包的 `do_package` hash → 全量重编。
- **`debuginfod`**：`meta/conf/bitbake.conf:919` 的 `DISTRO_FEATURES_FILTER_NATIVE/NATIVESDK` 含 debuginfod；`meta/recipes-devtools/gdb/gdb-common.inc` 受其影响；`scripts/oe-debuginfod` 可扫描 deploy feed 起本地服务。host 服务依赖未在本轮闭环（plan §7 第 4 条）。
- **`openssh_10.3p1.bb`** 在 oe-core `meta/recipes-connectivity/openssh/`，`openssh-sshd` 可作 `IMAGE_INSTALL` 增量加入 dev 镜像。

### 2.4 资源口径（延续 S1/S2 `RESOURCE_PARTIAL`）

宿主标称 `nproc=32`、`MemTotal≈128GiB`、容器 `NanoCpus=0 Memory=0 CpuQuota=0`；但嵌套沙箱宿主 shell cgroup `memory.max=8G`（S1/S2 OOM 根因，ISS-M1-002/003）。本 Stage 的 QEMU 启动只占 ~512M，SSH/调试为轻量运行；dev 镜像重建（加 sshd）为增量，若需全量重编则按 6/-j2 overlay（不入库），结论标 `RESOURCE_PARTIAL`，不写 full-quota。

## 3. 方案设计

### 3.1 拓扑（QEMU slirp 固定端口）

```
宿主 (127.0.0.1)                QEMU qemux86-64 (TCG, -cpu max)
  :2222  --hostfwd tcp-->  :22    sshd  (deploy-target / scp / ssh)
  :5678  --hostfwd tcp-->  :5678  gdbserver (yp-demo 远程调试)
  串口 -> --log 文件 (login: / YP_DEMO_MARKER)
  -m 512 -smp 2 -nographic -no-reboot -kernel bzImage -append 'console=ttyS0 root=/dev/vda rw init=/sbin/init'
```

派生自 S0 的 `qemu-run.sh`（内核从 ext4 `/boot` 用 `debugfs` 提取、`root=/dev/vda`、`-cpu max`、串口落盘、超时清理）；S3 增加 `hostfwd` 与 sshd/gdbserver 启动，不改动 S0 脚本。

### 3.2 `scripts/dev/deploy-target.sh --target qemu --binary <path>`

- 参数：`--target qemu`（本轮仅 qemu）、`--binary <path>`（宿主已编译的二进制）、`--user <u>`（默认 `root`）、`--port <p>`（默认 2222）、`--dest <dir>`（默认 `/usr/bin`）、`--image <ext4>`（可选，指定则脚本负责启动带 sshd 的 QEMU 靶机）、`--log <path>`、`--timeout <n>`；`--help`。
- 行为（两种模式）：
  1. **自带靶机**（给 `--image`）：用 `qemu-system-x86_64` 起 dev 镜像 + slirp `hostfwd`（:2222→:22、:5678→:5678），串口等 sshd 就绪（轮询 `nc -z 127.0.0.1 2222` 或串口 `sshd` 行），`scp -P 2222 -o StrictHostKeyChecking=no <binary> root@127.0.0.1:<dest>/`，`ssh -P 2222 ... chmod +x <dest>/<bin>`，随后 `ssh <cmd> <dest>/<bin>` 取目标机输出；打印 `DEPLOY_OK` + marker。
  2. **外部靶机**（不给 `--image`，已有 QEMU 在跑）：只做 scp/ssh 部署与执行，端口/用户由参数指定。
- 前置：目标 dev 镜像须含 `openssh-sshd`（否则 ssh 连接失败 → `DEPLOY_FAIL` + 提示先重建 dev 镜像）。
- 成功打印 `DEPLOY_OK` 与目标机输出中的 marker；失败 `DEPLOY_FAIL reason=...` 非 0。SSH 非交互凭据：debug-tweaks 空密码，用 `sshpass` 若可用，否则 `SSH_ASKPASS`（实现阶段探测；若均不可用，退化到 pexpect 驱动串口）。

### 3.3 `scripts/dev/gdb-connect.sh --target qemu --break <symbol>`

- 参数：`--target qemu`、`--break <symbol>`（默认 `yp_demo_main`）、`--gdb <path>`（默认 SDK 交叉 gdb）、`--binary <path>`（宿主带 `-g` 的 yp-demo）、`--host <h>`（默认 127.0.0.1）、`--port <p>`（默认 5678）、`--log <path>`；`--help`。
- 行为：非交互批处理 gdb：
  ```
  target remote <host>:<port>
  file <binary-with-symbols>
  break <symbol>
  continue
  bt
  list <symbol>
  detach / quit
  ```
  目标侧 gdbserver 由 `deploy-target.sh` 或脚本自身经 ssh 在目标机启动 `gdbserver :5678 <dest>/yp-demo`（等待连接模式）。
- 断言：gdb 输出含 `Breakpoint ...` + `yp_demo_main` → `GDB_BREAKPOINT_HIT`；`list` 输出含源码文件名/行号 → `SOURCE_LINE_OK`；二者缺一则 `GDB_FAIL reason=...` 非 0，并把 debuginfod/minidebuginfo 段标 `UNVERIFIED`。
- 严格不把 `gdbserver` 进程存在当 D-05 通过：必须断点命中 + 源码行定位都有真实输出。

### 3.4 配方与 kas 变更

- **`meta-yp-distro/recipes-core/images/yp-image-dev.bb`**：`IMAGE_INSTALL += " openssh-sshd openssh-sftp-server openssh-scp"`（为 deploy-target 提供 SSH/scp/SFTP 通道；gdbserver/gdb 已由 S1 `packagegroup-yp-devtools` 提供，不重复添加）。见 §3.4b 修正 1。
- **`kas/editions/dev.yml`**：追加 `EXTRA_IMAGE_FEATURES:append = " allow-empty-password empty-root-password allow-root-login"`（放开空密码 root SSH 登录，见 §3.4b 修正 2）；**不在本轮**全局启用 `DISTRO_FEATURES:append = " debuginfod minidebuginfo"`（全量重编 OOM 风险，plan §7 第 4 条）；以注释记录该配置入口与「留 M1.1」结论。
- **`docs/m0/variable-index.md`**：本 Stage 不新增受保护 bitbake 变量（`openssh-sshd` 是 `IMAGE_INSTALL` 值、`hostfwd` 是 QEMU 命令行参数，均非受保护变量），不改；`scripts/check-vars.sh` RULES 保持只读断言不变。

### 3.4b 实现阶段的设计修正（真实探测回填）

设计评审后实测发现三处必须修正（详见 RV-M1-S3 §3.1 B1–B6），已在实现提交中落地：

1. **SSH 组件从单 `openssh-sshd` 改为三项**：`openssh-sshd openssh-sftp-server openssh-scp`。只装 sshd 时，宿主 OpenSSH9 scp 默认走 SFTP 子系统→目标无 `sftp-server`→`Connection closed`；`-O` 旧协议又需目标 `scp` 命令。三者缺一不可。
2. **root 空密码需显式 `EXTRA_IMAGE_FEATURES`**：`debug-tweaks`（DISTRO_FEATURES）未自动放开三个 IMAGE_FEATURES，实测 root shadow=`root:*`、sshd 默认拒绝空密码。dev.yml 补 `EXTRA_IMAGE_FEATURES:append = " allow-empty-password empty-root-password allow-root-login"`（见 §3.4 dev.yml 变更）。
3. **QEMU 必须加 `ip=dhcp` 内核参数**：本镜像 `/etc/network/interfaces` 只有 lo，guest 无 eth0 IP 时 slirp hostfwd 转发到 guest:22/5678 失败（ssh banner 超时）。hostfwd 语法用双冒号 `tcp::<host>-:<guest>`（单冒号被 QEMU 8.2 拒）。
4. **gdb 批处理先 `file` 后 `target remote`**：反序会让 gdbserver 在 gdb 重读符号时 reset；去掉 nc 就绪探测（会消耗 gdbserver 一次 accept），固定 sleep 2；`set breakpoint pending off` 让坏符号快速失败。

### 3.5 `yp-demo` 样例（实现阶段生成，不入库二进制）

SDK 交叉 gcc 用 `-g -O0` 编译最小 C 程序：`yp_demo_main()` 打印 `YP_DEMO_MARKER` 后循环（便于 attach/断点），`main()` 调用它。源码与编译命令写入 RV 证据；二进制只在 `/tmp`/`/work`，不入库。

## 4. 失败模式与检测

| # | 失败模式 | 检测信号 | 处理 |
|---|---|---|---|
| F1 | dev 镜像无 sshd，SSH 部署连不上 | `ssh: connect to host ... port 2222: Connection refused` / `scp` 非 0 | 重建 dev 镜像加 `openssh-sshd`（本 Stage 配方变更）；仍失败开 ISS，不用「串口 echo」冒充 deploy-target |
| F2 | debug-tweaks 空密码被 openssh 拒绝 | `Permission denied` / `Password authentication failed` | 核对 `PermitEmptyPasswords`/`PermitRootLogin`；必要时用 `sshpass`/`SSH_ASKPASS`/pexpect；开 ISS 记录 |
| F3 | QEMU slirp hostfwd 不生效 | `nc -z 127.0.0.1 2222` 失败 / `ss -ltn` 无监听 | 核对 hostfwd 语法与 QEMU 版本（8.2.2 支持 `user,hostfwd`）；失败退到串口路径并如实记录，D-03 不宣称通过 |
| F4 | TCG 下 QEMU 起不来 / AVX invalid opcode | `trap ... vzeroupper` / 无 `login:` | 沿用 S0 的 `-cpu max` + `root=/dev/vda`；失败开 ISS |
| F5 | gdbserver 远程连不上 | `target remote: Connection refused` / gdb 超时 | 确认目标侧 gdbserver 在 `:<port>` 监听、hostfwd 映射正确；开 ISS，不把 gdbserver 进程存在当 D-05 通过 |
| F6 | 断点未命中 / 无源码行 | gdb 无 `Breakpoint` / `list` 无行号 | 用带 `-g` 二进制 + 本地源码路径；仍失败开 ISS，D-05-b 标 UNVERIFIED |
| F7 | minidebuginfo/debuginfod 未闭环 | 未启用 DISTRO_FEATURES / 无本地 debuginfod 服务 | 按 plan §7 标 UNVERIFIED，D-05 不宣称全通过，留 M1.1；不伪造证据 |
| F8 | dev 镜像重建 OOM | `Killed` / rc 137 / `memory.max` 触顶 | 用 6/-j2 overlay（不入库），记录峰值；标 RESOURCE_PARTIAL，不写「已通过」 |
| F9 | 校验脚本漂移 | `gate.sh` / `check-vars.sh` 非 0 | 新增脚本不改受保护变量行；复跑 drift=0；`bash -n` 全通过 |

## 5. 验收命令与期望输出

```bash
# 0) dev 镜像重建（加 openssh-sshd，增量；必要时 6/-j2 overlay）
docker exec -w /work/s2build yp-m1-build \
  kas build kas/yp.yml:kas/editions/dev.yml[:<lowconc overlay>]
# 期望：BUILD_RC=0（或如实记录客户端收尾 + 产物落盘）；新 ext4 含 /usr/sbin/sshd

# 1) 编译 yp-demo（SDK 交叉 gcc -g -O0）
source /work/yp-sdk-test/environment-setup-* && $CC -g -O0 -o /tmp/yp-demo yp-demo.c

# 2) 部署 + 目标机 marker
bash scripts/dev/deploy-target.sh --target qemu --image <dev.ext4> \
  --binary /tmp/yp-demo --log /tmp/s3-deploy.log --timeout 180
# 期望：DEPLOY_OK ...；目标机输出含 YP_DEMO_MARKER

# 3) gdbserver 远程断点 + 源码行
bash scripts/dev/gdb-connect.sh --target qemu --break yp_demo_main \
  --binary /tmp/yp-demo --log /tmp/s3-gdb.log
# 期望：GDB_BREAKPOINT_HIT；SOURCE_LINE_OK；minidebuginfo/debuginfod: UNVERIFIED

# 4) 门禁
bash -n scripts/dev/*.sh; bash scripts/gate.sh; bash scripts/check-vars.sh
```

**证据要求**：新 dev 镜像含 sshd 的 `debugfs` 输出；`deploy-target.sh` 原始输出（`DEPLOY_OK` + marker + scp/ssh 行）；`gdb-connect.sh` 原始输出（`GDB_BREAKPOINT_HIT` + `list` 源实行 + `Breakpoint` 行）；QEMU 命令与 hostfwd 参数、TCG 口径、实际 `nproc`/`MemTotal`；重建耗时与并发口径（`RESOURCE_PARTIAL`）。任何未跑命令在 RV 写 `UNVERIFIED`，不写「已通过」。debuginfod/minidebuginfo 必须明确标 UNVERIFIED（plan §7）。

## 6. 回滚

删除 `scripts/dev/deploy-target.sh`、`scripts/dev/gdb-connect.sh`，撤销 `yp-image-dev.bb` 的 `openssh-sshd` 一行，删除本文/评审文档即可；不改 base.yml、不改 M0 文件/配置/tag、不建 M2；重建的 dev 镜像、yp-demo、QEMU 日志均在 `/work`/`/tmp`，不在仓库回滚范围，可按需删除。无跨 Stage 影响（S0/S1/S2 脚本与证据不动）。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建 S3 deploy-target 与调试链路设计；含「dev 镜像无 sshd→补 openssh-sshd」「SSH/slirp 拓扑」「gdbserver 远程断点 + 源码行」「D-05 三层分档、debuginfod/minidebuginfo 标 UNVERIFIED 留 M1.1」的真实探测结论与失败模式 | zeek.zhao |
