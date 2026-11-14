# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 合规与供应链

@FR-007 @feature:spdx-format @evidence:build
Feature: [spdx-format] spdx-format（证据级别 build，适用 release: all）
  BATS 源: tests/bats/11_compliance.bats（tag compliance）

  Scenario: compliance.sh --print-sbom 缺产物时指向 --spdx 构建
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "compliance.sh --print-sbom 缺产物时指向 --spdx 构建"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 索引型 SBOM 用聚合口径而不是「1 包」
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 索引型 SBOM 用聚合口径而不是「1 包」"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 索引型对位不全时判 FAIL
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 索引型对位不全时判 FAIL"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sbom-stats.py 同时认 SPDX 2.2 与 3.0.1
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "sbom-stats.py 同时认 SPDX 2.2 与 3.0.1"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sbom-stats.py 对无法识别的文档返回非零
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "sbom-stats.py 对无法识别的文档返回非零"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sbom-stats.py 认索引型文档并按 documentNamespace 对位聚合
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "sbom-stats.py 认索引型文档并按 documentNamespace 对位聚合"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: sbom-stats.py 不传 --spdx-dir 时索引型只报形态不聚合
    Given features.txt 将 spdx-format 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "sbom-stats.py 不传 --spdx-dir 时索引型只报形态不聚合"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-008 @feature:cve-tool @evidence:static
Feature: [cve-tool] cve-tool（证据级别 static，适用 release: all）
  BATS 源: tests/bats/11_compliance.bats（tag compliance）

  Scenario: compliance.sh 校验必填参数与 --only 取值
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "compliance.sh 校验必填参数与 --only 取值"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: compliance.sh status 在未采集时报缺失而不是失败
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "compliance.sh status 在未采集时报缺失而不是失败"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 缺 compliance.json 时给出可执行的下一步
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 缺 compliance.json 时给出可执行的下一步"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 出五节归档并判 PASS
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 出五节归档并判 PASS"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 对 6.0 写 sbom-cve-check 而不是“不适用”
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 对 6.0 写 sbom-cve-check 而不是“不适用”"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 有节缺失时判 FAIL 并返回非零
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 有节缺失时判 FAIL 并返回非零"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: report.sh --compliance 拒绝 all
    Given features.txt 将 cve-tool 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "report.sh --compliance 拒绝 all"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-009 @feature:cve-db @evidence:build
Feature: [cve-db] cve-db（证据级别 build，适用 release: dunfell,kirkstone,scarthgap）
  BATS 源: tests/bats/09_cvedb.bats（tag cvedb）

  Scenario: build 5.0 产出 cve-check 认的 8 列库，并丢弃 Rejected
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "build 5.0 产出 cve-check 认的 8 列库，并丢弃 Rejected"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: build 3.1 产出 6 列库（没有 SCOREV4/VECTORSTRING）
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "build 3.1 产出 6 列库（没有 SCOREV4/VECTORSTRING）"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: derive 从 8 列库投影出的 3.1 库与直接 build 等价
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "derive 从 8 列库投影出的 3.1 库与直接 build 等价"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: PRODUCTS 表保住 cve-check 匹配所需的版本区间语义
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "PRODUCTS 表保住 cve-check 匹配所需的版本区间语义"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: node 里首条 cpeMatch 不是 vulnerable 时整条 node 不入 PRODUCTS（对齐上游 return）
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "node 里首条 cpeMatch 不是 vulnerable 时整条 node 不入 PRODUCTS（对齐上游 return）"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: verify 拒绝列结构不匹配的库
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "verify 拒绝列结构不匹配的库"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: verify 拒绝空库
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "verify 拒绝空库"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: cve-db.sh 的 status 里 wrynose 走 nvd-fkie 的 git 库而不是 sqlite
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "cve-db.sh 的 status 里 wrynose 走 nvd-fkie 的 git 库而不是 sqlite"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: cve-db.sh 接受 --release wrynose，未知 release 仍被拒绝
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "cve-db.sh 接受 --release wrynose，未知 release 仍被拒绝"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kas 基线把 CVE 库固定成离线模式
    Given features.txt 将 cve-db 注册为 build 级证据（适用 release: dunfell,kirkstone,scarthgap）
    When 运行 tests/bats/09_cvedb.bats 的用例 "kas 基线把 CVE 库固定成离线模式"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-010 @feature:foss-scan @evidence:build
Feature: [foss-scan] foss-scan（证据级别 build，适用 release: all）
  BATS 源: tests/bats/11_compliance.bats（tag compliance）

  Scenario: foss-summary.py 按实际产出的 json 记账，失败包不进成功率
    Given features.txt 将 foss-scan 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/11_compliance.bats 的用例 "foss-summary.py 按实际产出的 json 记账，失败包不进成功率"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-016 @feature:do-scancode @evidence:static
Feature: [do-scancode] do-scancode（证据级别 static，适用 release: all）
  BATS 源: tests/bats/11_scancode.bats（tag scancode）

  Scenario: scancode.sh status 覆盖四个 release 且版本按镜像 python 选
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "scancode.sh status 覆盖四个 release 且版本按镜像 python 选"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: scancode.sh path 给出容器内绝对路径，路径带版本与 python
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "scancode.sh path 给出容器内绝对路径，路径带版本与 python"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: scarthgap 与 wrynose 共用同一份 scancode
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "scarthgap 与 wrynose 共用同一份 scancode"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: scancode.sh 拒绝缺少 --release 的 path 与未知 release
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "scancode.sh 拒绝缺少 --release 的 path 与未知 release"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: scancode-toolkit-native 的 shim 配方已删除且无人依赖
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "scancode-toolkit-native 的 shim 配方已删除且无人依赖"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: do_scancode 走外部 CLI，不写 DEPENDS
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "do_scancode 走外部 CLI，不写 DEPENDS"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: do_scancode 必须显式传 --processes 并忽略工作目录噪音
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "do_scancode 必须显式传 --processes 并忽略工作目录噪音"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: do_scancode 默认跳过且不进任何镜像
    Given features.txt 将 do-scancode 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/11_scancode.bats 的用例 "do_scancode 默认跳过且不进任何镜像"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
