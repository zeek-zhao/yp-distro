# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 工程入口与命令行

@FR-001 @feature:entry-unified @evidence:static
Feature: [entry-unified] entry-unified（证据级别 static，适用 release: all）
  BATS 源: tests/bats/00_project.bats（tag entry）

  Scenario: four release configurations resolve to their expected tags
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "four release configurations resolve to their expected tags"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: help lists every implemented command
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "help lists every implemented command"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: custom variant resolves the wrynose configuration
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "custom variant resolves the wrynose configuration"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unknown release fails with an error message
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "unknown release fails with an error message"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: doctor lists all eight release and variant combinations
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "doctor lists all eight release and variant combinations"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unimplemented build command exits with status two
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "unimplemented build command exits with status two"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: configuration environment files do not use export
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "configuration environment files do not use export"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each implemented command has a successful command-level help
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "each implemented command has a successful command-level help"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: shell help lists its dry-run and runtime options
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "shell help lists its dry-run and runtime options"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unimplemented commands write one reason to stderr and exit two
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "unimplemented commands write one reason to stderr and exit two"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: test tags are forwarded to Bats as a filter
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "test tags are forwarded to Bats as a filter"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: shell dry-run prints one safe scarthgap docker command
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "shell dry-run prints one safe scarthgap docker command"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: shell dry-run applies defaults and launches a login shell
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "shell dry-run applies defaults and launches a login shell"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: shell requires a release using the standard error path
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "shell requires a release using the standard error path"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report defaults to all releases and general variant
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "report defaults to all releases and general variant"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unknown shell options use the standard usage error status
    Given features.txt 将 entry-unified 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/00_project.bats 的用例 "unknown shell options use the standard usage error status"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
