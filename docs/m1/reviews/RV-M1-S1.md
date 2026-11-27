# YP-M1-RV-002 · M1-S1 dev/prod 镜像与三个包组评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-002 |
| 版本 | v1.1 |
| 评审对象 | YP-M1-S1 实现（三包组 + dev/prod 镜像 + kas dev 配置）；设计 DES-002 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-27 |
| 关联 | `docs/m1/plan.md` §M1-S1；`docs/m1/design/S1-dev-prod-images.md`（DES-002）；S0=`2501402` |
| 结论 | S1 通过（Q1–Q4 + R1–R4）：dev/prod 镜像可构建、dev 带全部目标调试工具、prod 无残留、dev sstate 隔离、GATE/VARS 绿；标注 RESOURCE_PARTIAL（嵌套沙箱 OOM，降并发后成功）。D-05 远程断点属 S3 未验证 |

## 1. 四问自评

**Q1 覆盖需求**：S1 目标「dev 镜像有工具、prod 镜像无残留」由两个镜像配方 + 三个包组覆盖；D-04（三包组存在、dev 有工具/prod 无残留）与 D-01 目标侧（gdbserver/perf/strace/trace-cmd 可执行）逐条落到 `RDEPENDS` 与验收 grep；缓存按 edition 隔离（plan §3.3）落到 dev.yml 的 `SSTATE_DIR`。明确不做 eSDK(S2)/deploy/gdb(S3)/CI(S4)/tag，不越界。D-01 宿主层按 §3.1 声明归 S2，不在此冒领。✅

**Q2 失败模式列全且检测可执行**：设计 §4 列 8 类失败（配方缺层、edition 多 target、缓存串写、prod 误带工具、dev 缺工具、源码拉取、首编超时、脚本漂移），每类给检测信号与处理。F1/F2/F3 均为设计前实测发现（见 §2），非理论推测。✅

**Q3 验收可执行**：验收命令全部具体可执行（`kas build`、`oe-pkgdata-util list-pkg` grep 带 rc、QEMU `which`、sstate 目录断言、`gate.sh`/`check-vars.sh`），dev 命中/prod 不命中的期望明确（DEV_RC=0 / PROD_RC=1）；用已有 5.8G DL + 4.7G sstate，不下载 11 GiB。未执行的命令承诺写 `UNVERIFIED`，不写「已通过」。✅

**Q4 回滚可行**：删除 5 个配方 + 撤销 dev.yml/variable-index 增补即可；不改 base.yml、M0 文件/配置/tag；dev sstate 目录属构建产物不在仓库回滚范围；无跨 Stage 影响。✅

## 2. 设计阶段探测证据（真实，容器内 `kas checkout` 固定 commit）

Builder 容器 `yp-m1-build`（jenkins/uid1000，kas 5.5），资源口径：宿主 `nproc=32` `MemTotal=129308484 kB`；docker `NCPU=32 MemTotal=132411887616`；容器 `NanoCpus=0 Memory=0 CpuQuota=0`（无资源限制）；已记录。

- `kas checkout kas/yp.yml:editions/dev.yml` → 4 个 repo（openembedded-core/bitbake/meta-yocto/meta-openembedded）均 checkout 到 base.yml pin 的 commit，`CHECKOUT_RC=0`。
- 工具配方定位：`gdb_17.2.bb`（`PACKAGES =+ "gdbserver"`、`FILES:gdbserver=${bindir}/gdbserver`）、`perf.bb`、`strace_6.19.bb`、`quilt_0.69.bb` 在 openembedded-core `meta`；`trace-cmd_3.1.5.bb` 在 meta-openembedded `meta-oe`。两者均被 base.yml 加载 → 无需新增层。
- image 基类：`core-image-minimal.bb` 位于 `openembedded-core/meta/recipes-core/images/`，`inherit core-image`，`IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL}"`。
- edition 多 target 负向：dev.yml 追加 `targets:` 列表 → `kas dump` 报配置校验错误、`DUMP_RC=2`（kas 5.5 顶层 schema 不接受 `targets`）。
- edition 单 target 正向：dev.yml 追加 `target: yp-image-dev` → `kas dump` 输出 `target: yp-image-dev`，覆盖生效。
- packagegroup 写法参考：`openembedded-core/meta/recipes-core/packagegroups/packagegroup-core-buildessential.bb`（`inherit packagegroup` + `RDEPENDS:packagegroup-core-buildessential`）。
- DL_DIR 现状：`gdb` 源码 `git2/sourceware.org.git.binutils-gdb.git.done`、`quilt-0.69.tar.gz` 在缓存；`strace`/`trace-cmd` 源码未见（dev 允许联网拉取）。

以上为设计输入探测；构建/清单/QEMU 实测证据待实现提交后在 §3 回填。

## 3. 实测证据（实现提交后回填，宿主 builder 容器 TCG/无 KVM 与构建无关）

构建环境：`yp-m1-build` 容器，`nproc=32`、`MemTotal=129308484 kB`、Docker daemon NCPU=32/MemTotal=132411887616、容器 `NanoCpus=0 Memory=0 CpuQuota=0`；容器 cgroup `memory.max=max`、`memory.peak=6.9G`。**本机为嵌套沙箱，宿主 shell cgroup memory.max=8G，32×16 并发全量编译交叉工具链触发 OOM（ISS-M1-002），故构建用既有 `BB_NUMBER_THREADS` 机制临时降到 6 / -j2（本地 overlay，不入库）**。结论标注 **RESOURCE_PARTIAL**：未以 32c/128G full-quota 完成，但按实际全量资源（受嵌套沙箱内存上限约束）构建成功。

### 3.1 构建过程（三次尝试，如实）

| 尝试 | 命令 | 结果 |
|---|---|---|
| 1 | `kas build ...dev.yml`（32/-j16 默认并发） | 失败：llvm do_unpack 进程被 SIGKILL → tar EOF（BUILD_RC=2）；tarball 经核验完整（`xz -t` rc=0、大小=上游 Content-Length），系 OOM |
| 2 | 同命令重试（仍 32/-j16） | 越过 llvm，失败于 gcc-cross do_compile `genautomata` Killed / Error 137（OOM，BUILD_RC=2） |
| 3 | `kas build ...dev.yml:/work/s1-lowconc.yml`（6/-j2，本地 overlay） | `do_image_ext4: Succeeded`，产出 dev ext4；但 `kas build` 客户端在 do_image_ext4 后卡住不写 BUILD_RC（嵌套沙箱 bitbake server/client 收尾问题，ISS-M1-002 P3）。终止客户端，以已落盘产物验收 |
| prod-1 | 同一 build 目录 `--target yp-image-prod` | 失败：`basehash value changed ... metadata is not deterministic` + `No such task: do_rm_work`（dev/prod 的 INHERIT rm_work 差异污染同目录 datastore，ISS-M1-002 P4） |
| prod-2 | 全新独立目录 `/work/s1build-prod` + 6/-j2 overlay | **BUILD_RC=0**：`Attempted 4647 tasks of which 4318 didn't need to be rerun and all succeeded`；sstate `Wanted 2318 Local 2286 Missed 32 (98% match)`；无 OOM |

### 3.2 镜像产物（真实）

```
dev: yp-image-dev-qemux86-64.rootfs-20261127125613.ext4   152M  Linux rev 1.0 ext4 filesystem
     （do_image_ext4 Succeeded；位于 deploy-yp-image-dev-image-complete/）
prod:yp-image-prod-qemux86-64.rootfs-20261127155146.ext4    70M  Linux rev 1.0 ext4 filesystem
     （BUILD_RC=0；位于标准 deploy/images/qemux86-64/）
```

dev 独立 sstate：`/work/sstate/dev` 存在，7189 个对象；prod 用 M0 共享 `/work/sstate`（98% sstate 命中），**dev 缓存未写入 prod 路径 plan §3.3 成立**。

### 3.3 D-04 dev/prod 负向对照（manifest + 镜像内二进制，真实）

`oe-pkgdata-util` 在 oe-core 6.0（pin commit）中**没有 `list-pkg` 子命令**（DES-002 §5 该命令不可执行，以镜像 manifest + ext4 内 `/usr/bin` 二进制替代，等价且更可复现；见下方证据）。

| 工具 | dev manifest | prod manifest | dev `/usr/bin` | prod `/usr/bin` |
|---|---|---|---|---|
| gdbserver | YES | no | 0755 672000B | 不存在 |
| perf | YES | no | 0755 3997560B | 不存在 |
| strace | YES | no | 0755 2054600B | 不存在 |
| trace-cmd | YES | no | 0755 425256B | 不存在 |
| quilt | YES | no | 0755 3164B | 不存在 |
| gdb | YES | no | 0755 12277944B | 不存在 |

- dev manifest `grep -cE '^(gdbserver|perf|strace|trace-cmd|quilt|gdb)( |$)'` → **6**。
- prod 负向 `grep -qE '^(gdbserver|perf|strace|trace-cmd)( |$)' <prod.manifest>` → **rc=1**（无命中）；`debugfs stat /usr/bin/gdbserver <prod.ext4>` 无输出。
- dev `/usr/bin` grep 六工具全部命中且 Mode 0755；prod `/usr/bin` grep 同集合 → **rc=1**。

> **QEMU 内 `which` 说明**：以镜像 `/usr/bin` 下可执行文件存在性 + manifest 双重取证（`which` 语义即 PATH 查找可执行文件），等价且可复现；交互式 QEMU `which` 因需登录 shell 交互，本轮标 `UNVERIFIED`（非阻断：D-04 结论由上述两项证据支撑）。dev ext4 内 `/boot/bzImage-6.18.52-yocto-standard` 存在（14M），S0 的 qemu-run.sh 可启动该镜像（S3 deploy/gdb 阶段实际使用）。

### 3.4 门禁与卫生

`bash scripts/gate.sh` → **GATE_PASS**；`bash scripts/check-vars.sh` → **VARS_OK checked=36 drift=0**；提交身份 `zeek.zhao <zeek.zhao@foxmail.com>`（本地 `-c` 指定，不改 git config）；无 AI 署名、无 token、无大二进制入库（ext4/构建产物均在 /work 与 /tmp，不在仓库）。

### 3.5 结论

**S1 通过（D-04、D-01 目标侧）**：三个包组 + dev/prod 镜像可构建；dev 带全部目标工具、prod 无残留；dev 缓存按 edition 隔离；GATE/VARS 绿。标注 `RESOURCE_PARTIAL`（嵌套沙箱 OOM，降并发后成功，非 full-quota）。D-05 gdbserver 远程断点、debugging 链路属 S3，本 Stage 未验证。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建：S1 设计四问评审 + 设计阶段真实探测证据（层/target 覆盖/packagegroup 写法）；实测待回填 | zeek.zhao |
| v1.1 | 2026-11-27 | 回填实测：dev/prod 镜像产物、D-04 负向对照（manifest+二进制）、dev sstate 隔离、GATE/VARS；记录 ISS-M1-002 三次构建障碍与 RESOURCE_PARTIAL；S1 通过 | zeek.zhao |
