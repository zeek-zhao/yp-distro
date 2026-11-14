# 软件需求规格说明书（SRS）—— yp-distro

> 依 ISO/IEC/IEEE 29148 轻量落地。功能需求（FR）的唯一事实源是 [`config/features.txt`](../../config/features.txt)（26 项，第 6 列为证据级别）；本文件给出需求语义与验收准则，机器可读的追溯见 [`traceability.md`](traceability.md)，可执行场景见 [`scenarios/`](scenarios/)。

## 1. 引言

### 1.1 目的
将 yp-distro 工程的功能与非功能需求固化为可验收基线，作为需求管理（29148）、测试映射（BDD 场景层）与验收（12207，见 `acceptance-plan.md`）的共同输入。

### 1.2 范围
覆盖 yp-distro v1.0.x 全部工程能力：容器化 Yocto 构建环境、发行版层与 kas 配置、合规与供应链取证、报告与验证工程、发布工程、运行时演示服务。当前支持 release 范围以 `config/supported-releases.txt` 为准（单一事实源，现仅 wrynose/6.0）。

### 1.3 引用
- ISO/IEC/IEEE 29148（需求工程）、ISO/IEC/IEEE 12207（验收流程）
- `config/features.txt`、`config/supported-releases.txt`（单一事实源）
- `docs/verification-flow.md`（验证流程与证据级别定义）、`docs/features.md`（功能说明书）
- `tests/bats/`（210+ 可执行用例）、`docs/qa/`（QA 归档证据）

### 1.4 术语
- **证据级别**：static（静态断言）/ build（构建产物断言）/ boot（起机日志断言）/ runtime（起机后在线行为断言）——由 features.txt 第 6 列注册。
- **FR**：功能需求，编号 `FR-001…FR-026` 与 features.txt 行序一一对应。
- **NFR**：非功能需求，编号 `NFR-001…NFR-008`。
- **degraded**：显式登记的能力降级（`docs/qa/degraded.txt`），验收时可豁免但不可隐匿。

## 2. 总体描述

### 2.1 产品定位
一套以容器为执行边界、以 bats 为验证引擎、以 git 归档为证据载体的 Yocto 发行版工程：所有工程能力（构建、合规、报告、发布）都必须留下可追溯的自动化证据。

### 2.2 用户与场景
- 构建工程师：通过统一 CLI（`yp`）与 Makefile 驱动容器构建/测试/报告。
- 发布管理员：release-check 单命令全量验证 + 点版本流程。
- AI 派单 / 自动化：以 plan-sync 同步 issues，以本 SRS 为验收基线。

### 2.3 运行环境
- 执行边界：Docker 容器（非 root builder 用户，host uid/gid 映射，KVM 加速可选降级 TCG）。
- CI：GitHub Actions 五 job 门禁（bats/lint/secret-scan/identity-guard/plan-sync）。
- 构建机：Jenkins 节点，共享缓存（downloads/sstate）与磁盘自保（BB_DISKMON_DIRS）。

### 2.4 约束与假设
- CVE 库离线优先（`CVE_DB_UPDATE_INTERVAL=-1`），离线重建约 4h。
- APT 镜像默认官方源，构建机可覆写（`APT_MIRROR`）。
- 旧版归档（dunfell/kirkstone/scarthgap）已随工程清理移出仓库，git 历史可查。

## 3. 具体需求

### 3.1 功能需求（FR-001…FR-026，按模块分组）

**M1 工程入口与命令行** —— `scenarios/m1-entry.feature`
- FR-001 `entry-unified`（static）：统一 CLI/Makefile 入口，全部命令有 help、未知命令走标准错误路径、dry-run 安全打印。
  验收：00_project.bats 16 用例全绿。

**M2 容器与镜像** —— `scenarios/m2-images.feature`
- FR-002 `docker-images`（static）：四版 Dockerfile 通过 hadolint、基础镜像显式 tag、非 root、OCI 标签、共享安装器经 lint。
- FR-004 `container-runtime`（static/build）：容器名/挂载/uid 映射契约稳定，preflight 拒绝特权与低磁盘水位。
- FR-018 `kvm-accel`（static）：KVM 设备透传，缺失时降级 TCG 不阻塞。

**M3 CI 流水线治理** —— `scenarios/m3-ci.feature`
- FR-003 `ci-workflows`（static）：workflow 全量 actionlint、runner/Action 钉版本、凭据零入库、main 有 branch-guard、L1 永不构建镜像。
- FR-026 `supported-releases`（static）：supported-releases.txt 是唯一支持清单事实源，清单外 release 一律拒绝。

**M4 层与发行版配置** —— `scenarios/m4-distro.feature`
- FR-005 `layer-structure`（static）：四 release 声明、distro 身份与 include 顺序、镜像只做品牌化增量、无未支持 override。
- FR-006 `kas-layer`（static/build）：8 目标矩阵完整、header v14、机器维度成对、CVE 类按变体继承、磁盘/并行约束。
- FR-017 `distro-features`（build）：systemd 先于 poky 选定，特性移除用双语法且不显式删基线。

**M5 合规与供应链** —— `scenarios/m5-compliance.feature`
- FR-007 `spdx-format`（build）：SPDX SBOM 采集与解析（2.2/3.0.1、索引型聚合）。
- FR-008 `cve-tool`（static/build）：compliance.sh 采集流（sbom+cve 五节归档、缺节 FAIL、6.0 口径）。
- FR-009 `cve-db`（build）：8 列/6 列库构建与投影等价、离线模式固定。
- FR-010 `foss-scan`（build，degraded）：foss-summary 按实际 json 记账。
- FR-016 `do-scancode`（static，degraded）：外部 CLI 路径、默认跳过不进镜像。

**M6 报告与验证取证** —— `scenarios/m6-report.feature`
- FR-013 `report-archive`（static）：产物主选择/校验和/归档命名（变体/机器后缀）稳定。
- FR-015 `cross-version-diff`（static）：跨版本对比行与列按名渲染，无可比归档时 n/a。
- FR-021 `syntax-matrix`（build/build）：语法矩阵 ≥10 行六列、wrynose systemd 行、YP_SRC_DIR 取源。

**M7 发布与部署工程** —— `scenarios/m7-release.feature`
- FR-024 `deploy-guard`（build）：构建指纹防漂移，--all 在任何机器安全运行。
- FR-025 `release-check`（build）：单命令全量验证，scope 跟随 supported-releases 单源。

**M8 SDK 与共享缓存** —— `scenarios/m8-build.feature`
- FR-011 `sdk`（build）：sdk.sh 校验/试运行，报告渲染体积/SHA/gcc 并判 PASS/FAIL。
- FR-014 `shared-cache`（static）：共享缓存校验、并发互斥、构建统计渲染与 3.1 sstate 兼容。

**M9 运行时与服务演示** —— `scenarios/m9-runtime.feature`
- FR-019 `yp-service`（runtime）：systemd 服务 bbclass 契约（双 override 分隔符、无 SysV 回退）。
- FR-020 `boot-time`（boot）：起机日志解析（uboot/kernel/login 三段）、无登录判失败、不伪造时钟。
- FR-022 `demo-statusd`（runtime）：状态服务走模板与 YP_SRC_DIR。
- FR-023 `demo-collectd`（runtime）：采集服务 stdout 刷新、无旧式日志轮转。
- FR-012 `distro-backfill`（static，degraded）：无自动化用例，以文档证据归档。

### 3.2 非功能需求（NFR）
见 [`traceability.md`](traceability.md) NFR 表（NFR-001 合并门禁五 job、NFR-002 提交身份合规、NFR-003 容器非 root、NFR-004 磁盘自保、NFR-005 APT 镜像可配、NFR-006 CVE 离线、NFR-007 凭据安全、NFR-008 覆盖完整性元测试）。

## 4. 验收准则
验收流程、判据与产物见 [`acceptance-plan.md`](acceptance-plan.md)（12207 轻量落地）：一轮 release-check 全绿 + report.sh all 全绿（degraded 显式登记豁免）+ 追溯矩阵全覆盖。

## 5. 维护约定
- 修改功能能力必须先改 `config/features.txt`（唯一事实源），再重跑 `python3 scripts/ci/gen_requirements.py` 再生 scenarios 与 traceability。
- bats 用例名是唯一可执行事实；scenarios/*.feature 生成物禁止手改用例名。
