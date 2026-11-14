# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
# 模块: 容器与镜像

@FR-002 @feature:docker-images @evidence:static
Feature: [docker-images] docker-images（证据级别 static，适用 release: all）
  BATS 源: tests/bats/01_dockerfile.bats（tag dockerfile）

  Scenario: hadolint accepts all four build Dockerfiles
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "hadolint accepts all four build Dockerfiles"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each release uses its required Ubuntu base
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "each release uses its required Ubuntu base"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: Ubuntu base images have an explicit non-latest tag
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "Ubuntu base images have an explicit non-latest tag"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each Dockerfile copies the shared installer
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "each Dockerfile copies the shared installer"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each Dockerfile runs as a non-root user
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "each Dockerfile runs as a non-root user"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each Dockerfile has the identical builder USER instruction
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "each Dockerfile has the identical builder USER instruction"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: each Dockerfile has source and title OCI labels
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "each Dockerfile has source and title OCI labels"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: shared installer passes shellcheck and shfmt
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "shared installer passes shellcheck and shfmt"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: latest base negative case fails both base assertions without editing sources
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "latest base negative case fails both base assertions without editing sources"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: release images install hadolint and actionlint
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "release images install hadolint and actionlint"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dev image installs actionlint and records it in the fingerprint
    Given features.txt 将 docker-images 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/01_dockerfile.bats 的用例 "dev image installs actionlint and records it in the fingerprint"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-004 @feature:container-runtime @evidence:build
Feature: [container-runtime] container-runtime（证据级别 build，适用 release: all）
  BATS 源: tests/bats/03_container.bats（tag container）

  Scenario: image guard skips when the release image is absent
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "image guard skips when the release image is absent"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: missing release image
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "missing release image"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: help describes dry-run mode
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "help describes dry-run mode"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: all local release images pass container preflight
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "all local release images pass container preflight"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dry-run uses the stable release and variant container name
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "dry-run uses the stable release and variant container name"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dry-run maps the host uid and never runs privileged
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "dry-run maps the host uid and never runs privileged"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: download and sstate directories are under the repository work mount
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "download and sstate directories are under the repository work mount"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dry-run includes a read-only passwd mount from the host repository
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "dry-run includes a read-only passwd mount from the host repository"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: dry-run prints exactly one command line on stdout
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "dry-run prints exactly one command line on stdout"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: nested dry-run accepts an invisible host path without mounting docker binaries
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "nested dry-run accepts an invisible host path without mounting docker binaries"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: nested dry-run mounts host docker paths when dev provides them
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "nested dry-run mounts host docker paths when dev provides them"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: relative host repository paths are rejected
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "relative host repository paths are rejected"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: running container resolves builder with the non-root host uid and gid
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "running container resolves builder with the non-root host uid and gid"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: low disk watermark blocks container preflight with cleanup guidance
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "low disk watermark blocks container preflight with cleanup guidance"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: unknown release fails and names the requested release
    Given features.txt 将 container-runtime 注册为 build 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "unknown release fails and names the requested release"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
@FR-018 @feature:kvm-accel @evidence:static
Feature: [kvm-accel] kvm-accel（证据级别 static，适用 release: all）
  BATS 源: tests/bats/03_container.bats（tag container）

  Scenario: preflight reports kvm acceleration capability without failing
    Given features.txt 将 kvm-accel 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "preflight reports kvm acceleration capability without failing"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: kvm device is forwarded when the host exposes it
    Given features.txt 将 kvm-accel 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "kvm device is forwarded when the host exposes it"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
  Scenario: missing kvm degrades to tcg without blocking preflight
    Given features.txt 将 kvm-accel 注册为 static 级证据（适用 release: all）
    When 运行 tests/bats/03_container.bats 的用例 "missing kvm degrades to tcg without blocking preflight"
    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/
