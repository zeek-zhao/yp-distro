# QA Report

- Kind: `bats+build`
- Release: `kirkstone`
- Variant: `custom`
- Machine: `qemux86-64`
- Commit: `7eea1ac`
- Tag: `yocto-4.0.35`
- SOURCE_FINGERPRINT: `4a73b4389376f66b9f746f101d78ac4c731940d36d81e847fae4fc4d7d143fe9`
- Hostname: `0536e9b2015b`
- Start time: `2026-10-30T19:44:45+08:00`
- End time: `2026-10-30T19:44:54+08:00`
- Duration: `9s`

## Test statistics

| Tests | Passed | Failed | Skipped |
|---:|---:|---:|---:|
| 140 | 140 | 0 | 0 |

## Failures

None

## 构建产物

- Deploy dir: `work/kas-kirkstone-custom/build/tmp/deploy/images/qemux86-64`
- Artifact: `yp-image-qemux86-64.ext4`
- Artifact bytes: `166920192`
- Artifact SHA-256: `953eab29603b725c56cac6dbe6bd548b2fc1cdac108200de9c495bdb9d93a2a1`
- Image digest: n/a（本地构建无 registry digest）
- 全部产物 sha256: 见 `artifacts-20261030-7eea1ac-custom.sha256`（同目录，路径相对仓库根）

### 构建统计

- Build duration: 49s
- Tasks attempted / cached: 4481 / 3842
- Sstate hit: 441/444 (99%)
- Build log: `/work/work/logs/build-kirkstone-custom.log`

## QEMU 串口

- 串口日志: `work/artifacts/kirkstone/custom/qemu-serial.log`
- 启动到 login prompt: `yes`（匹配到 `login:`）
- 日志字节数: `45388`

## CVE 检查

| 项 | 值 |
|---|---|
| 开关 | `--cve`（kas/features/cve.yml） |
| 离线库 | `work/downloads/CVE_CHECK/nvdcve_2-2.db` |
| 库内 CVE 数 | 385644 |
| 库构建时间 | 2026-10-30T19:25:13+0800 |
| 镜像 CVE 清单 | `yp-image-qemux86-64.json` |
| 未修复 / 已修复 / 忽略 | 2862 / 11097 / 2737 |

## 降级清单

无（本版本全部能力按标准实现）

## 跨版本差异

| aspect | 本版本(kirkstone) | scarthgap | wrynose | dunfell |
|---|---|---|---|---|
| `distro-version` | 4.0.35 | 5.0.20 | 6.0.4 | 3.1.33 |
| `spdx-format` | 2.2 (create-spdx.bbclass) | 2.2 + 3.0.1 | 3.0.1 only | 2.2 (create-spdx.bbclass) |
| `cve-class` | cve-check | cve-check | sbom-cve-check | cve-check |
| `distro-backfill` | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | 仅改名墓碑 | 生效（pulseaudio sysvinit gobject-introspection-data ldconfig） |
| `kernel` | linux-yocto 5.15 | linux-yocto 6.6 | linux-yocto 6.18 | linux-yocto 5.4 |
| `gcc` | 11.% | 13.% | 15.% | 9.% |
| `image-fstypes` | tar.bz2 ext4 | tar.bz2 ext4 | tar.zst ext4.zst | tar.bz2 ext4 |
