# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 层与发行版配置

@FR-005 @feature:layer-structure @evidence:static
Feature: [layer-structure] layer-structure（证据级别 static，适用 release: all）
  BATS 源: tests/bats/04_layer.bats（tag layer）

  Scenario: layer declares exactly the four supported release series
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "layer declares exactly the four supported release series"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: yp distro declares the agreed identity
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "yp distro declares the agreed identity"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: yp distro selects systemd before poky and requires both includes after identity
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "yp distro selects systemd before poky and requires both includes after identity"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: release include is the sole source of version codename and maintainer
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "release include is the sole source of version codename and maintainer"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: compat include is currently comments only and documents all releases
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "compat include is currently comments only and documents all releases"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: yp images both require the oe-core minimal image
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "yp images both require the oe-core minimal image"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: full image installs the cpp example by real package name
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "full image installs the cpp example by real package name"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: minimal image adds only branding, no business or debug packages
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "minimal image adds only branding, no business or debug packages"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: layer configuration and core recipes have no unsupported colon overrides
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "layer configuration and core recipes have no unsupported colon overrides"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: general variant leaves the oe-core image untouched
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "general variant leaves the oe-core image untouched"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: active layer config tests and docs contain no retired names
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "active layer config tests and docs contain no retired names"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: yp distro and images do not overwrite inherited feature baselines
    Given features.txt 将 layer-structure 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/04_layer.bats 的用例 "yp distro and images do not overwrite inherited feature baselines"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-006 @feature:kas-layer @evidence:static
Feature: [kas-layer] kas-layer（证据级别 static，适用 release: all）
  BATS 源: tests/bats/05_kas.bats（tag kas）

  Scenario: kas configuration contains the complete release and variant matrix
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "kas configuration contains the complete release and variant matrix"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: builtin validator checks all eight targets
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "builtin validator checks all eight targets"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: validator rejects release tags that drift from config
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "validator rejects release tags that drift from config"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: every kas YAML declares header version 14
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "every kas YAML declares header version 14"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: base configuration does not define repositories
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "base configuration does not define repositories"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: wrynose declares split repositories without poky
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "wrynose declares split repositories without poky"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: custom variant uses the agreed YP variable name
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "custom variant uses the agreed YP variable name"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: custom variant references meta-yp as a local repository
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "custom variant references meta-yp as a local repository"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: wrynose keeps bitbake out of BBLAYERS
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "wrynose keeps bitbake out of BBLAYERS"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: release-specific knobs match each Yocto version
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "release-specific knobs match each Yocto version"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: distro layer inherits the CVE class only when the variant asks for it
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "distro layer inherits the CVE class only when the variant asks for it"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dev Dockerfile installs kas and records its fingerprint
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "dev Dockerfile installs kas and records its fingerprint"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kas command is wired through Makefile and project CLI
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "kas command is wired through Makefile and project CLI"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kas feature and BATS tag registration match
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "kas feature and BATS tag registration match"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build env bounds the parallelism by min(cores, 20)
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "build env bounds the parallelism by min(cores, 20)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: disk monitor keeps both STOPTASKS and ABORT tiers
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "disk monitor keeps both STOPTASKS and ABORT tiers"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: buildhistory writes one repository per release and variant
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "buildhistory writes one repository per release and variant"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: mirror tarballs are generated for git sources
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "mirror tarballs are generated for git sources"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: machine dimension keeps config and kas machine files in pairs
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "machine dimension keeps config and kas machine files in pairs"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: machine suffix only appears for non-default machines
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "machine suffix only appears for non-default machines"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kas targets never hardcode a non-default machine
    Given features.txt 将 kas-layer 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/05_kas.bats 的用例 "kas targets never hardcode a non-default machine"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-017 @feature:distro-features @evidence:build
Feature: [distro-features] distro-features（证据级别 build，适用 release: all）
  BATS 源: tests/bats/12_distro.bats（tag distro）

  Scenario: systemd is selected before poky consumes INIT_MANAGER
    Given features.txt 将 distro-features 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/12_distro.bats 的用例 "systemd is selected before poky consumes INIT_MANAGER"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: distro removes only the selected features with both override syntaxes
    Given features.txt 将 distro-features 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/12_distro.bats 的用例 "distro removes only the selected features with both override syntaxes"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: distro does not explicitly remove systemd or sysvinit as a feature
    Given features.txt 将 distro-features 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/12_distro.bats 的用例 "distro does not explicitly remove systemd or sysvinit as a feature"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
