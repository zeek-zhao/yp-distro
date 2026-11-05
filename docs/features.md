# Feature 注册表

> 本仓库所有 feature 的单一索引：状态、验收证据、归属里程碑/issue。
> 「已完成」必须有归档或测试可追溯；「进行中/规划中」必须有关联 issue。
> 新 feature 先开 issue 再进本表（与 CONTRIBUTING 的「先开 issue」一致）。
>
> 最后更新：2026-11-05（v1.0.0 发布）。

## 1. 基础设施（v0.1.0–v0.2.0，已发布）

| Feature | 证据/文档 | 状态 |
|---|---|---|
| 容器化构建（4 构建镜像 + 开发镜像，公开分发） | `docs/container.md`；ghcr.io 四镜像 pull-check CI | ✅ |
| kas 版本锁与四版配置矩阵 | `docs/kas.md`；`config/*.env` + `kas/` 分层 | ✅ |
| BATS 门禁体系（206 项，0 失败 0 skip） | `tests/bats/`；CI bats + release-matrix | ✅ |
| QA 报告链（build→qemu→report→归档） | `scripts/report.sh`；`docs/qa/` | ✅ |

## 2. 发行版能力（v0.3.0–v0.4.0，已发布）

| Feature | 证据/文档 | 状态 |
|---|---|---|
| U-Boot 启动链（x86 QFW，6.0） | `docs/qa/wrynose/`；`yp-uboot.inc` | ✅ |
| systemd 收口（init 管理器切换） | `docs/distro-features.md` | ✅ |
| 三层镜像（minimal ⊂ base ⊂ full） | `layers/meta-yp/recipes-core/images/`；12_distro.bats | ✅ |
| 品牌化（yp-release/hostname/motd） | `docs/qa/` 各 custom 归档 | ✅ |
| 服务模板 yp-service.bbclass + yp-statusd / yp-collectd | `docs/adding-a-service.md`；13/16/17_bats | ✅ |
| 六构建系统 demo（make/cmake/autotools/meson/python/rust/go） | `docs/syntax-matrix.md` | ✅ |

## 3. 启动优化（v0.5.0，已发布；三版移植）

| Feature | 数字 | 状态 |
|---|---|---|
| 内核裁剪 fragment（G1+G2+G3） | kernel_ms -6~-9%（三版一致）；KB-11/12 | ✅ |
| 压缩定稿 ZSTD | bzImage -37.5%（6.0）；KB-13 | ✅ |
| serial-getty@ttyS1 mask | 三版 masked；KB-21 | ✅ |
| 启动三段测量 + 基线文档 | `docs/qa/boot-baseline.md` §2/§6/§10 | ✅ |
| rootfs 格式对比实验开关 | `kas/features/rootfs-{squashfs,cpio}.yml`；KB-07 | ✅ |
| 优化汇总报告 | `docs/boot-optimization.md` | ✅ |

## 4. 服务与 demo（v0.6.0，已发布）

| Feature | 证据 | 状态 |
|---|---|---|
| 三层镜像 × 服务数×耗时曲线（均摊 134ms/unit） | `docs/boot-optimization.md` §三；#78 | ✅ |
| 5.0 服务与 demo 落地（C 源码零改动） | #83；`docs/qa/scarthgap/` | ✅ |

## 5. 四版收口与工程化（v1.0.0，已发布）

| Feature | 证据 | 状态 |
|---|---|---|
| 四版全量回归编排（release-check.sh） | #115；`docs/point-releases.md` | ✅ |
| deploy 指纹门禁（deploy-guard.sh） | #114；`docs/backlog.md` | ✅ |
| 点版本跟进流程 + 首演（scarthgap 5.0.21） | #115；KB-08/09 | ✅ |
| dm-verity 可行性验证 + 篡改检出 | `docs/qa/security/dm-verity-feasibility.md` | ✅ |
| dm-verity 生产化评估（两路线对比） | `docs/qa/security/dm-verity-production-assessment.md` | ✅ |
| 四版语法矩阵闭合（3.1/4.0 能编） | `docs/syntax-matrix.md` | ✅ |
| 知识库/规范文档（KB-01~32） | `docs/knowledge-base.md` | ✅ |

## 6. 进行中（有关联 issue）

| Feature | Issue | 当前位置 |
|---|---|---|
| dm-verity 生产化（路线一@5.0 + 路线二@6.0 综合） | #117 | 未开工；评估已完成 |
| 签名链设计（root hash 保护边界补全） | #118 | 未开工；设计题清单已列 |

## 7. 规划中（backlog 认领后开工）

| Feature | Issue | 说明 |
|---|---|---|
| deploy-guard 内容级扫描（--deep） | #119 | rpm 元数据逐包扫（#109 型污染防线） |
| ptest 运行时测试（busybox/python3/openssl 先行） | #120 | 结果进回归报告 |
| qemuarm64 常态化抽查 | #121 | 点版本窗口顺带执行 |
| CRA 合规深化（VEX、shipping-accurate SBOM 校验） | 暂在 backlog | 2027-12 全面执行前完成 |
