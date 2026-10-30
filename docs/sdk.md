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

- SDK：`<image>-<machine>-toolchain-<sdk_ver>.sh`
- eSDK：`<image>-<machine>-toolchain-ext-<sdk_ver>.sh`
  （`-ext` 与普通 SDK 靠这个名字区分，`find` 时两条 glob 不能写成一条）
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
  "sdk":  { "file": "...", "bytes": 0, "sha256": "...", "installed": true,  "gcc": "13.4.0" },
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
