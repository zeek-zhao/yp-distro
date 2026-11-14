# 组合矩阵：4 release × 2 variant × 2 machine = 10 种已验收组合

需求 §4.2 要求同一份代码在四个 Yocto 版本上都能出 **general**（贴近 oe-core 默认）
与 **custom**（独立 distro `yp` + 独立镜像 `yp-image`）两套镜像。本页是 #22 与 #27 的
验收底稿：每种组合都有归档报告，报告里的 commit 是**那次真构建时**的 commit，
不是重写过的值。

当前已验收：`4 release × 2 variant × {qemux86-64}` = 8 组（#22），
外加 `{scarthgap, wrynose} × general × qemuarm64` = 2 组（#27）。

## 一、8 种组合一览

| release | variant | distro | 主产物 | 字节 | SHA-256（前 12） | 任务数 | 构建 | 串口 | 报告（commit） |
|---|---|---|---|---|---:|---:|---:|---:|---|
| dunfell | general | poky | `core-image-minimal-qemux86-64.ext4` | 12428288 | `06a323e77d56` | 3432 | 1325s | 28298 | （归档已移出，git 历史可查） |
| dunfell | custom | **yp** | `yp-image-qemux86-64.ext4` | 164833280 | `6d3807dcf7f1` | 4482 | 728s | 37192 | （归档已移出，git 历史可查） |
| kirkstone | general | poky | `core-image-minimal-qemux86-64.ext4` | 28163072 | `d283300ae306` | 3919 | 2192s | 32901 | （归档已移出，git 历史可查） |
| kirkstone | custom | **yp** | `yp-image-qemux86-64.ext4` | 166920192 | `2314b8efaf97` | 4164 | 726s | 45388 | （归档已移出，git 历史可查） |
| scarthgap | general | poky | `core-image-minimal-qemux86-64.rootfs.ext4` | 39925760 | `d6969a793639` | 4551 | 1445s | 33338 | （归档已移出，git 历史可查） |
| scarthgap | custom | **yp** | `yp-image-qemux86-64.rootfs-*.ext4` | 187240448 | `38bcf2443f0d` | 5603 | 732s | 45981 | （归档已移出，git 历史可查） |
| wrynose | general | poky | `core-image-minimal-qemux86-64.rootfs.ext4.zst` | 20274535 | `65a5fc7be566` | — | — | 35088 | `wrynose/20261029-879e011.md` |
| wrynose | custom | **yp** | `yp-image-qemux86-64.rootfs-*.ext4.zst` | 60871153 | `972d6a705d2f` | 5825 | 1557s | 50340 | `wrynose/20261029-17cc392-custom.md` |

四份 custom 报告都是 112 例全过（0 失败 0 跳过）；串口全部匹配到 `login:`。
产物命名的版本差异见 `docs/03-build/kas.md`：3.1/4.0 是 `<image>-qemux86-64.<ext>`，
5.0 是 `<image>-qemux86-64.rootfs-<ts>.<ext>`，6.0 再压成 `.zst`。

## 二、custom 的 distro 确实是 `yp`（验收第 2 条）

```bash
# kirkstone / scarthgap / wrynose
kas shell kas/targets/<release>-custom.yml -c "bitbake -e yp-image | grep -E '^DISTRO='"
# → DISTRO="yp"
```

三个版本都直接拿到 `DISTRO="yp"`。**dunfell 例外**：3.1 的 `bitbake -e` 环境 dump
**不含 `DISTRO` / `MACHINE`** 两行（拿 general 的 poky 构建对照同样没有，属于 1.46 的行为，
不是配置问题），所以 dunfell 用三条等价证据：

```bash
# 1) 配置层：kas 渲染出的 local.conf
grep -nE '^DISTRO' work/kas-dunfell-custom/build/conf/local.conf
# → 62:DISTRO ??= "yp"

# 2) 镜像层：根文件系统里 os-release 的 ID
grep -a -o -m1 'ID=yp' work/kas-dunfell-custom/build/tmp/deploy/images/qemux86-64/yp-image-qemux86-64.ext4
# → ID=yp

# 3) 运行时：串口 banner
# → YP (Yocto Platform) 0.1.0 qemux86-64 ttyS0
```

同一手法在四个版本上都验过 `ID=yp`（6.0 的镜像是 `.ext4.zst`，先 `zstd -dc`）。

## 三、general 与 custom 是两套构建，不是同一个镜像改名（验收第 3 条）

| release | general SHA-256（前 12） | custom SHA-256（前 12） |
|---|---|---|
> 注：dunfell / kirkstone / scarthgap 的历史归档已于 2026-11-14 随工程清理移出仓库（git 历史 v1.0.2 前可查）；本表数据保留作历史对照。
| dunfell | `06a323e77d56` | `6d3807dcf7f1` |
| kirkstone | `d283300ae306` | `2314b8efaf97` |
| scarthgap | `d6969a793639` | `38bcf2443f0d` |
| wrynose | `65a5fc7be566` | `972d6a705d2f` |

体积也差一个量级（custom 带 systemd、multilib、curl/wget/python3/gdb 等），
并且 custom 的主机名是 `<release>-custom`（串口日志里可检索到）。

## 四、真构建才暴露的两个问题

1. **`UNPACKDIR` 只有 6.0 有**：`kas/releases/scarthgap.yml` 曾照抄
   `YP_SRC_DIR = "${UNPACKDIR}"`，5.0 的 poky 里没这个变量，S 停在字面量，
   `do_unpack` 阶段被 `bb.utils.mkdirhier` 的 `'${'` 检查打死。
   `bitbake -n`（noexec）**看不出**这类问题——它不跑 do_unpack。
   现在 `kas-verify.py` 除了「wrynose 必须有」，还有一条反向断言
   「非 wrynose 不得覆盖 `YP_SRC_DIR`」。
2. **`source oe-init-build-env` 撞 `set -u`**：该脚本第 29 行读 `$BBSERVER`，
   `scripts/lib/inner-qemu.sh` 带 `set -u` 就会 `BBSERVER: unbound variable` 秒退。
   已在 source 前后临时关掉 `-u`。

## 五、L1（BATS）要在 dev 容器跑

release 镜像只装构建依赖：**没有 hadolint / actionlint**，`project.sh shell` 也**不带**
docker socket，于是 `hadolint accepts all four build Dockerfiles`、
`actionlint accepts every workflow`、`running container resolves builder with the non-root host uid`
三条必红（#46）。`yocto-dev:local` 有全套工具与宿主 docker socket，112 例全绿。
所以 `scripts/report.sh` 里的 `bats -r` 在 dev 容器执行：

```bash
scripts/dev.sh scripts/report.sh --release <release> --variant <variant>
```

`report.sh` 本身不构建，只读 `work/` 下的产物、日志与串口存证，因此在哪个容器跑不影响产物数据。

## 六、machine 维度：arm64（#27，宿主零改动）

issue 原本写着「QEMU 验证 aarch64 启动（宿主需 qemu-system-aarch64）」。实际做下来
**宿主什么都不用装**：起机用的是 bitbake 自己编进 sysroot 的 `qemu-system-native`。

```bash
# 宿主侧
command -v qemu-system-aarch64 || echo absent          # → absent
# 容器内（bitbake 已经编好）
ls work/kas-scarthgap-general/build/tmp/sysroots-components/x86_64/qemu-system-native/usr/bin/
# → qemu-system-aarch64  qemu-system-arm  qemu-system-x86_64  ...
```

`poky/meta/recipes-devtools/qemu/qemu.inc` 里
`QEMU_TARGETS ?= "arm aarch64 i386 loongarch64 mips ... x86_64"`，默认就含 `aarch64`，
所以 `bitbake qemu-helper-native`（`inner-qemu.sh` 本来就会跑）顺带把
`qemu-system-aarch64` 编了出来。runqemu 实测命令行：

```
.../qemu-helper-native/1.0/recipe-sysroot-native/usr/bin/qemu-system-aarch64 \
  -machine virt -cpu cortex-a57 -smp 4 -m 2048 -snapshot -nographic ...
```

全程 TCG 全模拟，在 release 容器内跑，**构建机宿主环境零改动**。

| release | machine | 主产物 | 字节 | SHA-256（前 12） | 任务数 | 构建 | 串口 | 报告（commit） |
|---|---|---|---:|---:|---:|---:|---:|---|
| scarthgap | qemuarm64 | `core-image-minimal-qemuarm64.rootfs-*.ext4` | 23115776 | `9b0dac12048b` | 4532 | 801s | 20421 | （归档已移出，git 历史可查） |
| wrynose | qemuarm64 | `core-image-minimal-qemuarm64.rootfs-*.ext4.zst` | 6119795 | `7a352b4c7481` | 4611 | 973s | 21934 | `wrynose/20261030-8ca7fed-qemuarm64.md` |

两份报告都是 **124 例全过**（0 失败 0 跳过），串口都到 `qemuarm64 login:`，
banner 分别是 `Poky 5.0.20 qemuarm64 /dev/ttyAMA0` 与 `Poky 6.0.4 qemuarm64 /dev/ttyAMA0`。

### arm64 与 x86_64 是两套构建（不是同一镜像改名）

| release | x86_64 general | arm64 general |
|---|---|---|
| scarthgap | 39925760 B / `d6969a793639` | 23115776 B / `9b0dac12048b` |
| wrynose | 20274535 B / `65a5fc7be566` | 6119795 B / `7a352b4c7481` |

SHA-256 与体积全不同，且 arm64 的工作区独立（`work/kas-<release>-general-qemuarm64`），
不会和 x86_64 的 TMPDIR 互相污染。

### 为什么 custom × arm64 不在本次范围

`kas/variants/custom.yml` 的 multilib 段把 lib32 绑定到 **x86 tune**：

```yaml
require conf/multilib.conf
MULTILIBS = "multilib:lib32"
DEFAULTTUNE:virtclass-multilib-lib32 = "x86"
DEFAULTTUNE_virtclass-multilib-lib32 = "x86"
```

在 aarch64 machine 上要成立，得另设一套 aarch64 语义的 multilib tune，
属于独立设计而不是「把 machine 换一下」。issue #27 的验收也只要
`--release wrynose --machine qemuarm64`（默认 general），所以本次只覆盖 general。
