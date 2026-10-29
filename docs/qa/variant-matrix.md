# 变体矩阵：4 release × 2 variant = 8 种组合

需求 §4.2 要求同一份代码在四个 Yocto 版本上都能出 **general**（贴近 oe-core 默认）
与 **custom**（独立 distro `yp` + 独立镜像 `yp-image`）两套镜像。本页是 #22 的验收底稿：
每种组合都有归档报告，报告里的 commit 是**那次真构建时**的 commit，不是重写过的值。

## 一、8 种组合一览

| release | variant | distro | 主产物 | 字节 | SHA-256（前 12） | 任务数 | 构建 | 串口 | 报告（commit） |
|---|---|---|---|---|---:|---:|---:|---:|---|
| dunfell | general | poky | `core-image-minimal-qemux86-64.ext4` | 12428288 | `06a323e77d56` | 3432 | 1325s | 28298 | `dunfell/20261029-c30429d.md` |
| dunfell | custom | **yp** | `yp-image-qemux86-64.ext4` | 164833280 | `6d3807dcf7f1` | 4482 | 728s | 37192 | `dunfell/20261029-17cc392-custom.md` |
| kirkstone | general | poky | `core-image-minimal-qemux86-64.ext4` | 28163072 | `d283300ae306` | 3919 | 2192s | 32901 | `kirkstone/20261029-8d801a9.md` |
| kirkstone | custom | **yp** | `yp-image-qemux86-64.ext4` | 166920192 | `2314b8efaf97` | 4164 | 726s | 45388 | `kirkstone/20261029-17cc392-custom.md` |
| scarthgap | general | poky | `core-image-minimal-qemux86-64.rootfs.ext4` | 39925760 | `d6969a793639` | 4551 | 1445s | 33338 | `scarthgap/20261029-31d0ef1.md` |
| scarthgap | custom | **yp** | `yp-image-qemux86-64.rootfs-*.ext4` | 187240448 | `38bcf2443f0d` | 5603 | 732s | 45981 | `scarthgap/20261029-17cc392-custom.md` |
| wrynose | general | poky | `core-image-minimal-qemux86-64.rootfs.ext4.zst` | 20274535 | `65a5fc7be566` | — | — | 35088 | `wrynose/20261029-879e011.md` |
| wrynose | custom | **yp** | `yp-image-qemux86-64.rootfs-*.ext4.zst` | 60871153 | `972d6a705d2f` | 5825 | 1557s | 50340 | `wrynose/20261029-17cc392-custom.md` |

四份 custom 报告都是 112 例全过（0 失败 0 跳过）；串口全部匹配到 `login:`。
产物命名的版本差异见 `docs/kas.md`：3.1/4.0 是 `<image>-qemux86-64.<ext>`，
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
