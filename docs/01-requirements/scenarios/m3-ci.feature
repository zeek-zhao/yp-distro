# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: CI 流水线治理

@FR-003 @feature:ci-workflows @evidence:static
Feature: [ci-workflows] ci-workflows（证据级别 static，适用 release: all）
  BATS 源: tests/bats/02_workflows.bats（tag ci）

  Scenario: three workflow files exist and are nonempty
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "three workflow files exist and are nonempty"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: actionlint accepts every workflow without skipping
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "actionlint accepts every workflow without skipping"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: image matrix releases and series match Dockerfiles and configurations
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "image matrix releases and series match Dockerfiles and configurations"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: images use the automatic token and github contains no personal credentials
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "images use the automatic token and github contains no personal credentials"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: images grant package writes and push using the repository build context
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "images grant package writes and push using the repository build context"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: L1 never builds images
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "L1 never builds images"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: pull check remains anonymous
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "pull check remains anonymous"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: all workflow runners are pinned to ubuntu 24.04
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "all workflow runners are pinned to ubuntu 24.04"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: all action references are pinned to major versions
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "all action references are pinned to major versions"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: tool installer help lists every tool and prefix option
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "tool installer help lists every tool and prefix option"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: tracked repository passes credential scanning
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "tracked repository passes credential scanning"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: main is guarded by a branch guard job requiring PR provenance
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "main is guarded by a branch guard job requiring PR provenance"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: promised gates exist in repository: pre-push hook and make hooks
    Given features.txt 将 ci-workflows 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/02_workflows.bats 的用例 "promised gates exist in repository: pre-push hook and make hooks"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-026 @feature:supported-releases @evidence:static
Feature: [supported-releases] supported-releases（证据级别 static，适用 release: all）
  BATS 源: tests/bats/20_supported_releases.bats（tag release-check）

  Scenario: supported-releases file exists and is non-empty
    Given features.txt 将 supported-releases 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/20_supported_releases.bats 的用例 "supported-releases file exists and is non-empty"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: every line in supported-releases is a known release
    Given features.txt 将 supported-releases 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/20_supported_releases.bats 的用例 "every line in supported-releases is a known release"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: wrynose is in the supported list (6.0 是当前单点)
    Given features.txt 将 supported-releases 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/20_supported_releases.bats 的用例 "wrynose is in the supported list (6.0 是当前单点)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: release-check default scope follows the single source
    Given features.txt 将 supported-releases 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/20_supported_releases.bats 的用例 "release-check default scope follows the single source"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
