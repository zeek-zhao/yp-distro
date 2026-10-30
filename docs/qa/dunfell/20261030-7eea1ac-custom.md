# QA Report

- Kind: `bats+build`
- Release: `dunfell`
- Variant: `custom`
- Machine: `qemux86-64`
- Commit: `7eea1ac`
- Tag: `yocto-3.1.33`
- SOURCE_FINGERPRINT: `50ae8de69c4e85840e0b6ef65b9fc0220457c98a32a6d27f5effda37a5e68d0f`
- Hostname: `e89872a33295`
- Start time: `2026-10-30T19:46:20+08:00`
- End time: `2026-10-30T19:46:30+08:00`
- Duration: `10s`

## Test statistics

| Tests | Passed | Failed | Skipped |
|---:|---:|---:|---:|
| 140 | 140 | 0 | 0 |

## Failures

None

## 构建产物

- Deploy dir: `work/kas-dunfell-custom/build/tmp/deploy/images/qemux86-64`
- Artifact: `yp-image-qemux86-64.ext4`
- Artifact bytes: `164833280`
- Artifact SHA-256: `e5048edebb2f51716ff2675731244075796e4cd1c5859b63a5e4ff25ac174b80`
- Image digest: n/a（本地构建无 registry digest）
- 全部产物 sha256: 见 `artifacts-20261030-7eea1ac-custom.sha256`（同目录，路径相对仓库根）

### 构建统计

- Build duration: 44s
- Tasks attempted / cached: 4774 / 3619
- Sstate hit: 265/268 (98%)
- Build log: `/work/work/logs/build-dunfell-custom.log`

## QEMU 串口

- 串口日志: `work/artifacts/dunfell/custom/qemu-serial.log`
- 启动到 login prompt: `yes`（匹配到 `login:`）
- 日志字节数: `37192`

## CVE 检查

| 项 | 值 |
|---|---|
| 开关 | `--cve`（kas/features/cve.yml） |
| 离线库 | `work/downloads/CVE_CHECK/nvdcve_2.db` |
| 库内 CVE 数 | 385644 |
| 库构建时间 | 2026-10-30T19:25:34+0800 |
| 镜像 CVE 清单 | `yp-image-qemux86-64.json` |
| 未修复 / 已修复 / 忽略 | 4165 / 9919 / 2592 |

## 降级清单

无（本版本全部能力按标准实现）

## 跨版本差异

| aspect | 本版本(dunfell) | scarthgap | wrynose | kirkstone |
|---|---|---|---|---|
| `distro-version` | 3.1.33 | 5.0.20 | 6.0.4 | 4.0.35 |
| `spdx-format` | 2.2 (create-spdx.bbclass) | 2.2 + 3.0.1 | 3.0.1 only | 2.2 (create-spdx.bbclass) |
| `cve-class` | cve-check | cve-check | sbom-cve-check | cve-check |
| `distro-backfill` | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 仅改名墓碑 | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） |
| `kernel` | linux-yocto 5.4 | linux-yocto 6.6 | linux-yocto 6.18 | linux-yocto 5.15 |
| `gcc` | 9.% | 13.% | 15.% | 11.% |
| `image-fstypes` | tar.bz2 ext4 | tar.bz2 ext4 | tar.zst ext4.zst | tar.bz2 ext4 |
