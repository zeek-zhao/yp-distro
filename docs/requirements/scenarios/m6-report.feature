# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 报告与验证取证

@FR-013 @feature:report-archive @evidence:static
Feature: [report-archive] report-archive（证据级别 static，适用 release: all）
  BATS 源: tests/bats/06_report.bats（tag report）

  Scenario: report script help exits successfully
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "report script help exits successfully"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report CLI accepts positional and --release forms equivalently
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "report CLI accepts positional and --release forms equivalently"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact primary prefers ext4 and list excludes manifests
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact primary prefers ext4 and list excludes manifests"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact primary prefers zstd ext4 and list keeps zstd tarballs
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact primary prefers zstd ext4 and list keeps zstd tarballs"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact primary fails when no image exists
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact primary fails when no image exists"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact sha256 matches a known digest
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact sha256 matches a known digest"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact bytes follows symlinks in deploy dir
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact bytes follows symlinks in deploy dir"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact list excludes qemuboot.conf
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact list excludes qemuboot.conf"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: render-only report includes configured degraded aspects
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "render-only report includes configured degraded aspects"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact helpers accept pre-5.0 naming without rootfs segment
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact helpers accept pre-5.0 naming without rootfs segment"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact helpers fall back to timestamped aliases and do not double count
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact helpers fall back to timestamped aliases and do not double count"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: artifact list prefers short names when both naming styles coexist
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "artifact list prefers short names when both naming styles coexist"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report archive name carries the variant, general stays unsuffixed
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "report archive name carries the variant, general stays unsuffixed"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: checksum file name follows the archive so old reports stay consistent
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "checksum file name follows the archive so old reports stay consistent"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report archive name carries the machine for non-default machines
    Given features.txt 将 report-archive 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/06_report.bats 的用例 "report archive name carries the machine for non-default machines"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-015 @feature:cross-version-diff @evidence:static
Feature: [cross-version-diff] cross-version-diff（证据级别 static，适用 release: all）
  BATS 源: tests/bats/08_crossdiff.bats（tag crossdiff）

  Scenario: crossdiff source has unique aspects and known releases with nonempty values
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "crossdiff source has unique aspects and known releases with nonempty values"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: crossdiff validator rejects malformed fixtures under repo work
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "crossdiff validator rejects malformed fixtures under repo work"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: render-only report contains one crossdiff table row per source aspect
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "render-only report contains one crossdiff table row per source aspect"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: rendered wrynose and scarthgap values are not copy pasted
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "rendered wrynose and scarthgap values are not copy pasted"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: crossdiff without a comparable archive is n/a and does not add degraded items
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "crossdiff without a comparable archive is n/a and does not add degraded items"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: crossdiff renders all release columns by name rather than source position
    Given features.txt 将 cross-version-diff 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/08_crossdiff.bats 的用例 "crossdiff renders all release columns by name rather than source position"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-021 @feature:syntax-matrix @evidence:build
Feature: [syntax-matrix] syntax-matrix（证据级别 build，适用 release: all）
  BATS 源: tests/bats/15_syntax.bats（tag syntax）

  Scenario: syntax matrix has at least ten six-column data rows for all releases
    Given features.txt 将 syntax-matrix 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/15_syntax.bats 的用例 "syntax matrix has at least ten six-column data rows for all releases"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: wrynose YP init row specifies systemd
    Given features.txt 将 syntax-matrix 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/15_syntax.bats 的用例 "wrynose YP init row specifies systemd"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: demo recipes go through YP_SRC_DIR for their source root
    Given features.txt 将 syntax-matrix 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/15_syntax.bats 的用例 "demo recipes go through YP_SRC_DIR for their source root"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: YP source directory retains the pre-UNPACKDIR fallback
    Given features.txt 将 syntax-matrix 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/15_syntax.bats 的用例 "YP source directory retains the pre-UNPACKDIR fallback"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: YP distro selects systemd
    Given features.txt 将 syntax-matrix 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/15_syntax.bats 的用例 "YP distro selects systemd"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
