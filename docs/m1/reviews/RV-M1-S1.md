# YP-M1-RV-002 · M1-S1 dev/prod 镜像与三个包组评审

| 项 | 值 |
|---|---|
| 文档编号 | YP-M1-RV-002 |
| 版本 | v1.0 |
| 评审对象 | YP-M1-S1 设计（DES-002）；实现（配方/kas）待评审后单独提交 |
| 评审人 | zeek.zhao |
| 评审日期 | 2026-11-27 |
| 关联 | `docs/m1/plan.md` §M1-S1；`docs/m1/design/S1-dev-prod-images.md`（DES-002）；S0=`2501402` |
| 结论 | 设计通过（Q1–Q4）；实测构建与负向对照待实现提交后回填，**当前不宣称 S1 已通过** |

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

## 3. 实测证据（实现提交后回填）

> 待回填：`kas build` dev/prod 产物、dev/prod 包清单 grep 与 rc、QEMU 内 which 输出、dev sstate 独立目录证据、构建耗时、门禁输出。任何未执行命令写 `UNVERIFIED`。

## 4. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-27 | 新建：S1 设计四问评审 + 设计阶段真实探测证据（层/targe 覆盖/packagegroup 写法）；实测待回填 | zeek.zhao |
