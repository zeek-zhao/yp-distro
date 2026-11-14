# 需求追溯矩阵（traceability）

> 生成物：scripts/ci/gen_requirements.py 从 config/features.txt（唯一事实源）与 tests/bats/*.bats 自动生成。
> 方向：需求(FR) → Gherkin 场景(scenarios/*.feature) → bats 用例 → QA 归档证据(docs/qa/)。

## FR 总表

| FR | feature_id | release 范围 | 证据级别 | status | BATS 文件 | 用例数 | 场景文件 |
|---|---|---|---|---|---|---|---|
| FR-001 | entry-unified | all | static | ok | tests/bats/00_project.bats | 16 | scenarios/m1-entry.feature |
| FR-002 | docker-images | all | static | ok | tests/bats/01_dockerfile.bats | 11 | scenarios/m2-images.feature |
| FR-003 | ci-workflows | all | static | ok | tests/bats/02_workflows.bats | 13 | scenarios/m3-ci.feature |
| FR-004 | container-runtime | all | build | ok | tests/bats/03_container.bats | 15 | scenarios/m2-images.feature |
| FR-005 | layer-structure | all | static | ok | tests/bats/04_layer.bats | 12 | scenarios/m4-distro.feature |
| FR-006 | kas-layer | all | static | ok | tests/bats/05_kas.bats | 21 | scenarios/m4-distro.feature |
| FR-007 | spdx-format | all | build | ok | tests/bats/11_compliance.bats | 7 | scenarios/m5-compliance.feature |
| FR-008 | cve-tool | all | static | ok | tests/bats/11_compliance.bats | 7 | scenarios/m5-compliance.feature |
| FR-009 | cve-db | dunfell,kirkstone,scarthgap | build | ok | tests/bats/09_cvedb.bats | 10 | scenarios/m5-compliance.feature |
| FR-010 | foss-scan | all | build | degraded | tests/bats/11_compliance.bats | 1 | scenarios/m5-compliance.feature |
| FR-011 | sdk | all | build | ok | tests/bats/10_sdk.bats | 6 | scenarios/m8-build.feature |
| FR-012 | distro-backfill | wrynose | static | degraded | —（无自动化用例） | 0 | scenarios/m9-runtime.feature |
| FR-013 | report-archive | all | static | ok | tests/bats/06_report.bats | 15 | scenarios/m6-report.feature |
| FR-014 | shared-cache | all | static | ok | tests/bats/07_cache.bats | 10 | scenarios/m8-build.feature |
| FR-015 | cross-version-diff | all | static | ok | tests/bats/08_crossdiff.bats | 6 | scenarios/m6-report.feature |
| FR-016 | do-scancode | all | static | degraded | tests/bats/11_scancode.bats | 8 | scenarios/m5-compliance.feature |
| FR-017 | distro-features | all | build | ok | tests/bats/12_distro.bats | 3 | scenarios/m4-distro.feature |
| FR-018 | kvm-accel | all | static | ok | tests/bats/03_container.bats | 3 | scenarios/m2-images.feature |
| FR-019 | yp-service | wrynose | runtime | ok | tests/bats/13_service.bats | 6 | scenarios/m9-runtime.feature |
| FR-020 | boot-time | wrynose | boot | ok | tests/bats/14_boottime.bats | 8 | scenarios/m9-runtime.feature |
| FR-021 | syntax-matrix | all | build | ok | tests/bats/15_syntax.bats | 5 | scenarios/m6-report.feature |
| FR-022 | demo-statusd | wrynose | runtime | ok | tests/bats/16_statusd.bats | 3 | scenarios/m9-runtime.feature |
| FR-023 | demo-collectd | wrynose | runtime | ok | tests/bats/17_collectd.bats | 5 | scenarios/m9-runtime.feature |
| FR-024 | deploy-guard | all | build | ok | tests/bats/18_deployguard.bats | 6 | scenarios/m7-release.feature |
| FR-025 | release-check | all | build | ok | tests/bats/19_releasecheck.bats | 4 | scenarios/m7-release.feature |
| FR-026 | supported-releases | all | static | ok | tests/bats/20_supported_releases.bats | 4 | scenarios/m3-ci.feature |

覆盖合计：205 个 bats 用例（99_coverage 为元测试不计），26 个 FR 全部有场景或文档证据。

## NFR（非功能需求）

| NFR | 描述 | 证据 |
|---|---|---|
| NFR-001 | 合并门禁：CI 五 job（bats/lint/secret-scan/identity-guard/plan-sync）全绿 | .github/workflows/ci.yml + GitHub runs |
| NFR-002 | 提交身份合规：GitHub noreply 身份，identity-guard 全历史扫描 | scripts/ci/identity-guard.sh |
| NFR-003 | 容器非 root：builder 用户 + host uid/gid 映射 | tests/bats/01_dockerfile.bats、03_container.bats |
| NFR-004 | 磁盘自保：BB_DISKMON_DIRS 双阈值（STOPTASKS/ABORT） | tests/bats/05_kas.bats |
| NFR-005 | APT 镜像可配：默认官方源，构建机可覆写 | docker/common/install-yocto-deps.sh + docs/ci.md |
| NFR-006 | CVE 离线模式：CVE_DB_UPDATE_INTERVAL=-1，离线库优先 | tests/bats/09_cvedb.bats |
| NFR-007 | 凭据安全：tracked 仓库无明文凭据，workflow 用自动 token | tests/bats/02_workflows.bats + secret-scan job |
| NFR-008 | 测试覆盖完整性：features↔bats 双向注册校验（99_coverage 元测试 6 用例） | tests/bats/99_coverage.bats |

## 用例级明细

| FR | feature_id | bats 文件 | 用例 |
|---|---|---|---|
| FR-001 | entry-unified | 00_project.bats | configuration environment files do not use export |
| FR-001 | entry-unified | 00_project.bats | custom variant resolves the wrynose configuration |
| FR-001 | entry-unified | 00_project.bats | doctor lists all eight release and variant combinations |
| FR-001 | entry-unified | 00_project.bats | each implemented command has a successful command-level help |
| FR-001 | entry-unified | 00_project.bats | four release configurations resolve to their expected tags |
| FR-001 | entry-unified | 00_project.bats | help lists every implemented command |
| FR-001 | entry-unified | 00_project.bats | report defaults to all releases and general variant |
| FR-001 | entry-unified | 00_project.bats | shell dry-run applies defaults and launches a login shell |
| FR-001 | entry-unified | 00_project.bats | shell dry-run prints one safe scarthgap docker command |
| FR-001 | entry-unified | 00_project.bats | shell help lists its dry-run and runtime options |
| FR-001 | entry-unified | 00_project.bats | shell requires a release using the standard error path |
| FR-001 | entry-unified | 00_project.bats | test tags are forwarded to Bats as a filter |
| FR-001 | entry-unified | 00_project.bats | unimplemented build command exits with status two |
| FR-001 | entry-unified | 00_project.bats | unimplemented commands write one reason to stderr and exit two |
| FR-001 | entry-unified | 00_project.bats | unknown release fails with an error message |
| FR-001 | entry-unified | 00_project.bats | unknown shell options use the standard usage error status |
| FR-002 | docker-images | 01_dockerfile.bats | Ubuntu base images have an explicit non-latest tag |
| FR-002 | docker-images | 01_dockerfile.bats | dev image installs actionlint and records it in the fingerprint |
| FR-002 | docker-images | 01_dockerfile.bats | each Dockerfile copies the shared installer |
| FR-002 | docker-images | 01_dockerfile.bats | each Dockerfile has source and title OCI labels |
| FR-002 | docker-images | 01_dockerfile.bats | each Dockerfile has the identical builder USER instruction |
| FR-002 | docker-images | 01_dockerfile.bats | each Dockerfile runs as a non-root user |
| FR-002 | docker-images | 01_dockerfile.bats | each release uses its required Ubuntu base |
| FR-002 | docker-images | 01_dockerfile.bats | hadolint accepts all four build Dockerfiles |
| FR-002 | docker-images | 01_dockerfile.bats | latest base negative case fails both base assertions without editing sources |
| FR-002 | docker-images | 01_dockerfile.bats | release images install hadolint and actionlint |
| FR-002 | docker-images | 01_dockerfile.bats | shared installer passes shellcheck and shfmt |
| FR-003 | ci-workflows | 02_workflows.bats | L1 never builds images |
| FR-003 | ci-workflows | 02_workflows.bats | actionlint accepts every workflow without skipping |
| FR-003 | ci-workflows | 02_workflows.bats | all action references are pinned to major versions |
| FR-003 | ci-workflows | 02_workflows.bats | all workflow runners are pinned to ubuntu 24.04 |
| FR-003 | ci-workflows | 02_workflows.bats | image matrix releases and series match Dockerfiles and configurations |
| FR-003 | ci-workflows | 02_workflows.bats | images grant package writes and push using the repository build context |
| FR-003 | ci-workflows | 02_workflows.bats | images use the automatic token and github contains no personal credentials |
| FR-003 | ci-workflows | 02_workflows.bats | main is guarded by a branch guard job requiring PR provenance |
| FR-003 | ci-workflows | 02_workflows.bats | promised gates exist in repository: pre-push hook and make hooks |
| FR-003 | ci-workflows | 02_workflows.bats | pull check remains anonymous |
| FR-003 | ci-workflows | 02_workflows.bats | three workflow files exist and are nonempty |
| FR-003 | ci-workflows | 02_workflows.bats | tool installer help lists every tool and prefix option |
| FR-003 | ci-workflows | 02_workflows.bats | tracked repository passes credential scanning |
| FR-004 | container-runtime | 03_container.bats | all local release images pass container preflight |
| FR-004 | container-runtime | 03_container.bats | download and sstate directories are under the repository work mount |
| FR-004 | container-runtime | 03_container.bats | dry-run includes a read-only passwd mount from the host repository |
| FR-004 | container-runtime | 03_container.bats | dry-run maps the host uid and never runs privileged |
| FR-004 | container-runtime | 03_container.bats | dry-run prints exactly one command line on stdout |
| FR-004 | container-runtime | 03_container.bats | dry-run uses the stable release and variant container name |
| FR-004 | container-runtime | 03_container.bats | help describes dry-run mode |
| FR-004 | container-runtime | 03_container.bats | image guard skips when the release image is absent |
| FR-004 | container-runtime | 03_container.bats | low disk watermark blocks container preflight with cleanup guidance |
| FR-004 | container-runtime | 03_container.bats | missing release image |
| FR-004 | container-runtime | 03_container.bats | nested dry-run accepts an invisible host path without mounting docker binaries |
| FR-004 | container-runtime | 03_container.bats | nested dry-run mounts host docker paths when dev provides them |
| FR-004 | container-runtime | 03_container.bats | relative host repository paths are rejected |
| FR-004 | container-runtime | 03_container.bats | running container resolves builder with the non-root host uid and gid |
| FR-004 | container-runtime | 03_container.bats | unknown release fails and names the requested release |
| FR-005 | layer-structure | 04_layer.bats | active layer config tests and docs contain no retired names |
| FR-005 | layer-structure | 04_layer.bats | compat include is currently comments only and documents all releases |
| FR-005 | layer-structure | 04_layer.bats | full image installs the cpp example by real package name |
| FR-005 | layer-structure | 04_layer.bats | general variant leaves the oe-core image untouched |
| FR-005 | layer-structure | 04_layer.bats | layer configuration and core recipes have no unsupported colon overrides |
| FR-005 | layer-structure | 04_layer.bats | layer declares exactly the four supported release series |
| FR-005 | layer-structure | 04_layer.bats | minimal image adds only branding, no business or debug packages |
| FR-005 | layer-structure | 04_layer.bats | release include is the sole source of version codename and maintainer |
| FR-005 | layer-structure | 04_layer.bats | yp distro and images do not overwrite inherited feature baselines |
| FR-005 | layer-structure | 04_layer.bats | yp distro declares the agreed identity |
| FR-005 | layer-structure | 04_layer.bats | yp distro selects systemd before poky and requires both includes after identity |
| FR-005 | layer-structure | 04_layer.bats | yp images both require the oe-core minimal image |
| FR-006 | kas-layer | 05_kas.bats | base configuration does not define repositories |
| FR-006 | kas-layer | 05_kas.bats | build env bounds the parallelism by min(cores, 20) |
| FR-006 | kas-layer | 05_kas.bats | buildhistory writes one repository per release and variant |
| FR-006 | kas-layer | 05_kas.bats | builtin validator checks all eight targets |
| FR-006 | kas-layer | 05_kas.bats | custom variant references meta-yp as a local repository |
| FR-006 | kas-layer | 05_kas.bats | custom variant uses the agreed YP variable name |
| FR-006 | kas-layer | 05_kas.bats | dev Dockerfile installs kas and records its fingerprint |
| FR-006 | kas-layer | 05_kas.bats | disk monitor keeps both STOPTASKS and ABORT tiers |
| FR-006 | kas-layer | 05_kas.bats | distro layer inherits the CVE class only when the variant asks for it |
| FR-006 | kas-layer | 05_kas.bats | every kas YAML declares header version 14 |
| FR-006 | kas-layer | 05_kas.bats | kas command is wired through Makefile and project CLI |
| FR-006 | kas-layer | 05_kas.bats | kas configuration contains the complete release and variant matrix |
| FR-006 | kas-layer | 05_kas.bats | kas feature and BATS tag registration match |
| FR-006 | kas-layer | 05_kas.bats | kas targets never hardcode a non-default machine |
| FR-006 | kas-layer | 05_kas.bats | machine dimension keeps config and kas machine files in pairs |
| FR-006 | kas-layer | 05_kas.bats | machine suffix only appears for non-default machines |
| FR-006 | kas-layer | 05_kas.bats | mirror tarballs are generated for git sources |
| FR-006 | kas-layer | 05_kas.bats | release-specific knobs match each Yocto version |
| FR-006 | kas-layer | 05_kas.bats | validator rejects release tags that drift from config |
| FR-006 | kas-layer | 05_kas.bats | wrynose declares split repositories without poky |
| FR-006 | kas-layer | 05_kas.bats | wrynose keeps bitbake out of BBLAYERS |
| FR-007 | spdx-format | 11_compliance.bats | compliance.sh --print-sbom 缺产物时指向 --spdx 构建 |
| FR-007 | spdx-format | 11_compliance.bats | report.sh --compliance 索引型 SBOM 用聚合口径而不是「1 包」 |
| FR-007 | spdx-format | 11_compliance.bats | report.sh --compliance 索引型对位不全时判 FAIL |
| FR-007 | spdx-format | 11_compliance.bats | sbom-stats.py 不传 --spdx-dir 时索引型只报形态不聚合 |
| FR-007 | spdx-format | 11_compliance.bats | sbom-stats.py 同时认 SPDX 2.2 与 3.0.1 |
| FR-007 | spdx-format | 11_compliance.bats | sbom-stats.py 对无法识别的文档返回非零 |
| FR-007 | spdx-format | 11_compliance.bats | sbom-stats.py 认索引型文档并按 documentNamespace 对位聚合 |
| FR-008 | cve-tool | 11_compliance.bats | compliance.sh status 在未采集时报缺失而不是失败 |
| FR-008 | cve-tool | 11_compliance.bats | compliance.sh 校验必填参数与 --only 取值 |
| FR-008 | cve-tool | 11_compliance.bats | report.sh --compliance 出五节归档并判 PASS |
| FR-008 | cve-tool | 11_compliance.bats | report.sh --compliance 对 6.0 写 sbom-cve-check 而不是“不适用” |
| FR-008 | cve-tool | 11_compliance.bats | report.sh --compliance 拒绝 all |
| FR-008 | cve-tool | 11_compliance.bats | report.sh --compliance 有节缺失时判 FAIL 并返回非零 |
| FR-008 | cve-tool | 11_compliance.bats | report.sh --compliance 缺 compliance.json 时给出可执行的下一步 |
| FR-009 | cve-db | 09_cvedb.bats | PRODUCTS 表保住 cve-check 匹配所需的版本区间语义 |
| FR-009 | cve-db | 09_cvedb.bats | build 3.1 产出 6 列库（没有 SCOREV4/VECTORSTRING） |
| FR-009 | cve-db | 09_cvedb.bats | build 5.0 产出 cve-check 认的 8 列库，并丢弃 Rejected |
| FR-009 | cve-db | 09_cvedb.bats | cve-db.sh 接受 --release wrynose，未知 release 仍被拒绝 |
| FR-009 | cve-db | 09_cvedb.bats | cve-db.sh 的 status 里 wrynose 走 nvd-fkie 的 git 库而不是 sqlite |
| FR-009 | cve-db | 09_cvedb.bats | derive 从 8 列库投影出的 3.1 库与直接 build 等价 |
| FR-009 | cve-db | 09_cvedb.bats | kas 基线把 CVE 库固定成离线模式 |
| FR-009 | cve-db | 09_cvedb.bats | node 里首条 cpeMatch 不是 vulnerable 时整条 node 不入 PRODUCTS（对齐上游 return） |
| FR-009 | cve-db | 09_cvedb.bats | verify 拒绝列结构不匹配的库 |
| FR-009 | cve-db | 09_cvedb.bats | verify 拒绝空库 |
| FR-010 | foss-scan | 11_compliance.bats | foss-summary.py 按实际产出的 json 记账，失败包不进成功率 |
| FR-011 | sdk | 10_sdk.bats | report.sh --sdk 在 devtool 不可用时判 FAIL 并返回非零 |
| FR-011 | sdk | 10_sdk.bats | report.sh --sdk 在缺少 sdk.json 时给出可执行的下一步 |
| FR-011 | sdk | 10_sdk.bats | report.sh --sdk 拒绝 all |
| FR-011 | sdk | 10_sdk.bats | report.sh --sdk 渲染体积、SHA-256、gcc 版本与 PASS 结论 |
| FR-011 | sdk | 10_sdk.bats | sdk.sh dry-run 打印工作区、产物目录与两条 bitbake 命令 |
| FR-011 | sdk | 10_sdk.bats | sdk.sh 校验必填参数与取值 |
| FR-013 | report-archive | 06_report.bats | artifact bytes follows symlinks in deploy dir |
| FR-013 | report-archive | 06_report.bats | artifact helpers accept pre-5.0 naming without rootfs segment |
| FR-013 | report-archive | 06_report.bats | artifact helpers fall back to timestamped aliases and do not double count |
| FR-013 | report-archive | 06_report.bats | artifact list excludes qemuboot.conf |
| FR-013 | report-archive | 06_report.bats | artifact list prefers short names when both naming styles coexist |
| FR-013 | report-archive | 06_report.bats | artifact primary fails when no image exists |
| FR-013 | report-archive | 06_report.bats | artifact primary prefers ext4 and list excludes manifests |
| FR-013 | report-archive | 06_report.bats | artifact primary prefers zstd ext4 and list keeps zstd tarballs |
| FR-013 | report-archive | 06_report.bats | artifact sha256 matches a known digest |
| FR-013 | report-archive | 06_report.bats | checksum file name follows the archive so old reports stay consistent |
| FR-013 | report-archive | 06_report.bats | render-only report includes configured degraded aspects |
| FR-013 | report-archive | 06_report.bats | report CLI accepts positional and --release forms equivalently |
| FR-013 | report-archive | 06_report.bats | report archive name carries the machine for non-default machines |
| FR-013 | report-archive | 06_report.bats | report archive name carries the variant, general stays unsuffixed |
| FR-013 | report-archive | 06_report.bats | report script help exits successfully |
| FR-014 | shared-cache | 07_cache.bats | build.sh dry-run prints the container command and shared cache paths |
| FR-014 | shared-cache | 07_cache.bats | build.sh records logs and duration and preserves build failure status |
| FR-014 | shared-cache | 07_cache.bats | build.sh rejects concurrent builds without waiting |
| FR-014 | shared-cache | 07_cache.bats | build.sh validates required arguments and allowed values |
| FR-014 | shared-cache | 07_cache.bats | check_shared_cache passes for the current base configuration |
| FR-014 | shared-cache | 07_cache.bats | check_shared_cache rejects missing and weak cache assignments |
| FR-014 | shared-cache | 07_cache.bats | check_shared_cache rejects per-release caches |
| FR-014 | shared-cache | 07_cache.bats | report.sh falls back to the 3.1 sstate summary format |
| FR-014 | shared-cache | 07_cache.bats | report.sh render-only includes build statistics |
| FR-014 | shared-cache | 07_cache.bats | report.sh renders latest build metrics and n/a without adding degraded items |
| FR-015 | cross-version-diff | 08_crossdiff.bats | crossdiff renders all release columns by name rather than source position |
| FR-015 | cross-version-diff | 08_crossdiff.bats | crossdiff source has unique aspects and known releases with nonempty values |
| FR-015 | cross-version-diff | 08_crossdiff.bats | crossdiff validator rejects malformed fixtures under repo work |
| FR-015 | cross-version-diff | 08_crossdiff.bats | crossdiff without a comparable archive is n/a and does not add degraded items |
| FR-015 | cross-version-diff | 08_crossdiff.bats | render-only report contains one crossdiff table row per source aspect |
| FR-015 | cross-version-diff | 08_crossdiff.bats | rendered wrynose and scarthgap values are not copy pasted |
| FR-016 | do-scancode | 11_scancode.bats | do_scancode 必须显式传 --processes 并忽略工作目录噪音 |
| FR-016 | do-scancode | 11_scancode.bats | do_scancode 走外部 CLI，不写 DEPENDS |
| FR-016 | do-scancode | 11_scancode.bats | do_scancode 默认跳过且不进任何镜像 |
| FR-016 | do-scancode | 11_scancode.bats | scancode-toolkit-native 的 shim 配方已删除且无人依赖 |
| FR-016 | do-scancode | 11_scancode.bats | scancode.sh path 给出容器内绝对路径，路径带版本与 python |
| FR-016 | do-scancode | 11_scancode.bats | scancode.sh status 覆盖四个 release 且版本按镜像 python 选 |
| FR-016 | do-scancode | 11_scancode.bats | scancode.sh 拒绝缺少 --release 的 path 与未知 release |
| FR-016 | do-scancode | 11_scancode.bats | scarthgap 与 wrynose 共用同一份 scancode |
| FR-017 | distro-features | 12_distro.bats | distro does not explicitly remove systemd or sysvinit as a feature |
| FR-017 | distro-features | 12_distro.bats | distro removes only the selected features with both override syntaxes |
| FR-017 | distro-features | 12_distro.bats | systemd is selected before poky consumes INIT_MANAGER |
| FR-018 | kvm-accel | 03_container.bats | kvm device is forwarded when the host exposes it |
| FR-018 | kvm-accel | 03_container.bats | missing kvm degrades to tcg without blocking preflight |
| FR-018 | kvm-accel | 03_container.bats | preflight reports kvm acceleration capability without failing |
| FR-019 | yp-service | 13_service.bats | bbclass declares SYSTEMD_SERVICE with both override separators |
| FR-019 | yp-service | 13_service.bats | bbclass never falls back to sysvinit registration |
| FR-019 | yp-service | 13_service.bats | full image installs the sample service |
| FR-019 | yp-service | 13_service.bats | sample recipe inherits yp-service and ships a unit file |
| FR-019 | yp-service | 13_service.bats | sample unit targets multi-user and logs to journal |
| FR-019 | yp-service | 13_service.bats | yp-service bbclass exists and inherits the systemd class |
| FR-020 | boot-time | 14_boottime.bats | a log without login is a failure, not a zero |
| FR-020 | boot-time | 14_boottime.bats | boot-time script is syntactically valid bash |
| FR-020 | boot-time | 14_boottime.bats | ignores runqemu INFO noise before the kernel line |
| FR-020 | boot-time | 14_boottime.bats | kernel-only log (no bootloader) still reports login and kernel |
| FR-020 | boot-time | 14_boottime.bats | mark() returns empty instead of aborting under set -e when marks file is missing |
| FR-020 | boot-time | 14_boottime.bats | monitor_stream marks login through a real tee pipe (prompt has no trailing newline) |
| FR-020 | boot-time | 14_boottime.bats | parses a normal serial log with uboot, kernel and login |
| FR-020 | boot-time | 14_boottime.bats | wall clock is never fabricated in replay mode |
| FR-021 | syntax-matrix | 15_syntax.bats | YP distro selects systemd |
| FR-021 | syntax-matrix | 15_syntax.bats | YP source directory retains the pre-UNPACKDIR fallback |
| FR-021 | syntax-matrix | 15_syntax.bats | demo recipes go through YP_SRC_DIR for their source root |
| FR-021 | syntax-matrix | 15_syntax.bats | syntax matrix has at least ten six-column data rows for all releases |
| FR-021 | syntax-matrix | 15_syntax.bats | wrynose YP init row specifies systemd |
| FR-022 | demo-statusd | 16_statusd.bats | yp-statusd unit 配置启动、重启和自启 |
| FR-022 | demo-statusd | 16_statusd.bats | yp-statusd 配方使用服务模板并从 YP_SRC_DIR 取源码 |
| FR-022 | demo-statusd | 16_statusd.bats | 配方和 unit 不使用 SysV init 注册 |
| FR-023 | demo-collectd | 17_collectd.bats | collectd unit 具有默认环境配置并加入多用户目标 |
| FR-023 | demo-collectd | 17_collectd.bats | collectd 配方使用 yp-service 并从 YP_SRC_DIR 构建 |
| FR-023 | demo-collectd | 17_collectd.bats | 采集指标写入 stdout 后立即刷新 |
| FR-023 | demo-collectd | 17_collectd.bats | 采集服务不引入旧式日志轮转或 init 注册机制 |
| FR-023 | demo-collectd | 17_collectd.bats | 默认配置文件明确纳入 collectd 软件包 |
| FR-024 | deploy-guard | 18_deployguard.bats | build.sh stamps fingerprint on success (guard's data source exists) |
| FR-024 | deploy-guard | 18_deployguard.bats | deploy-guard --all rejects combo flags (die -> exit 1) |
| FR-024 | deploy-guard | 18_deployguard.bats | deploy-guard --all runs on any machine (0=fresh/none, 1=stale, never crashes) |
| FR-024 | deploy-guard | 18_deployguard.bats | deploy-guard and build scripts are syntactically valid bash |
| FR-024 | deploy-guard | 18_deployguard.bats | deploy-guard passes quietly for a never-built combo |
| FR-024 | deploy-guard | 18_deployguard.bats | deploy-guard rejects unknown flags (die -> exit 1) |
| FR-025 | release-check | 19_releasecheck.bats | default scope follows the supported-releases single source |
| FR-025 | release-check | 19_releasecheck.bats | help describes scope and machine dimension |
| FR-025 | release-check | 19_releasecheck.bats | release-check is syntactically valid bash |
| FR-025 | release-check | 19_releasecheck.bats | unknown release is rejected before any build runs |
| FR-026 | supported-releases | 20_supported_releases.bats | every line in supported-releases is a known release |
| FR-026 | supported-releases | 20_supported_releases.bats | release-check default scope follows the single source |
| FR-026 | supported-releases | 20_supported_releases.bats | supported-releases file exists and is non-empty |
| FR-026 | supported-releases | 20_supported_releases.bats | wrynose is in the supported list (6.0 是当前单点) |
