# 构建环境：并行度、磁盘闸、buildhistory、源码镜像包

这四组配置都在 `kas/base.yml` 的 `base:` 段，四个 release 共用。**现行保障
范围只有 wrynose 6.0**（`config/supported-releases.txt`），涉及其余三版差异的
段落（如 §3 磁盘闸对 dunfell 的兼容限制）描述的是冻结配置的历史事实，保留作
参考。它们不改变产物内容，
但决定「构建会不会把机器打爆 / 数据能不能回溯 / 断网能不能重建」。

改动它们**不会触发重编译**（实测：加完全部四项，scarthgap general 仍是
`Attempted 4551 tasks of which 4548 didn't need to be rerun`），也就是说写错了
构建照样成功、只是悄悄不生效。所以每一项都由 `scripts/kas-verify.py::check_build_env`
和 `tests/bats/05_kas.bats` 双向兜住。

## 1. 并行度：min(核数, 20)

```bitbake
BB_NUMBER_THREADS = "${@min(oe.utils.cpu_count(), 20)}"
PARALLEL_MAKE = "-j ${@min(oe.utils.cpu_count(), 20)}"
```

**为什么不是 `?=`**：`bitbake.conf` 自己就写着
`BB_NUMBER_THREADS ?= "${@oe.utils.cpu_count()}"`，而 `bitbake.conf` 在
`local.conf` **之前**解析。在 `local.conf` 里再写 `?=` 属于「变量已有值」，
不会覆盖，等于没写。这是 poky 的 `local.conf.sample` 注释里那两行最容易踩的坑。

**为什么不是写死 20**：构建机是 32 核，别的机器不是。`min()` 保证小机器按实际核数跑，
大机器封顶 20 以免和同机的其他任务抢内存（构建机上 124GB 内存常年有其他构建）。

**改上限**：两个 20 必须一起改，校验器会断言它们相等。
按经验 `BB_NUMBER_THREADS × PARALLEL_MAKE` 不超过核数时比较稳，超过就得看内存。

验证：

```bash
bash scripts/dev.sh bash -lc 'cd /work/work/kas-scarthgap-general/build && \
    . ../poky/oe-init-build-env . >/dev/null && \
    bitbake -e base-files | grep -E "^BB_NUMBER_THREADS=|^PARALLEL_MAKE="'
# BB_NUMBER_THREADS="20"
# PARALLEL_MAKE="-j 20"
```

## 2. 磁盘闸：STOPTASKS + ABORT 两档

```bitbake
BB_DISKMON_DIRS = "STOPTASKS,${TMPDIR},1G,100K STOPTASKS,${DL_DIR},1G,100K \
STOPTASKS,${SSTATE_DIR},1G,100K STOPTASKS,/tmp,100M,100K \
ABORT,${TMPDIR},100M,1K ABORT,${DL_DIR},100M,1K ABORT,${SSTATE_DIR},100M,1K ABORT,/tmp,10M,1K"
```

（`local.conf` 里写在一行，这里为可读性折行。）

| 档位 | 触发 | 行为 |
|---|---|---|
| `STOPTASKS` | 剩余 < 1G 或 inode < 100K | 停派新任务，等在跑的收尾 |
| `ABORT` | 剩余 < 100M 或 inode < 1K | 立即中止整个构建 |

阈值刻意压得很低 —— 这是「别把共享盘写满」的最后一道闸，不是水位管理。
日常拦截看 `scripts/lib/disk-guard.sh` 的 85% 门禁，那个才会在构建开始前就拒绝。

只写 `STOPTASKS` 会在低水位无限等（永远派不出新任务，也不报错）；
只写 `ABORT` 会一有压力就整锅端。两档都要有。

**第二档为什么不是 `HALT`**：`HALT` 是 bitbake 4.0 才加进 DiskSpaceMonitor 的动作，
3.1（dunfell）只认 `ABORT`/`STOPTASKS`/`WARN`。四版共用一份 `base.yml`，写 `HALT`
会让 dunfell 在解析阶段直接
`ERROR: Unknown disk space monitor action: HALT`（实测于 #48 的 dunfell 构建）。
这份配置 2026-10-30 之前是 `HALT`，P1 的 dunfell 真构建跑在它之前，所以一直没暴露。

宿主机 /tmp 归 systemd 管，`/tmp` 那一档只在小 tmpfs 环境下才会触发，留着无害。

## 3. buildhistory：跨版本包内容底账

```bitbake
INHERIT += "buildhistory"
YP_VARIANT ??= "general"
BUILDHISTORY_DIR = "${TOPDIR}/../../buildhistory/${YP_RELEASE_NAME}-${YP_VARIANT}"
BUILDHISTORY_COMMIT = "1"
BUILDHISTORY_COMMIT_AUTHOR = "yocto-build <yocto-build@yocto-platform.invalid>"
```

**布局**：`work/buildhistory/<release>-<variant>/`，八个组合各一个独立 git 仓库。
放 `${TOPDIR}` 之外是刻意的 —— 在 `TMPDIR` 里会随 `rm_work` 或清理 `work/` 一起消失。

**记录什么**：每个包的文件清单、依赖、大小、`PKGV`/`PR`，镜像的
`image-info`（装了哪些包、多大），以及 `metadata-revs`（当时的 layer 版本）。

**用法**：

```bash
bootstrap=work/buildhistory
# 同一 release 两个 variant 之间比
buildhistory-diff -p $bootstrap/kirkstone-general $bootstrap/kirkstone-custom
# 同一 variant 跨 release 比（更有价值：看升级带来的包变化）
buildhistory-diff -p $bootstrap/scarthgap-general $bootstrap/wrynose-general
```

**重要限制**：buildhistory 只在任务**真的执行**时记录。如果某个 recipe 命中
sstate 被跳过，它不会补录历史。所以：

- 全绿的增量构建只会产生 `metadata-revs`（日志里 `Writing buildhistory took: 0 seconds`）
- 要真正攒数据，得跑一次真实构建（新 machine、SDK、清 sstate 后重建）

验证 buildhistory 能工作（强制跑一个包）：

```bash
bash scripts/dev.sh bash -lc 'cd /work/work/kas-scarthgap-general/build && \
    . ../poky/oe-init-build-env . >/dev/null && \
    bitbake -f -c packagedata base-files'
git -C work/buildhistory/scarthgap-general log --oneline | head -3
```

**`BUILDHISTORY_COMMIT_AUTHOR` 为什么必须显式给**：`buildhistory_commit()` 整段
被 `( ... ) || true` 包着，git 身份缺失时 commit 失败**不会让构建变红**，
只会留下一堆未跟踪文件，等到要 `buildhistory-diff` 时才发现没有历史。

## 4. 源码镜像包：BB_GENERATE_MIRROR_TARBALLS

```bitbake
BB_GENERATE_MIRROR_TARBALLS = "1"
```

在 `do_fetch` 完成后，把 git 源再打一份 `git2_<hash>.tar.gz` 放进 `DL_DIR`。
value 在于：

- 构建机出网受限，`linux-yocto` 直连 git 会在传大 pack 时断（`fetch-pack: unexpected disconnect`），
  当初只能改走 `downloads.yoctoproject.org` 的 3.83 GiB 全 history 包
- 有了 mirror tarball，`DL_DIR` 可以整包搬到另一台机器，不用重新解一遍 git 协议
- 代价是 `DL_DIR` 多占一份（顶层目录 17G → 会增加）

**只影响之后新 fetch 的条目**。已命中 sstate 的 recipe 不会因此重跑 `do_fetch`，
所以打开它不会触发重建。这也是它必须写在 `base.yml` 而不是各 release 的原因 ——
任何 release 单独覆盖成 `"0"`，那一版就变成断网不可重建。

## 一起改的时候的顺序

1. 改 `kas/base.yml`
2. `python3 scripts/kas-verify.py --engine builtin`（8 组合全过）
3. 删掉受影响的 `work/kas-<rel>-<variant>/build/conf/local.conf`（kas 不会覆盖已存在的）
4. `bash scripts/build.sh --release <r> --variant <v>`
5. 确认日志里出现 `NOTE: Writing buildhistory`
