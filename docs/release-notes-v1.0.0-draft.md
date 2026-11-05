# v1.0.0 Release Notes（草稿，合并 PR #113 后定稿）

> 用途：GitHub Release 页文案。合并 PR #113 后按本稿发布；数字均可追溯到
> `docs/qa/` 归档与 `work/artifacts/`。

## Highlights

**四个 Yocto 版本、一条工程化流水线。** dunfell 3.1 / kirkstone 4.0 /
scarthgap 5.0 LTS / wrynose 6.0 LTS × 2 variant（general / custom 独立 distro），
从版本锁、容器化构建、BATS 门禁到镜像分发与合规证据采集，全部脚本化、可复现。

### 启动优化（v0.5.0）

- 内核裁剪（fragment 三组 + ZSTD）：bzImage -37.5%（13.8MB → 8.6MB）
- **唯一有启动收益的措施**是裁调试设施：kernel_ms -6~-9%，结论在
  **三个 Yocto 版本上一致**（6.18/6.6/5.15，`docs/boot-optimization.md`）
- systemd 精简：mask null 串口的 getty；剖析出结构性瓶颈（udev 冷插排空）
- rootfs 格式对比：三种启动等价，维持 ext4

### 跨版本对齐（v0.7.0）

- scarthgap 5.0 全能力对齐：三层镜像、品牌化、服务与 demo、语法组七配方
- 语法差异矩阵四版闭合（`docs/syntax-matrix.md`）；3.1/4.0 按 D12 冻结
- 5.0 U-Boot 链降级说明（2024.01 无 BOOTMETH_QFW，degraded.txt）

### 工程化（v1.0.0 收口）

- `scripts/release-check.sh`：一条命令跑全量回归（build→qemu→report→guard）
- 点版本跟进流程（`docs/point-releases.md`）+ 首次执行（scarthgap 5.0.21）
- deploy 产物新鲜度门禁（指纹戳 + `deploy-guard.sh`）
- dm-verity 只读根可行性验证：起机 + 篡改逐块检出（`docs/qa/security/`）

## 数字

| 项 | 值 |
|---|---|
| 回归 | 8 组合 × 206 项 BATS，0 失败 0 跳过 |
| 启动（wrynose minimal，KVM 中位） | wall 17390 → 15924ms（-8.4%） |
| bzImage（wrynose minimal） | 13784064 → 8614912 bytes（-37.5%） |
| 服务并行成本 | ~134ms/unit（均摊） |

## 已知限制（登记于 config/degraded.txt）

- 5.0 的 U-Boot 引导链：QFW bootmeth 在 u-boot 2024.01 不存在，bootloader 段 n/a
- wrynose 的 minimal/base 串口 root 无空密码（`empty-root-password` 仅 full 层），
  这两层采不到 systemd-analyze
- 3.1/4.0 为 EOL 冻结口径：只保证「能编」与语法对照证据，不跟进安全更新

## 变更清单

PR [#113](https://github.com/zeek-zhao/yp-distro/pull/113)（27 commits），
关闭 16 个 issue。早期里程碑见各 `docs/qa/<release>/` 归档与
[Releases](https://github.com/zeek-zhao/yp-distro/releases)。
