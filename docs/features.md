# 功能说明书

> **本文件是「每条功能是什么、怎么用、证到什么程度」的人读说明书。**
> 机器可读的注册表在 [`../config/features.txt`](../config/features.txt)——两者分工：
> 人读这份，机器读那份。`99_coverage.bats` 只校验 `features.txt` 的自洽性，
> 本文件的说明不参与门禁，但**不许与它矛盾**。
>
> 想知道工程结构为什么这样 → [`design.md`](design.md)
> 想知道怎么证明它对 → [`verification-flow.md`](verification-flow.md)
>
> 最后更新：2026-11-09（v1.0.0 已发布；此后保障范围收窄至 wrynose 6.0）

## 0. 两条先读的规则

**规则一：`✅` 不等于「验到运行时」。** 每条功能都标了**证据级别**，四档含义不同：

| 档位 | 含义 | 判定方式 | 能发现什么 | **发现不了什么** |
|---|---|---|---|---|
| `static` | 配置存在且正确 | bats 断言 | 文件缺失、字段写错、路径不通 | 能不能真的编出来、跑起来 |
| `build` | 真构建通过 | `N tasks all succeeded` | 解析错误、构建失败、依赖缺失 | 装进去的东西能不能用 |
| `boot` | 起机到 login | 串口 `login:` 且无 panic | 启动链断、init 起不来 | 服务是不是假活 |
| `runtime` | 客户机内动作可执行 | smoke 动作集 rc=0 | 二进制不可执行、库缺失、服务假活 | 上游测试是否全过（那是 ptest） |

**规则二：「已发布」的版本口径。** `v0.5.0` / `v0.6.0` / `v0.7.0` 三个里程碑从未单独打 tag、从未发 Release，它们的内容是**累积进 `v1.0.0`** 的。所以下面写「随 v1.0.0 累积发布」，不写「v0.5.0 已发布」。

## 1. 工程基础设施

| Feature | 证据级别 | 状态 | 归属 |
|---|---|---|---|
| `entry-unified` | static | ✅ | v0.1.0 |
| `docker-images` | build | ✅ | v0.1.0 |
| `container-runtime` | build | ✅ | v0.1.0 |
| `kvm-accel` | boot | ✅ | v0.1.0 |
| `shared-cache` | static | ✅ | v0.2.0 |
| `ci-workflows` | static | ✅ | v0.2.0 |

### entry-unified

**是什么**：四个发行版的 poky 版本锁在同一份 `config/versions.env` 里，`git commit` 级别的锁定，不是分支名。

**怎么用**：改版本 = 改 `config/versions.env` 里对应行 + 重跑 `kas-verify.py`。分支名会漂，commit 不会。

**边界**：只锁 poky 与 meta-openembedded 的 commit；不锁层内的 recipe 版本（那由 poky 决定）。

**证明**：`tests/bats/00_project.bats`（16 项，含四版 commit 断言）。

### docker-images

**是什么**：每个 release 一个构建镜像（`ghcr.io/zeek-zhao/yp-distro/<release>`），公开可匿拉，带 OCI 许可标签。镜像内是「能跑 bitbake 的最低环境」。

**怎么用**：`bash scripts/container.sh --release wrynose --variant custom -- <命令>`，不要在宿主直接跑 bitbake。

**边界**：镜像是**构建环境**，不是产物。它的许可不是 MIT（见 `THIRD_PARTY_NOTICES.md`）。

**证明**：`tests/bats/01_dockerfile.bats`（11 项）；`pull-check.yml` 每周一匿名拉取验证。

### container-runtime

**是什么**：容器入口脚本 `scripts/container.sh` 的运行时契约——把宿主 UID 映射成镜像内 `builder`，同时生成 `/etc/passwd` 与 `/etc/group` 挂进去。

**怎么用**：`--check` 看宿主 UID:GID，`--dry-run` 看解析出的镜像名，不加参数才是真跑。

**边界**：只解决 UID/GID 解析与 pseudo 冲突，不解决 SELinux/AppArmor。

> **为什么 `/etc/group` 不能漏**：`oe/sstatesig.py` 哈希文件列表时用 `pwd.getpwuid()` **和** `grp.getgrgid()`。只挂 passwd 时 `do_package` 会抛 KeyError，报成「owned by uid N, gid N, which doesn't match any user/group」。这个 bug 藏了很久，因为只有 `do_package` 真执行（不命中 sstate）时才踩到。

**证明**：`tests/bats/03_container.bats`（18 项）。

### kvm-accel

**是什么**：QEMU 走 `/dev/kvm` 加速。起机时间从分钟级降到十几秒，是全部启动测量成立的前提。

**怎么用**：宿主有 `/dev/kvm` 就行，`qemu.sh` 自动检测。

**边界**：**没有 KVM 时用例会 skip**，而 `skip-gate.sh` 把 skip 数当门禁——这是刻意的，宁可红也不许悄悄降级。

**证明**：`03_container.bats` 的 KVM 透传用例。

### shared-cache

**是什么**：`DL_DIR` 与 `SSTATE_DIR` 指向共享的 `work/downloads` 与 `work/sstate`，四个 release 共用一份。

**怎么用**：不需要操作。`kas/base.yml` 里写死 `${TOPDIR}/../../downloads`。

**边界**：**`../..` 是刻意的**。只用 `..` 会退化成每个 release 一份缓存，磁盘与命中率都会崩。

**证明**：`tests/bats/07_cache.bats`（10 项）。

### ci-workflows

**是什么**：GitHub Actions 的六类作业：lint / bats / secret-scan / identity-guard / plan-sync / branch-guard。

**怎么用**：PR 自动触发。九个状态检查是 `protect-main` ruleset 的必需项。

**边界**：**CI 只做 static 档**。build / boot / runtime 三档在构建机 215——GitHub runner 没有 bitbake，一次 6.0 构建是小时级。

**证明**：`tests/bats/02_workflows.bats`（13 项）。

## 2. 配置与分层

| Feature | 证据级别 | 状态 | 归属 |
|---|---|---|---|
| `kas-layer` | static | ✅ | v0.3.0 |
| `layer-structure` | static | ✅ | v0.3.0 |
| `distro-features` | build | ✅ | v0.3.0 |
| `syntax-matrix` | static | ✅ | v1.0.0（知识资产） |
| `cross-version-diff` | static | ✅ | v1.0.0 |
| `distro-backfill` | static | ⚠️ degraded | v1.0.0 |

### kas-layer

**是什么**：26 个 YAML 按六维切分（base / machines / releases / variants / features / targets），`targets/<release>-<variant>.yml` 是唯一的人工入口，`.lock.yml` 是锁住的完整展开。

**怎么用**：只改 `targets/*.yml` 的引用关系；要改实际配置改对应维度文件，然后让 lock 重新生成。

**边界**：kas 是**配置合并**，不是构建系统。它产出 `local.conf` 与 `bblayers.conf`，之后全交给 bitbake。

**证明**：`tests/bats/05_kas.bats`（21 项）。

### layer-structure

**是什么**：`meta-yp` 的层结构：`classes/` 4 个 class、`conf/` 6 个配置文件、`recipes-*/` 按用途分目录。

**怎么用**：新增配方放对应 `recipes-*` 目录；不要新建 layer，这个项目只有一个自有 layer。

**边界**：`recipes-example/cpp-hello-cus-pack` 是**兼容性演示**，不是能力——它存在的理由是展示「同一份配方四版语义一致」，`04_layer.bats` 对它豁免冒号检查。

**证明**：`tests/bats/04_layer.bats`（12 项）。

### distro-features

**是什么**：`DISTRO_FEATURES` 相对 Poky 基线的改动，以及三层镜像的包含关系（`minimal ⊂ base ⊂ full`）。

**怎么用**：改 `conf/distro/yp.conf`。三层体积单调递增由 `12_distro.bats` 断言。

**边界**：体积单调是**启动三点基线成立的前提**。改镜像内容如果破坏单调性，基线口径也要跟着改。

**证明**：`tests/bats/12_distro.bats`（3 项）+ `docs/distro-features.md`。

### syntax-matrix

**是什么**：四版 YAML/BitBake 语法差异矩阵——`S` 落点、override 分隔符、`UNPACKDIR`、cargo/Go 版本、`IMAGE_INSTALL` 写法。

**怎么用**：新增配方前先查「源码解包目录」和「Override operator」两行。写错这两处会导致路径找不到或 override 不生效。

**边界**：**这是知识资产，不是保障承诺**。3.1/4.0/5.0 已冻结，矩阵记录的是历史实测结论，不会随上游变化更新。

**证明**：`tests/bats/15_syntax.bats`（5 项）+ `docs/syntax-matrix.md`。

### cross-version-diff

**是什么**：同一组合跨版本构建产物的差异对比能力——哪些包多了、哪些配置变了。

**怎么用**：`scripts/build.sh --diff` 系列或直接比 `deploy/` 下的清单。

**边界**：只比**清单层面**的差异，不比二进制内容。内容级对比需要 `--deep`（已 icebox）。

**证明**：`tests/bats/08_crossdiff.bats`（6 项）。

### distro-backfill

**是什么**：`DISTRO_FEATURES_BACKFILL` 在 6.0 被移除后的处理方式。

**状态**：**degraded**。理由登记在 `config/degraded.txt`：6.0 起 systemd 成为 nodistro 默认，本项目保留 poky 的 `DISTRO_FEATURES` / `IMAGE_FEATURES` 基线与 `INIT_MANAGER` 不动，因此不需要 backfill 兼容层。

**证明**：`config/degraded.txt` 的登记；`99_coverage.bats` 强制 degraded 必须有理由。

## 3. 镜像能力

| Feature | 证据级别 | 状态 | 归属 |
|---|---|---|---|
| `yp-service` | runtime | ✅ | v0.6.0（累积进 v1.0.0） |
| `demo-statusd` | runtime | ✅ | v0.6.0（累积进 v1.0.0） |
| `demo-collectd` | runtime | ✅ | v0.6.0（累积进 v1.0.0） |
| `boot-time` | runtime | ✅ | v0.5.0（累积进 v1.0.0） |

### yp-service

**是什么**：服务模板 class。把「装 systemd unit + 建运行用户 + 写默认配置」收敛成一行 `inherit yp-service`。

**怎么用**：

```bitbake
inherit yp-service
YP_SERVICE_NAME ?= "${PN}"                  # 默认等于包名
YP_SERVICE_UNIT ?= "${YP_SERVICE_NAME}.service"
```

`do_install:append()` 里只调 `yp_service_install_unit`。

**证据级别**：`runtime`——起机后 `is-enabled` 与 `is-active` 都成立才算数。静态断言只能证明 unit 文件存在，证明不了它被 enable 了。

**边界**：只管 systemd 单元，**不管 socket 激活与 timer**。需要那两个的场合要自己写 unit。

**证明**：`tests/bats/13_service.bats`（6 项）+ `docs/adding-a-service.md`。

> **这里踩过一个坑**：早期为兼容 3.1 又写了一份 `do_install_append`，结果 3.1 上两份都生效、同一任务跑两遍，症状是 `xxx: not found` exit 127。实测证明**任务级冒号 3.1 也认**，冗余已删。

### demo-statusd

**是什么**：状态服务 demo。HTTP 端点返回 JSON，含版本与服务列表。

**怎么用**：起机后 `curl -s localhost:<port>/status`。

**证据级别**：`runtime`——返回合法 JSON 才算。文件存在不算。

**边界**：是**演示**，没有认证、没有限流、不适合暴露到网络。

**证明**：`tests/bats/16_statusd.bats`（3 项）。

### demo-collectd

**是什么**：采集服务 demo。周期性写采集记录到 journald。

**怎么用**：`journalctl -u yp-collectd -n 20` 能看到采集记录。

**证据级别**：`runtime`——`is-active` 且日志里有记录。假活（active 但从不产出）靠日志判。

**边界**：只写 journald，不落盘到独立文件。journald 的持久化由 `yp-journald-persist` 决定。

**证明**：`tests/bats/17_collectd.bats`（5 项）。

### boot-time

**是什么**：启动三段测量——内核、userspace、到 login，各段分开计时，5 次取中位数。

**怎么用**：`scripts/boot-time.sh --release wrynose --variant custom --image minimal`。

**证据级别**：`runtime`——必须真起机。这是唯一无法用静态断言替代的。

**边界**：**只在 KVM 下有效**。无 KVM 时数字没有可比性，会 skip。测量口径见 `docs/qa/boot-baseline.md` §1。

**证明**：`tests/bats/14_boottime.bats`（8 项）+ `docs/qa/boot-baseline.md`。

## 4. 合规产物

| Feature | 证据级别 | 状态 | 归属 |
|---|---|---|---|
| `spdx-format` | build | ✅ | v0.3.0 |
| `cve-tool` | static | ✅ | v0.3.0 |
| `cve-db` | build | ✅ | v0.3.0 |
| `foss-scan` | static | ⚠️ degraded | v1.0.0 |
| `do-scancode` | — | ⚠️ degraded | v1.0.0 |

> **范围声明**：合规产物**只保 SPDX SBOM 与 CVE 报告两件**。VEX、SBOM 与镜像一致性校验**不做**（非 CRA 制造商）。`THIRD_PARTY_NOTICES` 保留——那是 MIT 仓库分发二进制时的许可义务，不能停。

### spdx-format

**是什么**：SPDX SBOM，2.2（3.1~5.0）与 3.0.1（6.0）两种格式。各版产物形态不同：3.1 是 `.tar.gz`、4.0 是单文件、5.0 是 `.tar.zst`、6.0 是 `.rootfs.spdx.json`。

**怎么用**：`scripts/compliance.sh --release wrynose --variant custom --only sbom`。

**边界**：SBOM 描述的是**构建期**的包清单，不是**运行期**实际落盘内容。两者一致性校验不做。

**证明**：`tests/bats/11_compliance.bats`（15 项）；`docs/compliance.md`。

### cve-tool

**是什么**：CVE 检查工具的接入。3.1~5.0 用 `cve-check.bbclass`，6.0 用 `sbom-cve-check` CLI（6.0 没有 `cve-check.bbclass`）。

**怎么用**：`scripts/compliance.sh --release wrynose --variant custom --only cve`。

**边界**：只产清单，不做影响判定。哪些 CVE 真的影响本镜像需要人工判断（VEX 已 icebox）。

**证明**：`11_compliance.bats`；`docs/cve.md`。

### cve-db

**是什么**：CVE 库离线化。`cve-update-nvd2-native` 默认走 NVD REST API，无 key 时限流 5 次/30 秒，首次建库约 25 万条、实测 4 小时。所以库必须预先离线构建。

**怎么用**：`scripts/cve-db.sh` 从 `olbat/nvdcve` 构建，放进 `${DL_DIR}/CVE_CHECK/`。`CVE_DB_UPDATE_INTERVAL = "-1"`（永不更新），库缺失时**构建直接失败**而不是静默挂 4 小时。

**边界**：这条的 `release` 字段标的是 `dunfell,kirkstone,scarthgap`——因为 6.0 走的是 `sbom-cve-check` 的另一套流程。**收缩到 6.0 后这个字段需要重新表述**（见 #129）。

**证明**：`tests/bats/09_cvedb.bats`（10 项）。

### foss-scan

**是什么**：FOSS 许可扫描（scancode），逐包产 json/csv/spdx/html 四件。

**状态**：**degraded**——范围收缩后**默认不执行**，脚本保留。恢复条件是「出现真实出货或客户尽调」。

**边界**：它验的是**源码级许可**，与 `THIRD_PARTY_NOTICES`（产物级声明）不是一回事。后者仍在维护。

**证明**：`config/degraded.txt` 的登记。

### do-scancode

**是什么**：scancode 的具体执行入口。

**状态**：**degraded**，同上。`scripts/scancode.sh` 保留不删——删掉等于把「怎么做 FOSS 扫描」这个花了成本换来的知识一起删了。

**证明**：`tests/bats/11_scancode.bats`（8 项）验的是**脚本能力**，脚本还在所以仍跑。

## 5. 验证与发布

| Feature | 证据级别 | 状态 | 归属 |
|---|---|---|---|
| `report-archive` | static | ✅ | v0.1.0 |
| `deploy-guard` | static | ✅ | v1.0.0 |
| `release-check` | build | ✅ | v1.0.0 |
| `sdk` | build | ✅ | v1.0.0 |

### report-archive

**是什么**：`build → qemu → report` 三段的归档链。报告是 `docs/qa/{release}/{日期}-{sha}.md`，同目录附 `artifacts-{sha}.sha256`。

**怎么用**：`scripts/report.sh`（默认最新组合），`--all` 跑全部。

**边界**：报告的五要素（commit / 命令 / 环境 / 阈值 / 摘要）缺一项就只是「一次运行记录」，不能叫证据。见 `verification-flow.md` §3。

**证明**：`tests/bats/06_report.bats`（15 项）。

### deploy-guard

**是什么**：部署新鲜度门禁。防「`runqemu` 悄悄用了旧部署」——那会让你以为验的是新镜像。

**怎么用**：`scripts/deploy-guard.sh`，指纹戳比对。

**边界**：**只比清单指纹，不比内容**。旧 sstate 恢复出属性错乱文件这类污染，它发现不了（内容级 `--deep` 已 icebox）。

**证明**：`tests/bats/18_deployguard.bats`（6 项）。

### release-check

**是什么**：一条命令跑多组合全量回归的编排器：每组合 `build.sh → qemu.sh → report.sh`，出汇总。

**怎么用**：`bash scripts/release-check.sh`（默认跑哪些组合由受保障版本清单决定，清单在 `#127` 引入）。

**边界**：串行执行，**必须独占构建机**。中途失败会停在该组合，日志在 `/tmp/release-check-*`。

**证明**：`tests/bats/19_releasecheck.bats`（4 项）。

### sdk

**是什么**：SDK 与 eSDK 的产出能力。SDK 约 466 MB，eSDK 约 3003 MB，gcc 13。

**怎么用**：`scripts/sdk.sh --release wrynose`。

**边界**：eSDK 在 3.1 上需要 `yp-sdk-ext-workaround.bbclass`（已冻结）。6.0 的结论见 `docs/sdk.md` §8。

**证明**：`tests/bats/10_sdk.bats`（6 项）+ `docs/sdk.md`。

## 6. 当前未覆盖的能力

| 能力 | 状态 | 为什么 |
|---|---|---|
| runtime smoke 动作集 | ⬜ 已排期 | `#132`，DoD ③。这是 L3→L4 唯一的补口 |
| 只读根 `/var` 可写 | ⬜ 已排期 | `#133`，DoD ④。现在靠 tmpfs 兜底，只算「演示能起」 |
| ptest | icebox | `#120`。3–5 人日 + 每次点版本要处理上游红 |
| 内容级扫描 `--deep` | icebox | `#119`。指纹门禁已覆盖大部分 |
| arm64 | 暂停 | `#121`。纯元数据仓库，架构特定逻辑极少 |
| 实体硬件 | **永久不做** | 全部证据来自 QEMU，已写成主动声明 |
| VEX / SBOM 一致性 | **不做** | 非 CRA 制造商，显式决策 |
| 签名链（防整镜像替换） | icebox | `#118`。只声明 root hash 的边界 |

## 7. 相关文档

- 工程结构为什么这样 → [`design.md`](design.md)
- 数据怎么流动 → [`functional-flow.md`](functional-flow.md)
- 怎么证明它对 → [`verification-flow.md`](verification-flow.md)
- 承诺与不承诺 → [`engineering-overview.md`](engineering-overview.md)
- 机器可读注册表 → [`../config/features.txt`](../config/features.txt)
