# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 运行时与服务演示

@FR-012 @feature:distro-backfill @evidence:static
Feature: [distro-backfill] distro-backfill（证据级别 static，适用 release: wrynose）
  本特性无自动化 bats 用例（degraded/static），以文档证据归档为准。

  Scenario: 文档证据——无自动化用例，按 degraded 登记口径归档
    Given features.txt 将该特性标记为 degraded 且无 bats 映射
    When 审阅 docs/features.md 与 docs/qa/ 对应 degraded 登记
    Then 证据级别为 static 且 degraded.txt 有对应登记原因
@FR-019 @feature:yp-service @evidence:runtime
Feature: [yp-service] yp-service（证据级别 runtime，适用 release: wrynose）
  BATS 源: tests/bats/13_service.bats（tag service）

  Scenario: yp-service bbclass exists and inherits the systemd class
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "yp-service bbclass exists and inherits the systemd class"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: bbclass declares SYSTEMD_SERVICE with both override separators
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "bbclass declares SYSTEMD_SERVICE with both override separators"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: bbclass never falls back to sysvinit registration
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "bbclass never falls back to sysvinit registration"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sample recipe inherits yp-service and ships a unit file
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "sample recipe inherits yp-service and ships a unit file"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sample unit targets multi-user and logs to journal
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "sample unit targets multi-user and logs to journal"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: full image installs the sample service
    Given features.txt 将 yp-service 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/13_service.bats 的用例 "full image installs the sample service"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-020 @feature:boot-time @evidence:boot
Feature: [boot-time] boot-time（证据级别 boot，适用 release: wrynose）
  BATS 源: tests/bats/14_boottime.bats（tag boottime）

  Scenario: boot-time script is syntactically valid bash
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "boot-time script is syntactically valid bash"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: parses a normal serial log with uboot, kernel and login
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "parses a normal serial log with uboot, kernel and login"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: ignores runqemu INFO noise before the kernel line
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "ignores runqemu INFO noise before the kernel line"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: a log without login is a failure, not a zero
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "a log without login is a failure, not a zero"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kernel-only log (no bootloader) still reports login and kernel
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "kernel-only log (no bootloader) still reports login and kernel"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: wall clock is never fabricated in replay mode
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "wall clock is never fabricated in replay mode"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: monitor_stream marks login through a real tee pipe (prompt has no trailing newline)
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "monitor_stream marks login through a real tee pipe (prompt has no trailing newline)"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: mark() returns empty instead of aborting under set -e when marks file is missing
    Given features.txt 将 boot-time 注册为 boot 级证据（适用 release: wrynose）
    When 运行 tests/bats/14_boottime.bats 的用例 "mark() returns empty instead of aborting under set -e when marks file is missing"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-022 @feature:demo-statusd @evidence:runtime
Feature: [demo-statusd] demo-statusd（证据级别 runtime，适用 release: wrynose）
  BATS 源: tests/bats/16_statusd.bats（tag demo）

  Scenario: yp-statusd 配方使用服务模板并从 YP_SRC_DIR 取源码
    Given features.txt 将 demo-statusd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/16_statusd.bats 的用例 "yp-statusd 配方使用服务模板并从 YP_SRC_DIR 取源码"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: yp-statusd unit 配置启动、重启和自启
    Given features.txt 将 demo-statusd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/16_statusd.bats 的用例 "yp-statusd unit 配置启动、重启和自启"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: 配方和 unit 不使用 SysV init 注册
    Given features.txt 将 demo-statusd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/16_statusd.bats 的用例 "配方和 unit 不使用 SysV init 注册"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-023 @feature:demo-collectd @evidence:runtime
Feature: [demo-collectd] demo-collectd（证据级别 runtime，适用 release: wrynose）
  BATS 源: tests/bats/17_collectd.bats（tag demo）

  Scenario: collectd 配方使用 yp-service 并从 YP_SRC_DIR 构建
    Given features.txt 将 demo-collectd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/17_collectd.bats 的用例 "collectd 配方使用 yp-service 并从 YP_SRC_DIR 构建"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: collectd unit 具有默认环境配置并加入多用户目标
    Given features.txt 将 demo-collectd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/17_collectd.bats 的用例 "collectd unit 具有默认环境配置并加入多用户目标"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: 默认配置文件明确纳入 collectd 软件包
    Given features.txt 将 demo-collectd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/17_collectd.bats 的用例 "默认配置文件明确纳入 collectd 软件包"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: 采集服务不引入旧式日志轮转或 init 注册机制
    Given features.txt 将 demo-collectd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/17_collectd.bats 的用例 "采集服务不引入旧式日志轮转或 init 注册机制"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: 采集指标写入 stdout 后立即刷新
    Given features.txt 将 demo-collectd 注册为 runtime 级证据（适用 release: wrynose）
    When 运行 tests/bats/17_collectd.bats 的用例 "采集指标写入 stdout 后立即刷新"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
