# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 发布与部署工程

@FR-024 @feature:deploy-guard @evidence:build
Feature: [deploy-guard] deploy-guard（证据级别 build，适用 release: all）
  BATS 源: tests/bats/18_deployguard.bats（tag deploy-guard）

  Scenario: deploy-guard and build scripts are syntactically valid bash
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "deploy-guard and build scripts are syntactically valid bash"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build.sh stamps fingerprint on success (guard's data source exists)
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "build.sh stamps fingerprint on success (guard's data source exists)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: deploy-guard --all runs on any machine (0=fresh/none, 1=stale, never crashes)
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "deploy-guard --all runs on any machine (0=fresh/none, 1=stale, never crashes)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: deploy-guard --all rejects combo flags (die -> exit 1)
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "deploy-guard --all rejects combo flags (die -> exit 1)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: deploy-guard rejects unknown flags (die -> exit 1)
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "deploy-guard rejects unknown flags (die -> exit 1)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: deploy-guard passes quietly for a never-built combo
    Given features.txt 将 deploy-guard 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/18_deployguard.bats 的用例 "deploy-guard passes quietly for a never-built combo"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-025 @feature:release-check @evidence:build
Feature: [release-check] release-check（证据级别 build，适用 release: all）
  BATS 源: tests/bats/19_releasecheck.bats（tag release-check）

  Scenario: release-check is syntactically valid bash
    Given features.txt 将 release-check 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/19_releasecheck.bats 的用例 "release-check is syntactically valid bash"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: default scope follows the supported-releases single source
    Given features.txt 将 release-check 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/19_releasecheck.bats 的用例 "default scope follows the supported-releases single source"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unknown release is rejected before any build runs
    Given features.txt 将 release-check 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/19_releasecheck.bats 的用例 "unknown release is rejected before any build runs"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: help describes scope and machine dimension
    Given features.txt 将 release-check 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/19_releasecheck.bats 的用例 "help describes scope and machine dimension"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
