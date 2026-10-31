# SDK / eSDK 产出与验证（issue #25）

需求 §7.3 把 SDK 与 eSDK 列为 P2 交付，且写明「必须成功，**不允许降级**」，
dunfell 也不例外。本方案把「构建」「安装验证」「归档」拆成三步，各自可重跑。

## 1. 三步各管什么

| 步 | 入口 | 产出 |
|---|---|---|
| 构建 | `scripts/sdk.sh --release R --variant V` | `deploy/sdk/*.sh` + `work/logs/sdk-<rel>-<var>.log/.meta` |
| 安装验证 | 同上（内置）或 `--verify-only` | `work/artifacts/<rel>/<var>/sdk.json` |
| 归档 | `scripts/report.sh --release R --variant V --sdk` | `docs/qa/<release>/sdk-<date>-<sha>[-<var>].md` |

**「产物存在」不等于「装了能用」**，所以第二步必须真装：两个安装包各解包到
`/tmp`（用 `-y -d` 走非交互），`source environment-setup-*` 后验
`gcc -dumpversion` 与 `devtool --help`，验完删掉。这一步在同一个 release 容器里做
—— SDK 的宿主工具链版本跟它自己的构建容器一致，换宿主验没有意义。

## 2. 为什么必须走 `kas shell`

`scripts/sdk.sh` 拼出来的容器命令是：

```bash
mkdir -p /work/work/kas-<rel>-<var> /work/work/downloads /work/work/sstate \
  && KAS_CLONE_DEPTH=1 KAS_WORK_DIR=/work/work/kas-<rel>-<var> \
     kas shell /work/kas/targets/<rel>-<var>.yml -c 'bitbake -c populate_sdk <image> && bitbake -c populate_sdk_ext <image>'
```

两个坑：

- release 容器里 **`bitbake` 不在 PATH 上**，环境是 kas 按 target 现搭的
  （`scripts/build.sh` 也是同一条路子）。
- `kas -c` 走的是 `/bin/sh -c`，**bitbake 的 `${IMAGE}` 在那个 shell 里不存在**，
  写 `bitbake ... ${IMAGE}` 会被展开成空串，报
  `Shell returned non-zero exit status`。镜像名必须在 `sdk.sh` 里就展开成字面量。

串行：`sdk.sh` 与 `build.sh` 共用 `work/build.lock`，抢锁时以 3 退出。

## 3. 产物与命名

- SDK：`poky-glibc-<sdk_arch>-<image>-<tune>-<machine>-toolchain-<ver>.sh`
- eSDK：`poky-glibc-<sdk_arch>-<image>-<tune>-<machine>-toolchain-ext-<ver>.sh`

两个必须记住的细节：

- **`-ext` 在版本号前面**，不是 `toolchain-<ver>-ext.sh`。
- 中间那段 `<tune>`（如 `core2-64`）会**打断** `<image>-<machine>` 的连续匹配，
  所以 glob 只能写成 `*${IMAGE}*${machine}-toolchain-*`；写成
  `<image>-<machine>-toolchain-*` 一条都匹配不到 —— 第一版就是这么挂的，
  而且 BATS 用 fixture 测不出来（fixture 里没有 `<tune>` 段）。
- 归档：`docs/qa/<release>/sdk-<date>-<sha>[-<variant>][-<machine>].md`，
  后缀规则与构建报告完全一致（general 与默认 machine 不加后缀）。

`docs/qa/README.md` 里 `99_coverage.bats` 只挑 `<date>-<sha>…md` 这类构建报告做
「最新报告」校验，SDK 归档没有降级清单节，所以 `find` 的条件收窄成 `[0-9]*.md`，
否则 SDK 归档一生成就会让它误判「最新报告缺节」。

## 4. `sdk.json` 的字段

```json
{
  "release": "scarthgap", "variant": "custom", "machine": "qemux86-64",
  "tag": "yocto-5.0.20", "commit": "7eea1ac", "date": "20261030",
  "build_seconds": 812,
  "sdk":  { "file": "...", "bytes": 0, "sha256": "...", "installed": true,  "gcc": "13" },
  "esdk": { "file": "...", "bytes": 0, "sha256": "...", "installed": true,  "devtool": "ok" }
}
```

`report.sh --sdk` 只读这份 json（不构建、不跑 BATS），验收结论
`PASS` 的条件是两个 `installed` 都为真 **且** `devtool == "ok"`，
任一不满足就写 `FAIL` 并以非零退出 —— 这就是「不允许降级」的机器化表达。

## 5. 用法

```bash
# 一个组合
scripts/sdk.sh --release scarthgap --variant custom
scripts/report.sh --release scarthgap --variant custom --sdk

# 只重跑安装验证（换镜像/换容器后想复验，不用再构建）
scripts/sdk.sh --release scarthgap --variant custom --verify-only

# 干跑，看清将要执行什么
scripts/sdk.sh --release scarthgap --variant custom --dry-run
```

`populate_sdk` 会引入一整套 `nativesdk-*` 配方（实测 scarthgap 从 5,938 个任务
涨到 6,000+，其中大头是 `gcc-crosssdk` / `nativesdk-glibc` 的 `do_compile`），
冷启动单组合约 30-60 分钟。8 个组合串行跑要几个小时，所以驱动脚本放在
`~/yp-run/sdk-*.sh`，仓库里只保留可复现的单组合入口。

## 6. 8 组合实测（2026-10-30，commit `e55b973`）

全部 PASS（两个 `installed` 均为真、`devtool` 均为 `ok`）。归档：
`docs/qa/<release>/sdk-20261030-e55b973[-<variant>].md`。

| release | tag | variant | SDK | eSDK | SDK `gcc` | eSDK `devtool` | 构建耗时 |
|---|---|---|---:|---:|---:|---|---:|
| dunfell | 3.1.33 | general | 128.3 MB | 1.01 GB | 9 | ok | 1026 s |
| dunfell | 3.1.33 | custom | 291.8 MB | 1.27 GB | 9 | ok | 143 s ※ |
| kirkstone | 4.0.35 | general | 192.0 MB | 1.86 GB | 11 | ok | 1088 s |
| kirkstone | 4.0.35 | custom | 416.4 MB | 1.98 GB | 11 | ok | 1299 s |
| scarthgap | 5.0.20 | general | 181.4 MB | 2.25 GB | 13 | ok | 1307 s |
| scarthgap | 5.0.20 | custom | 371.9 MB | 2.49 GB | 13 | ok | 1414 s |
| wrynose | 6.0.4 | general | 233.6 MB | 2.60 GB | 13 | ok | 1804 s |
| wrynose | 6.0.4 | custom | 465.5 MB | 2.93 GB | 13 | ok | 2079 s |

※ dunfell:custom 是 eSDK 修复后的补跑，SDK 阶段全部命中 sstate，143 s 是增量耗时，
不代表冷启动成本（同版本 general 是 1026 s）。

三个可读出的规律：

1. **eSDK 普遍是 SDK 的 6~11 倍**：它带整个 SDK 的 sysroot 与全部 `nativesdk-*`。
2. **custom 比 general 贵 40%~100%**：custom 有 multilib（`lib32`）与 systemd，
   `nativesdk` 侧随之变多。
3. **版本越新越大**：eSDK 从 dunfell 的 1.01 GB 到 wrynose 的 2.60 GB，是工具链与
   sysroot 膨胀，不是本工程的增量。

## 7. dunfell 的 eSDK 需要一层 workaround

3.1 的 `oe.copy_buildsystem.copy_bitbake_and_layers()` 只会正确处理两类层：
COREBASE 树内的、以及 COREBASE 的兄弟目录。本工程的 `layers/meta-yp` 在构建树外
四层（`<repo>/layers/meta-yp` 对 `<work>/kas-<release>-custom/poky`），于是
`relpath()` 得到 `../../../../layers/meta-yp`，被拼成
`poky/../../../../layers/meta-yp` 写进 eSDK 的 `conf/bblayers.conf`，生成
filtered task list 时直接失败：

```
ERROR: The following layer directories do not exist:
ERROR:    .../tmp-renamed-sdk/layers/../../layers/meta-yp
```

挂的是 `do_populate_sdk_ext` —— **SDK 本体是好的，只有 eSDK 挂**。4.0 起这个函数被
`write_sdk_bblayers()` 重写、按层位置分三态处理，所以 kirkstone/scarthgap/wrynose 的
custom 一次就过，只有 dunfell 需要处理。

修法在 `layers/meta-yp/classes/yp-sdk-ext-workaround.bbclass`，挂到
`do_populate_sdk_ext` 的 `prefuncs`：

- 在 COREBASE 旁边建软链 `<corebase>/../meta-yp` 指向真实层目录；
- **只对这个任务**把 `BBLAYERS` 换成软链路径（`BuildSystem.__init__` 就是读
  `d.getVar('BBLAYERS')` 取的层列表），让 `relpath()` 变成 `../meta-yp`、命中上游
  本来支持的那个分支，eSDK 里得到 `${SDKBASEMETAPATH}/layers/poky/meta-yp`，
  文件也真被复制到那个位置；
- 判据用实现源码的特征串（`os.path.basename(corebase) + ` 在 4.0+ 三份源码里
  都是 0 命中），比按版本号猜可靠；没有该缺陷的版本直接 return。

真实构建用的 `BBLAYERS` 不动，其它任务不受影响。实测 dunfell:custom 从
`do_populate_sdk_ext: Failed` 变成 `Succeeded`，eSDK 1.27 GB、`devtool=ok`。
