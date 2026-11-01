#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    source "${BATS_TEST_DIRNAME}/setup.bash"
    CONTAINER_SCRIPT="${ROOT_DIR}/scripts/container.sh"
}

# Keep image names aligned with scripts/container.sh image_name().
release_image() {
    printf 'ghcr.io/zeek-zhao/yp-distro/%s' "$1"
}

require_release_image() {
    local release="$1"
    if docker image inspect "$(release_image "${release}"):local" >/dev/null 2>&1 ||
        docker image inspect "$(release_image "${release}"):latest" >/dev/null 2>&1; then
        return 0
    fi
    skip "release image not available in this environment: ${release} (expected on CI; must run on a build node)"
}

# Pure logic tests need image resolution, but never execute Docker commands.
mock_release_image() {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat >"${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" -eq 3 && "$1" == image && "$2" == inspect &&
    "$3" == ghcr.io/zeek-zhao/yp-distro/scarthgap:local ]]; then
    exit 0
fi
printf 'Unexpected Docker command in logic test: %s\n' "$*" >&2
exit 1
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/docker"
    export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# bats test_tags=container
@test "image guard skips when the release image is absent" {
    export -f release_image require_release_image
    cat >"${BATS_TEST_TMPDIR}/image-guard.bats" <<'EOF'
@test "missing release image" {
    require_release_image does-not-exist
    return 1
}
EOF
    # Bats records skip metadata outside stdout; exercise it in a nested runner.
    run bats --formatter tap "${BATS_TEST_TMPDIR}/image-guard.bats"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ok 1 missing release image # skip release image not available in this environment: does-not-exist"* ]]
}

# bats test_tags=container
@test "help describes dry-run mode" {
    run bash "${CONTAINER_SCRIPT}" --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--dry-run"* ]]
}

# bats test_tags=container
@test "all local release images pass container preflight" {
    local release image
    for release in dunfell kirkstone scarthgap wrynose; do
        require_release_image "${release}"
        image="$(release_image "${release}"):local"
        if ! docker image inspect "${image}" >/dev/null 2>&1; then
            image="$(release_image "${release}"):latest"
        fi
        run bash "${CONTAINER_SCRIPT}" --release "${release}" --check
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"RELEASE=${release}"* ]]
        [[ "${output}" == *"Resolved image: ${image}"* ]]
    done
}

# bats test_tags=container
@test "dry-run uses the stable release and variant container name" {
    mock_release_image
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --variant general --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--name yocto-scarthgap-general"* ]]
}

# bats test_tags=container
@test "dry-run maps the host uid and never runs privileged" {
    mock_release_image
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--user"* ]]
    [[ "${output}" == *"$(id -u):$(id -g)"* ]]
    [[ "${output}" != *"--user 0"* ]]
    [[ "${output}" != *"--privileged"* ]]
}

# bats test_tags=container
@test "download and sstate directories are under the repository work mount" {
    mock_release_image
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DL_DIR=/work/work/downloads"* ]]
    [[ "${output}" == *"SSTATE_DIR=/work/work/sstate"* ]]
}

# bats test_tags=container
@test "dry-run includes a read-only passwd mount from the host repository" {
    mock_release_image
    run bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${WB_HOST_REPO_DIR:-${ROOT_DIR}}/work/home/.passwd:/etc/passwd:ro"* ]]
}

# bats test_tags=container
@test "dry-run prints exactly one command line on stdout" {
    mock_release_image
    run --separate-stderr bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == "docker run "* ]]
}

# bats test_tags=container
@test "nested dry-run accepts an invisible host path without mounting docker binaries" {
    mock_release_image
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
    mock_release_image
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
    require_release_image scarthgap
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
    mock_release_image
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

# bats test_tags=container
@test "preflight reports kvm acceleration capability without failing" {
    mock_release_image
    run --separate-stderr bash "${CONTAINER_SCRIPT}" --release scarthgap --check
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"KVM="* ]]
}

# bats test_tags=container
@test "kvm device is forwarded when the host exposes it" {
    mock_release_image
    if [[ ! -e /dev/kvm ]]; then
        skip "宿主无 /dev/kvm，本机无法覆盖透传路径"
    fi
    run --separate-stderr bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--device /dev/kvm"* ]]
    [[ "${output}" == *"--group-add"* ]]
    [[ "${output}" == *"YP_KVM=ok"* ]]
}

# bats test_tags=container
@test "missing kvm degrades to tcg without blocking preflight" {
    mock_release_image
    run --separate-stderr env YP_KVM_DEVICE=/nonexistent/kvm \
        bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"--device"* ]]
    [[ "${output}" == *"YP_KVM=unavailable"* ]]
}
