# YP-M1-RV-004 · M1-S3 deploy-target 与调试链路评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-004 |
| 版本 | v1.1（设计评审 + 实测证据回填） |
| 评审对象 | YP-M1-S3 实现（deploy-target.sh + gdb-connect.sh + yp-image-dev.bb 加 sshd/sftp-server/scp）；设计 DES-004 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-28 |
| 关联 | `docs/m1/plan.md` §M1-S3 §3.1 §7；`docs/m1/design/S3-deploy-debug.md`（DES-004）；S2=`a441f91`；设计评审=`6aa1cfe` |
| 结论 | S3 通过（Q1–Q4 + 实测）：D-03 `DEPLOY_OK`+目标机 `YP_DEMO_MARKER`；D-05-a/b `GDB_BREAKPOINT_HIT`+`SOURCE_LINE_OK`；dev 镜像重建 BUILD_RC=0（仅增量）；标注 RESOURCE_PARTIAL。D-05-c（debuginfod/minidebuginfo）如实 UNVERIFIED、留 M1.1（plan §7 第 4 条）；devshell 交互 UNVERIFIED |

## 1. 四问自评

**Q1 覆盖需求**：S3 目标「一条命令部署 + gdbserver 远程断点 + 源码行定位」由 `deploy-target.sh`（D-03：scp/ssh 部署 + 目标机 marker → `DEPLOY_OK`）与 `gdb-connect.sh`（D-05-a/b：断点命中 + 源码行 → `GDB_BREAKPOINT_HIT`/`SOURCE_LINE_OK`）逐项覆盖；`yp-image-dev` 补 `openssh-sshd` 打通 SSH 部署通道，gdbserver/gdb 复用 S1 包组。D-05-c（debuginfod/minidebuginfo）按 plan §7 分层标 UNVERIFIED、留 M1.1，不冒充全通过。明确不做 CI/tag（S4/S5）、不改 M0、不建 M2，不越界。✅

**Q2 失败模式列全且检测可执行**：设计 §4 列 9 类失败（无 sshd、空密码被拒、hostfwd 不生效、TCG 启动、gdbserver 连不上、断点/源码行缺失、debuginfod 未闭环、重建 OOM、脚本漂移），每类给检测信号与处理。F1（dev 镜像无 sshd）为设计前 `debugfs` 实测发现——这是本 Stage 最关键的真实障碍，直接决定配方必须加 sshd，非理论推测；F8（OOM）来自 S1/S2 的 ISS-M1-002/003 真实教训。✅

**Q3 验收可执行**：验收命令全部具体可执行（`kas build`、`$CC -g`、`deploy-target.sh`、`gdb-connect.sh`、`bash -n`/`gate`/`vars`），期望输出明确（`DEPLOY_OK`+marker、`GDB_BREAKPOINT_HIT`+`SOURCE_LINE_OK`、rc）。SSH 凭据方式（debug-tweaks 空密码 + sshpass/SSH_ASKPASS/pexpect 兜底）列明探测路径；未跑命令写 UNVERIFIED，debuginfod/minidebuginfo 强制标 UNVERIFIED。✅

**Q4 回滚可行**：删除两个脚本 + 撤销 `yp-image-dev.bb` 加 sshd 的一行 + 删除设计/评审文档即可；不改 base.yml/M0 文件/配置/tag、不建 M2；重建镜像、yp-demo、QEMU 日志均在 /work`/`/tmp，不在仓库回滚范围；无跨 Stage 影响。✅

## 2. 设计阶段探测证据（真实，容器内 debugfs + 宿主命令 + oe-core 源码）

容器 `yp-m1-build`（重启后缓存完整：dev sstate 9317 对象、`/work/yp-sdk-test` eSDK 在、/work/s2build dev 镜像在）；宿主 qemu 8.2.2（TCG）、ssh/scp、pexpect 4.9.0 可用。

- **dev 镜像 `debugfs` 实测**：`/usr/bin/gdb`（12277944B）、`/usr/bin/gdbserver`（672000B）均 mode 100755；`/usr/sbin` 无 sshd/dropbear（F1 来源）；`/etc/passwd` root=`*`；无现成 demo 二进制。→ S1 的 gdbserver 可复用，但部署链路必须补 openssh-sshd。
- **eSDK 实测**：`x86_64-poky-linux-gdb` = GNU gdb 17.2；`x86_64-poky-linux-gcc` 在同目录，可交叉编译带 `-g` 的 yp-demo。
- **deploy.py 实测**：`scp`+`ssh 'sh <script>'` 实现部署；参数 `user@host[:destdir]`、`-P/--port`、`-c`、`-i` 齐全 → 部署链路 = SSH/scp，需目标 sshd + slirp hostfwd。
- **minidebuginfo/debuginfod 实测**：`package.bbclass:237` 按 `DISTRO_FEATURES` 含 minidebuginfo 注入 xz-native 依赖；`package.py:888 inject_minidebuginfo()` 把 debug 信息压入 `.gnu_debugdata`；`bitbake.conf:919` 与 `gdb-common.inc`、`scripts/oe-debuginfod` 构成 debuginfod 侧。代码路径真实，但启用触发全量重编（S2 实测 3h+ 且归档 OOM），本轮标 UNVERIFIED（plan §7 第 4 条）。
- **kas overlay 实测**：`kas dump` 解析 `dev.yml:/work/s3probe.yml`（含 debuginfod/minidebuginfo/sshd）成功（KAS_DUMP_OK），证明配置写法有效；是否启用见实现阶段 dry-run 决定。
- **资源口径**：宿主标称 32c/128GiB、容器三项 0/0/0；嵌套沙箱 cgroup `memory.max=8G`（S1/S2 OOM 根因），延续 `RESOURCE_PARTIAL`。

以上为设计输入探测；脚本/配方实现、dev 镜像重建、部署与调试实测待实现提交后在 §3 回填。

## 3. 实测证据（实现提交后回填）

构建环境：`yp-m1-build` 容器（jenkins/uid1000），dev edition 独立目录 `/work/s2build`，`SSTATE_DIR=/work/sstate/dev`；宿主 qemu 8.2.2（TCG，无 `/dev/kvm`）、原生 gdb 15.0.50、gcc 12、ssh/scp、pexpect 4.9.0。宿主标称 `nproc=32` `MemTotal≈128GiB`、容器三项 0/0/0；嵌套沙箱 cgroup `memory.max=8G`（S1/S2 OOM 根因）。用低并发 overlay（`BB_NUMBER_THREADS=6`、`PARALLEL_MAKE=-j2`、`BB_PARALLEL_PARSE=0`，本地不入库）抑制解析/编译 OOM。结论标注 **RESOURCE_PARTIAL**。

### 3.1 设计阶段新发现的真实障碍与修复（均非理论推测）

| # | 障碍 | 实测信号 | 修复 |
|---|---|---|---|
| B1 | dev 镜像只有 sshd，缺 sftp-server/scp | scp SFTP 模式 `Subsystem sftp ... Connection closed`；`-O` 模式目标 `sh: scp: command not found` | `yp-image-dev.bb` 的 `IMAGE_INSTALL` 补 `openssh-sshd openssh-sftp-server openssh-scp` 三项（缺一不可） |
| B2 | debug-tweaks 未放开 root 空密码 SSH | 首版 root shadow=`root:*`、`sshd_config` 默认 `PermitRootLogin prohibit-password`/`PermitEmptyPasswords no` | dev.yml 显式 `EXTRA_IMAGE_FEATURES:append = " allow-empty-password empty-root-password allow-root-login"`；重建后 shadow=`root::15069`、`PermitRootLogin yes`/`PermitEmptyPasswords yes` |
| B3 | guest 无 eth0 IP，slirp hostfwd 转发失败 | 串口 `ip addr` 仅 `127.0.0.1 lo`；ssh banner 超时 | QEMU `-append` 加内核参数 `ip=dhcp`（slirp 分 10.0.2.15），不改镜像网络配置 |
| B4 | hostfwd 语法 | 单冒号 `tcp:5678-:5678` 被 QEMU 8.2 拒：`Invalid host forwarding rule (Bad host address)` | 双冒号 `tcp::5678-:5678`（省略 host addr） |
| B5 | nc 探测消耗 gdbserver 一次 accept | nc -z 后 gdb 连接 `Connection reset by peer` | 去掉 nc 探测，固定 sleep 2 让 gdbserver 稳定监听 |
| B6 | gdb 批处理顺序错误 | 先 `target remote` 再 `file` → gdbserver reset | 先 `file` 加载本地 `-g` 符号，再 `target remote`；加 `set sysroot /`；不存在的符号用 `set breakpoint pending off` 快速失败 |

### 3.2 dev 镜像重建（加 SSH 三组件 + 空密码 root）

| 尝试 | 命令 | 结果 |
|---|---|---|
| 1 | `kas build ...dev.yml:/work/s3sshd.yml:/work/s1-lowconc.yml --target yp-image-dev`（仅加 sshd） | BUILD_RC=0，`Attempted 4796 tasks of which 4759 didn't need to be rerun and all succeeded`（openssh 首次编译 37 任务）；产物含 `/usr/sbin/sshd`，但缺 sftp-server/scp、root 密码锁定（B1/B2） |
| 2 | `...:/work/s3login.yml`（加 sshd + EXTRA_IMAGE_FEATURES，未禁并行解析） | 失败：`ParseError: Not all recipes parsed, parser thread killed/died? (0 1908 of 2007)`（8G cgroup 并行解析 OOM）；overlay 加 `BB_PARALLEL_PARSE=0` 修复 |
| 3 | `...:/work/s3login.yml`（含 `BB_PARALLEL_PARSE=0`） | BUILD_RC=0，`4784 didn't need to be rerun`；shadow=`root::15069`、`PermitRootLogin yes`/`PermitEmptyPasswords yes` |
| 4 | `...:/work/s3login.yml`（再加 sftp-server+scp） | **BUILD_RC=0**，`Attempted 4796 tasks of which 4782 didn't need to be rerun and all succeeded`；debugfs 确认 `/usr/libexec/sftp-server`、`/usr/bin/scp`、`/usr/sbin/sshd` 全 FOUND |

- 最终产物：`yp-image-dev-qemux86-64.rootfs-20261128092134.ext4`（160M，ext4）；dev sstate 仍 `/work/sstate/dev`，未写 prod 路径（plan §3.3 保持）。
- 并发口径 6/-j2、并行解析关闭；耗时约 2 分钟/次增量；标 `RESOURCE_PARTIAL`，非 full-quota。

### 3.3 D-03 deploy-target（真实）

命令：`bash scripts/dev/deploy-target.sh --target qemu --image <dev.ext4> --binary <yp-demo-static> --log <serial.log> --timeout 90 --keep-target --pidfile <pid>`

```
SSHD_READY elapsed=10s
=== scp <yp-demo-static> -> root@127.0.0.1:/usr/bin/yp-demo-static ===
SCP_OK
=== chmod + execute on target ===
YP_DEMO_MARKER
TARGET_MARKER_OK marker=YP_DEMO_MARKER
TARGET_PIDFILE=<pid> pid=104720
DEPLOY_OK target=root@127.0.0.1 port=2222 binary=/usr/bin/yp-demo-static
```

- QEMU 命令：`-m 512 -smp 2 -nographic -no-reboot -cpu max -kernel <extracted bzImage> -append 'console=ttyS0 root=/dev/vda rw init=/sbin/init ip=dhcp' -netdev user,id=n0,hostfwd=tcp::2222-:22,hostfwd=tcp::5678-:5678 -device virtio-net-pci,netdev=n0`；TCG（无 KVM），串口落 `<serial.log>`。
- yp-demo：宿主 gcc `-g -O0 -static` 编译（静态规避目标 glibc 版本差异），`yp_demo_main()` 打印 `YP_DEMO_MARKER`；`YP_DEMO_STAY=1` 时循环（gdb 模式），否则打印后退出（deploy 模式）。源码与二进制在 `/tmp`/artifact，不入库。
- 负向：`--binary /tmp/no-such-bin` → `DEPLOY_FAIL reason=binary not found`（rc=1）；`--target docker` → `DEPLOY_FAIL reason=unsupported --target: docker`（rc=1）。

### 3.4 D-05-a/b gdbserver 远程断点 + 源码行（真实）

命令：`bash scripts/dev/gdb-connect.sh --target qemu --break yp_demo_main --binary <yp-demo-static> --remote-bin /usr/bin/yp-demo-static --log <log>`

```
=== start gdbserver on target :5678 ===
GDBSERVER_STARTED
GDB=/usr/bin/gdb   (GNU gdb 15.0.50；SDK 交叉 gdb 为 uninative 动态链接，宿主不可直接跑，回退宿主 gdb)
Breakpoint 1 at 0x40190d: file .../yp-demo.c, line 10.
Breakpoint 1, yp_demo_main () at .../yp-demo.c:10
10	    printf("YP_DEMO_MARKER\n");
#0  yp_demo_main () at .../yp-demo.c:10
#1  0x0000000000401969 in main () at .../yp-demo.c:23
GDB_BREAKPOINT_HIT symbol=yp_demo_main
SOURCE_LINE_OK
minidebuginfo/debuginfod: UNVERIFIED (plan §7; D-05-c deferred to M1.1)
GDB_CONNECT_OK break=yp_demo_main host=127.0.0.1:5678
```

- 目标侧 gdbserver 是 dev 镜像自带（D-05-a，S1 包组产物），宿主 gdb 通过 hostfwd `tcp::5678-:5678` 连接；断点命中 + `list` 源码行均为真实输出。
- 负向：`--break no_such_symbol` → `Function "no_such_symbol" not defined.` + `GDB_FAIL reason=breakpoint not hit`（rc=1，靠 `set breakpoint pending off` 快速失败，不挂起）。

### 3.5 D-05-c debuginfod/minidebuginfo（如实 UNVERIFIED）

`minidebuginfo`/`debuginfod` 是 `DISTRO_FEATURES`，启用会改变全镜像 `do_package` hash → 全量重编（S2 实测首编 3h+ 且归档 xz OOM，本沙箱 8G cgroup）。按 plan §7 第 4 条确认项，本轮**不启用**、标 `UNVERIFIED`，D-05 整体不宣称全 P1，留 M1.1 补；不把 gdbserver 通过写成 D-05 全通过。DES-004 §2.3 已记录 oe-core 真实代码路径（package.bbclass:237 / package.py:888 inject_minidebuginfo / oe-debuginfod），非凭空断言。

### 3.6 门禁与卫生

`bash -n scripts/dev/*.sh` → SYNTAX_OK；`bash scripts/gate.sh` → **GATE_PASS**；`bash scripts/check-vars.sh` → **VARS_OK checked=36 drift=0**；提交身份 `zeek.zhao <zeek.zhao@foxmail.com>`（一次性 `-c`，未写 git config）；无 token、无大二进制入库（dev 镜像 160M、yp-demo、QEMU 日志均在 /work`/`/tmp`/artifact，不在仓库）。`devshell` 交互 → `UNVERIFIED`（非 pty/CI 不跑，符合 plan）。配方改动仅 `yp-image-dev.bb` 的 `IMAGE_INSTALL` 一行 + dev.yml 的 `EXTRA_IMAGE_FEATURES` 一行，回滚面最小。

### 3.7 结论与 CI 状态

**S3 通过（D-03、D-05-a/b）**：deploy-target 一条命令部署 + 目标机 marker、gdbserver 远程断点命中 + 源码行定位均真实跑通；dev 镜像重建 BUILD_RC=0。`RESOURCE_PARTIAL`（8G 沙箱，6/-j2 + 禁并行解析）。D-05-c（debuginfod/minidebuginfo）与 devshell 交互标 UNVERIFIED，D-05 不宣称全 P1（plan §7）。CI：按 head_sha 查询 GitHub Actions 见 §3.8。

### 3.8 CI 状态（如实）

S3 设计评审（`6aa1cfe`）与实现回填提交 push 到 `feat-m1-dev-platform` 后，查询 GitHub Actions `total_count=0`——gate/publish workflow 的 push 分支限制为 `feat-m0*`/`release-m0*`，本分支 `feat-m1-*` 不匹配（与 S0/S1/S2 同一口径）。不为让 CI 跑而改 workflow paths（前序硬边界），以本地 GATE_PASS/VARS_OK 为质量证据，远端 CI 记「未触发（分支不匹配）」，不冒充 success。push 凭据经一次性环境变量与 git 参数传递，未写 git config/仓库、未打印 token。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S3 设计四问评审 + 设计阶段真实探测证据（dev 无 sshd→补 sshd、SSH/slirp 拓扑、gdbserver+源码行、D-05 三层分档、debuginfod/minidebuginfo 标 UNVERIFIED）；实测待回填 | zeek.zhao |
| v1.1 | 2026-11-28 | 回填实测：dev 镜像重建 BUILD_RC=0（sshd/sftp-server/scp + 空密码 root，4 次迭代修复 B1–B4）；D-03 DEPLOY_OK+YP_DEMO_MARKER；D-05-a/b GDB_BREAKPOINT_HIT+SOURCE_LINE_OK（修复 B5 nc 消耗 accept、B6 gdb 批处理顺序）；负向路径非 0；debuginfod/minidebuginfo 标 UNVERIFIED 留 M1.1；RESOURCE_PARTIAL；S3 通过 | zeek.zhao |
