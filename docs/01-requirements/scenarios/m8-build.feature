# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: SDK 与共享缓存

@FR-011 @feature:sdk @evidence:build
Feature: [sdk] sdk（证据级别 build，适用 release: all）
  BATS 源: tests/bats/10_sdk.bats（tag sdk）

  Scenario: sdk.sh dry-run 打印工作区、产物目录与两条 bitbake 命令
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "sdk.sh dry-run 打印工作区、产物目录与两条 bitbake 命令"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sdk.sh 校验必填参数与取值
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "sdk.sh 校验必填参数与取值"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --sdk 在缺少 sdk.json 时给出可执行的下一步
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "report.sh --sdk 在缺少 sdk.json 时给出可执行的下一步"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --sdk 渲染体积、SHA-256、gcc 版本与 PASS 结论
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "report.sh --sdk 渲染体积、SHA-256、gcc 版本与 PASS 结论"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --sdk 在 devtool 不可用时判 FAIL 并返回非零
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "report.sh --sdk 在 devtool 不可用时判 FAIL 并返回非零"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --sdk 拒绝 all
    Given features.txt 将 sdk 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/10_sdk.bats 的用例 "report.sh --sdk 拒绝 all"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-014 @feature:shared-cache @evidence:static
Feature: [shared-cache] shared-cache（证据级别 static，适用 release: all）
  BATS 源: tests/bats/07_cache.bats（tag cache）

  Scenario: check_shared_cache passes for the current base configuration
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "check_shared_cache passes for the current base configuration"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: check_shared_cache rejects per-release caches
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "check_shared_cache rejects per-release caches"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: check_shared_cache rejects missing and weak cache assignments
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "check_shared_cache rejects missing and weak cache assignments"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build.sh validates required arguments and allowed values
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "build.sh validates required arguments and allowed values"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build.sh rejects concurrent builds without waiting
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "build.sh rejects concurrent builds without waiting"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build.sh dry-run prints the container command and shared cache paths
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "build.sh dry-run prints the container command and shared cache paths"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build.sh records logs and duration and preserves build failure status
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "build.sh records logs and duration and preserves build failure status"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh render-only includes build statistics
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "report.sh render-only includes build statistics"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh renders latest build metrics and n/a without adding degraded items
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "report.sh renders latest build metrics and n/a without adding degraded items"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh falls back to the 3.1 sstate summary format
    Given features.txt 将 shared-cache 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/07_cache.bats 的用例 "report.sh falls back to the 3.1 sstate summary format"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
