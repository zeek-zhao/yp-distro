# YP-M1-RV-004 · M1-S3 deploy-target 与调试链路评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-004 |
| 版本 | v1.0（设计评审；实测证据待实现提交后回填 v1.1） |
| 评审对象 | YP-M1-S3 实现（deploy-target.sh + gdb-connect.sh + yp-image-dev.bb 加 sshd）；设计 DES-004 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-28 |
| 关联 | `docs/m1/plan.md` §M1-S3 §3.1 §7；`docs/m1/design/S3-deploy-debug.md`（DES-004）；S2=`a441f91` |
| 结论 | 待实现回填（设计阶段 Q1–Q4 通过；D-03/D-05 实测证据、debuginfod/minidebuginfo 分层口径在实现后回填） |

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

## 3. 实测证据（实现提交后回填 v1.1）

待回填：新 dev 镜像含 sshd 的 debugfs 输出；`DEPLOY_OK` + 目标机 `YP_DEMO_MARKER` 原始输出；`GDB_BREAKPOINT_HIT` + `SOURCE_LINE_OK` 原始输出；QEMU 命令/hostfwd/TCG/资源实测；重建耗时与并发口径；debuginfod/minidebuginfo 的 UNVERIFIED 记录；门禁 GATE_PASS/VARS_OK；CI 状态（如实）。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-28 | 新建：S3 设计四问评审 + 设计阶段真实探测证据（dev 无 sshd→补 sshd、SSH/slirp 拓扑、gdbserver+源码行、D-05 三层分档、debuginfod/minidebuginfo 标 UNVERIFIED）；实测待回填 | zeek.zhao |
