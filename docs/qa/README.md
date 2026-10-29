# QA 报告归档

- `docs/qa/<release>/` 保存对应 release 的归档报告。
- `docs/qa/<release>/<date>-<sha>.md` 是一次 BATS 测试报告。
- `--render-only` 生成 `<date>-<sha>-render.md`，用于无测试渲染验证。
- 报告的「构建产物」记录 deploy 目录、主产物、字节数和 SHA-256。
- 同目录的 `artifacts.sha256` 保存该次构建全部镜像产物的校验和及来源信息。
- 报告的「QEMU 串口」记录登录提示匹配状态和日志大小；未运行时明确标注。
- `config/features.txt` 标注每个能力的 `ok` 或 `degraded` 状态。
- `config/degraded.txt` 是降级理由及需求条款的唯一来源。
- 报告按 release 从 `config/degraded.txt` 呈现降级项。
- 跨版本差异的唯一真本是 `config/crossdiff.txt`，报告只做呈现；无可比版本时记为 `n/a`，不新增降级项。
- `tests/bats/99_coverage.bats` 校验特性标注、降级理由和最新报告三处一致。

## QEMU 存证怎么来

```bash
scripts/qemu.sh --release <release> --variant <variant> [--timeout 300]
```

- 宿主侧入口是 `scripts/qemu.sh`，容器内部分是 `scripts/lib/inner-qemu.sh`；
  两者都在仓库里，改一次不用两边同步。
- 镜像名取 `config/variants/<variant>.env` 的 `IMAGE`（`general` = `core-image-minimal`，
  `custom` = `yp-image`），不在脚本里写死。
- 串口日志固定落在 `work/artifacts/<release>/<variant>/qemu-serial.log`；
  报告只读这个文件判断 `login:` 是否出现，不重新起机。
- 三个版本约束写在 `inner-qemu.sh` 里：3.1 的 `runqemu` 要 machine 位置参数、
  4.0+ 不能给 machine、wrynose 的 `.zst` 只支持 `snapshot` 模式。

## 降级项实测依据（wrynose = yocto-6.0.4）

| aspect | 实测依据 |
|---|---|
| `spdx-format` | `image_types_spdx.bbclass` 已不存在；`meta/classes/` 下只剩 `create-spdx.bbclass`、`create-spdx-3.0.bbclass`，`meta/classes-recipe/` 下是 `create-spdx-image-3.0.bbclass`、`create-spdx-sdk-3.0.bbclass` → 只能产出 SPDX 3.0 SBOM |
| `cve-tool` | `cve-check.bbclass` 已不存在；`meta/classes-recipe/sbom-cve-check.bbclass` 存在 |
| `distro-backfill` | `meta/conf/bitbake.conf` 里只剩墓碑声明：`BB_RENAMED_VARIABLES[DISTRO_FEATURES_BACKFILL] = "is obsolete, add all default features to DISTRO_FEATURES_DEFAULTS"` |
