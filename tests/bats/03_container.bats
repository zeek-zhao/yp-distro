#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    source "${BATS_TEST_DIRNAME}/setup.bash"
    CONTAINER_SCRIPT="${ROOT_DIR}/scripts/container.sh"
}

# bats test_tags=container
@test "help describes dry-run mode" {
    run bash "${CONTAINER_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--dry-run"* ]]
}

# bats test_tags=container
@test "all local release images pass container preflight" {
    local release
    for release in dunfell kirkstone scarthgap wrynose; do
        run bash "${CONTAINER_SCRIPT}" --release "${release}" --check
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"RELEASE=${release}"* ]]
        [[ "${output}" == *"Resolved image: ghcr.io/zeek-zhao/yocto/${release}:local"* ]]
    done
}

# bats test_tags=container
@test "dry-run uses the stable release and variant container name" {
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --variant general --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--name yocto-scarthgap-general"* ]]
}

# bats test_tags=container
@test "dry-run maps the host uid and never runs privileged" {
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--user"* ]]
    [[ "${output}" == *"$(id -u):$(id -g)"* ]]
    [[ "${output}" != *"--user 0"* ]]
    [[ "${output}" != *"--privileged"* ]]
}

# bats test_tags=container
@test "download and sstate directories are under the repository work mount" {
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DL_DIR=/work/work/downloads"* ]]
    [[ "${output}" == *"SSTATE_DIR=/work/work/sstate"* ]]
}

# bats test_tags=container
@test "dry-run includes a read-only passwd mount from the host repository" {
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${WB_HOST_REPO_DIR:-${ROOT_DIR}}/work/home/.passwd:/etc/passwd:ro"* ]]
}

# bats test_tags=container
@test "dry-run prints exactly one command line on stdout" {
    run --separate-stderr bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == "docker run "* ]]
}

# bats test_tags=container
@test "nested dry-run accepts an invisible host path without mounting docker binaries" {
    run --separate-stderr env -u WB_HOST_DOCKER_BIN -u WB_HOST_DOCKER_PLUGIN_DIR \
        WB_HOST_REPO_DIR=/not-visible-on-purpose/yocto \
        bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"-v /not-visible-on-purpose/yocto:/work"* ]]
    [[ "${output}" == *"/not-visible-on-purpose/yocto/work/home/.passwd:/etc/passwd:ro"* ]]
    [[ "${output}" != *"/usr/local/bin/docker"* ]]
    [[ "${output}" != *"cli-plugins"* ]]
}

# bats test_tags=container
@test "nested dry-run mounts host docker paths when dev provides them" {
    run --separate-stderr env \
        WB_HOST_REPO_DIR=/host/yocto \
        WB_HOST_DOCKER_BIN=/host/usr/bin/docker \
        WB_HOST_DOCKER_PLUGIN_DIR=/host/usr/lib/docker/cli-plugins \
        bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"-v /host/usr/bin/docker:/usr/local/bin/docker:ro"* ]]
    [[ "${output}" == *"-v /host/usr/lib/docker/cli-plugins:/usr/local/lib/docker/cli-plugins:ro"* ]]
}

# bats test_tags=container
@test "relative host repository paths are rejected" {
    run env WB_HOST_REPO_DIR=relative/yocto bash "${CONTAINER_SCRIPT}" --release scarthgap --check
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"WB_HOST_REPO_DIR 必须是绝对路径"* ]]
}

# bats test_tags=container
@test "running container resolves builder with the non-root host uid and gid" {
    run --separate-stderr bash "${CONTAINER_SCRIPT}" --release scarthgap -- \
        bash -lc 'id -un; id -u; id -g; stat -c "%a" /etc/passwd'
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" = builder ]
    [ "${lines[1]}" -eq "$(id -u)" ]
    [ "${lines[1]}" -ne 0 ]
    [ "${lines[2]}" -eq "$(id -g)" ]
    [ "${lines[3]}" = 644 ]
}

# bats test_tags=container
@test "low disk watermark blocks container preflight with cleanup guidance" {
    run env WATERMARK_PCT=1 bash "${CONTAINER_SCRIPT}" --release scarthgap --check
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"work/"* ]]
}

# bats test_tags=container
@test "unknown release fails and names the requested release" {
    run bash "${CONTAINER_SCRIPT}" --release foo --check
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"foo"* ]]
}
