# QA 报告归档

- `docs/qa/<release>/` 保存对应 release 的归档报告。
- `docs/qa/<release>/<date>-<sha>.md` 是一次 BATS 测试报告。
- `--render-only` 生成 `<date>-<sha>-render.md`，用于无测试渲染验证。
- 文件名后缀顺序固定为 `<date>-<sha>[-<variant>][-<machine>][-render]`：
  `general` 与默认 machine（`qemux86-64`）不加后缀，所以历史文件名不变；
  只有 `custom` / 非默认 machine 才追加，避免同一 release 的多种组合互相覆盖。
- 报告的「构建产物」记录 deploy 目录、主产物、字节数和 SHA-256。
- 同目录的 `artifacts-<date>-<sha>[-<variant>][-<machine>].sha256` 保存该次构建全部
  镜像产物的校验和及来源信息（`#41` 之前叫固定的 `artifacts.sha256`，同一 release
  重跑会改写旧归档指向的文件，历史文件保留原样）。
- 报告的「QEMU 串口」记录登录提示匹配状态和日志大小；未运行时明确标注。
- `docs/qa/<release>/sdk-<date>-<sha>[-<variant>][-<machine>].md` 是一次 SDK/eSDK
  归档（`scripts/report.sh --sdk`），含体积、SHA-256、安装后 `gcc -dumpversion`
  与 `devtool` 结果。它**没有**降级清单节，所以 `99_coverage.bats` 挑「最新报告」
  时只认 `<date>-<sha>…md` 这类构建报告（`find -name '[0-9]*.md'`）。
- 报告的「CVE 检查」一节只在构建带了 `--cve` 时出现（开关记在
  `work/logs/build-<rel>-<var>.flags`），内容是离线库版本、库内 CVE 数、
  镜像清单名与「未修复/已修复/忽略」计数。
- `config/features.txt` 标注每个能力的 `ok` 或 `degraded` 状态。
- `config/degraded.txt` 是降级理由及需求条款的唯一来源。
- 报告按 release 从 `config/degraded.txt` 呈现降级项。
- 跨版本差异的唯一真本是 `config/crossdiff.txt`，报告只做呈现；无可比版本时记为 `n/a`，不新增降级项。
- `tests/bats/99_coverage.bats` 校验特性标注、降级理由和最新报告三处一致。

## QEMU 存证怎么来

```bash
scripts/qemu.sh --release <release> --variant <variant> [--machine <machine>] [--timeout 300]
```

- 宿主侧入口是 `scripts/qemu.sh`，容器内部分是 `scripts/lib/inner-qemu.sh`；
  两者都在仓库里，改一次不用两边同步。
- 镜像名取 `config/variants/<variant>.env` 的 `IMAGE`（`general` = `core-image-minimal`，
  `custom` = `yp-image`），不在脚本里写死。
- 串口日志固定落在 `work/artifacts/<release>/<variant>[-<machine>]/qemu-serial.log`；
  报告只读这个文件判断 `login:` 是否出现，不重新起机。
- aarch64（`qemuarm64`）**不需要宿主装 `qemu-system-arm`**：起机用的是 bitbake
  自己编的 `qemu-system-native`（`QEMU_TARGETS` 默认含 `aarch64`，实测
  `tmp/sysroots-components/x86_64/qemu-system-native/usr/bin/qemu-system-aarch64`
  已存在），全程在 release 容器内以 TCG 跑，宿主环境零改动。
- 三个版本约束写在 `inner-qemu.sh` 里：3.1 的 `runqemu` 要 machine 位置参数、
  4.0+ 不能给 machine、wrynose 的 `.zst` 只支持 `snapshot` 模式。

## 降级项实测依据（wrynose = yocto-6.0.4）

| aspect | 实测依据 |
|---|---|
| `spdx-format` | `image_types_spdx.bbclass` 已不存在；`meta/classes/` 下只剩 `create-spdx.bbclass`、`create-spdx-3.0.bbclass`，`meta/classes-recipe/` 下是 `create-spdx-image-3.0.bbclass`、`create-spdx-sdk-3.0.bbclass` → 只能产出 SPDX 3.0 SBOM |
| `cve-tool` | `cve-check.bbclass` 已不存在；`meta/classes-recipe/sbom-cve-check.bbclass` 存在 |
| `distro-backfill` | `meta/conf/bitbake.conf` 里只剩墓碑声明：`BB_RENAMED_VARIABLES[DISTRO_FEATURES_BACKFILL] = "is obsolete, add all default features to DISTRO_FEATURES_DEFAULTS"` |
