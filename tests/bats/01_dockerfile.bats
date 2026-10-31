#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
}

assert_expected_from() {
    local file="$1" version="$2"
    grep -Eq "^FROM ubuntu:${version}$" "${file}"
}

assert_pinned_ubuntu_from() {
    local file="$1"
    grep -Eq '^FROM ubuntu(:latest)?$' "${file}" && return 1
    grep -Eq '^FROM ubuntu:[^[:space:]]+$' "${file}"
}

# bats test_tags=dockerfile
@test "hadolint accepts all four build Dockerfiles" {
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        run hadolint "${ROOT_DIR}/docker/${release}/Dockerfile"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=dockerfile
@test "each release uses its required Ubuntu base" {
    local release version
    while read -r release version; do
        run assert_expected_from "${ROOT_DIR}/docker/${release}/Dockerfile" "${version}"
        [ "${status}" -eq 0 ]
    done <<'EOF'
dunfell 20.04
kirkstone 22.04
scarthgap 24.04
wrynose 24.04
EOF
}

# bats test_tags=dockerfile
@test "Ubuntu base images have an explicit non-latest tag" {
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        run assert_pinned_ubuntu_from "${ROOT_DIR}/docker/${release}/Dockerfile"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=dockerfile
@test "each Dockerfile copies the shared installer" {
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        run grep -Eq '^COPY docker/common/install-yocto-deps\.sh ' \
            "${ROOT_DIR}/docker/${release}/Dockerfile"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=dockerfile
@test "each Dockerfile runs as a non-root user" {
    local release file
    for release in dunfell kirkstone scarthgap wrynose; do
        file="${ROOT_DIR}/docker/${release}/Dockerfile"
        run grep -Eq '^USER ' "${file}"
        [ "${status}" -eq 0 ]
        run grep -Eq '^USER root([[:space:]]|$)' "${file}"
        [ "${status}" -ne 0 ]
    done
}

# bats test_tags=dockerfile
@test "each Dockerfile has the identical builder USER instruction" {
    local release file
    for release in dunfell kirkstone scarthgap wrynose; do
        file="${ROOT_DIR}/docker/${release}/Dockerfile"
        run grep -E '^USER[[:space:]]+' "${file}"
        [ "${status}" -eq 0 ]
        [ "${output}" = 'USER builder' ]
    done
}

# bats test_tags=dockerfile
@test "each Dockerfile has source and title OCI labels" {
    local release file
    for release in dunfell kirkstone scarthgap wrynose; do
        file="${ROOT_DIR}/docker/${release}/Dockerfile"
        run grep -q 'org.opencontainers.image.source=' "${file}"
        [ "${status}" -eq 0 ]
        run grep -q 'org.opencontainers.image.title=' "${file}"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=dockerfile
@test "shared installer passes shellcheck and shfmt" {
    run shellcheck "${ROOT_DIR}/docker/common/install-yocto-deps.sh"
    [ "${status}" -eq 0 ]
    run shfmt -d -i 4 -ci "${ROOT_DIR}/docker/common/install-yocto-deps.sh"
    [ "${status}" -eq 0 ]
}

# bats test_tags=dockerfile
@test "latest base negative case fails both base assertions without editing sources" {
    local tmp_file
    tmp_file="$(mktemp)"
    printf '%s\n' '# syntax=docker/dockerfile:1.7' 'FROM ubuntu:latest' >"${tmp_file}"

    run assert_expected_from "${tmp_file}" 24.04
    [ "${status}" -ne 0 ]
    run assert_pinned_ubuntu_from "${tmp_file}"
    [ "${status}" -ne 0 ]
    rm -f "${tmp_file}"
}

# bats test_tags=dockerfile
@test "release images install hadolint and actionlint" {
    # #46：release 镜像要跑 scripts/report.sh，里面有两例分别调 hadolint 与
    # actionlint。镜像缺这两个工具时归档只能临时补装，"镜像本身可复现"就没了。
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        grep -q '^ARG HADOLINT_VERSION=' "${ROOT_DIR}/docker/${release}/Dockerfile"
        grep -q '^ARG ACTIONLINT_VERSION=' "${ROOT_DIR}/docker/${release}/Dockerfile"
        grep -q 'HADOLINT_VERSION=${HADOLINT_VERSION}' \
            "${ROOT_DIR}/docker/${release}/Dockerfile"
        grep -q 'ACTIONLINT_VERSION=${ACTIONLINT_VERSION}' \
            "${ROOT_DIR}/docker/${release}/Dockerfile"
    done
    grep -q 'install-linters.sh' "${ROOT_DIR}/docker/${release}/Dockerfile"
    grep -q 'hadolint-Linux-x86_64' "${ROOT_DIR}/docker/common/install-linters.sh"
    grep -q 'rhysd/actionlint' "${ROOT_DIR}/docker/common/install-linters.sh"
    # 指纹进构建日志，否则"装了但版本不对"会静默通过
    grep -q 'hadolint=${HADOLINT_VERSION} reported=' \
        "${ROOT_DIR}/docker/common/install-linters.sh"
    grep -q 'actionlint=${ACTIONLINT_VERSION} reported=' \
        "${ROOT_DIR}/docker/common/install-linters.sh"
}

# bats test_tags=dockerfile
@test "dev image installs actionlint and records it in the fingerprint" {
    grep -q '^ARG ACTIONLINT_VERSION=' "${ROOT_DIR}/docker/dev/Dockerfile"
    grep -q 'rhysd/actionlint' "${ROOT_DIR}/docker/dev/Dockerfile"
    grep -q "actionlint=" "${ROOT_DIR}/docker/dev/Dockerfile"
}
