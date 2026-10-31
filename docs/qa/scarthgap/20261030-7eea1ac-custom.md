# QA Report

- Kind: `bats+build`
- Release: `scarthgap`
- Variant: `custom`
- Machine: `qemux86-64`
- Commit: `7eea1ac`
- Tag: `yocto-5.0.20`
- SOURCE_FINGERPRINT: `4a73b4389376f66b9f746f101d78ac4c731940d36d81e847fae4fc4d7d143fe9`
- Hostname: `72666df3868f`
- Start time: `2026-10-30T19:44:55+08:00`
- End time: `2026-10-30T19:45:04+08:00`
- Duration: `9s`

## Test statistics

| Tests | Passed | Failed | Skipped |
|---:|---:|---:|---:|
| 140 | 140 | 0 | 0 |

## Failures

None

## 构建产物

- Deploy dir: `work/kas-scarthgap-custom/build/tmp/deploy/images/qemux86-64`
- Artifact: `yp-image-qemux86-64.rootfs-20261030112613.ext4`
- Artifact bytes: `187240448`
- Artifact SHA-256: `2580a4e919b04ff4534444a7298c7fab4579f5c7ddb824d2df7949a58313ca2a`
- Image digest: n/a（本地构建无 registry digest）
- 全部产物 sha256: 见 `artifacts-20261030-7eea1ac-custom.sha256`（同目录，路径相对仓库根）

### 构建统计

- Build duration: 88s
- Tasks attempted / cached: 5938 / 4605
- Sstate hit: 447/721 (61%)
- Build log: `/work/work/logs/build-scarthgap-custom.log`

## QEMU 串口

- 串口日志: `work/artifacts/scarthgap/custom/qemu-serial.log`
- 启动到 login prompt: `yes`（匹配到 `login:`）
- 日志字节数: `45981`

## CVE 检查

| 项 | 值 |
|---|---|
| 开关 | `--cve`（kas/features/cve.yml） |
| 离线库 | `work/downloads/CVE_CHECK/nvdcve_2-2.db` |
| 库内 CVE 数 | 385644 |
| 库构建时间 | 2026-10-30T19:25:13+0800 |
| 镜像 CVE 清单 | `yp-image-qemux86-64.rootfs.json` |
| 未修复 / 已修复 / 忽略 | 668 / 17637 / 38 |

## 降级清单

无（本版本全部能力按标准实现）

## 跨版本差异

| aspect | 本版本(scarthgap) | wrynose | kirkstone | dunfell |
|---|---|---|---|---|
| `distro-version` | 5.0.20 | 6.0.4 | 4.0.35 | 3.1.33 |
| `spdx-format` | 2.2 + 3.0.1 | 3.0.1 only | 2.2 (create-spdx.bbclass) | 2.2 (create-spdx.bbclass) |
| `cve-class` | cve-check | sbom-cve-check | cve-check | cve-check |
| `distro-backfill` | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 仅改名墓碑 | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） |
| `kernel` | linux-yocto 6.6 | linux-yocto 6.18 | linux-yocto 5.15 | linux-yocto 5.4 |
| `gcc` | 13.% | 15.% | 11.% | 9.% |
| `image-fstypes` | tar.bz2 ext4 | tar.zst ext4.zst | tar.bz2 ext4 | tar.bz2 ext4 |
