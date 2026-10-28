#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
}

# bats test_tags=entry
@test "four release configurations resolve to their expected tags" {
    local release repo_mode tag

    while read -r release repo_mode tag; do
        run project config --release "${release}" --variant general --machine qemux86-64
        [ "${status}" -eq 0 ]
        [[ "${output}" == *"RELEASE=${release}"* ]]
        [[ "${output}" == *"REPO_MODE=${repo_mode}"* ]]
        [[ "${output}" == *"TAG=${tag}"* ]]
    done <<'EOF'
dunfell poky yocto-3.1.33
kirkstone poky yocto-4.0.35
scarthgap poky yocto-5.0.20
wrynose split yocto-6.0.4
EOF
}

# bats test_tags=entry
@test "help lists every implemented command" {
    run project --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"config"* ]]
    [[ "${output}" == *"doctor"* ]]
    [[ "${output}" == *"test"* ]]
    [[ "${output}" == *"report"* ]]
}

# bats test_tags=entry
@test "custom variant resolves the wrynose configuration" {
    run project config --release wrynose --variant custom --machine qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DISTRO=yp"* ]]
    [[ "${output}" == *"IMAGE=yp-image"* ]]
    [[ "${output}" == *"REPO_MODE=split"* ]]
}

# bats test_tags=entry
@test "unknown release fails with an error message" {
    run project config --release bogus --variant general --machine qemux86-64
    [ "${status}" -ne 0 ]
    [ -n "${output}" ]
}

# bats test_tags=entry
@test "doctor lists all eight release and variant combinations" {
    run project doctor
    [ "${status}" -eq 0 ]
    count="$(printf '%s\n' "${output}" | grep -Ec '^(dunfell|kirkstone|scarthgap|wrynose) ' || true)"
    [ "${count}" -eq 8 ]
}

# bats test_tags=entry
@test "unimplemented build command exits with status two" {
    run project build
    [ "${status}" -eq 2 ]
}

# bats test_tags=entry
@test "configuration environment files do not use export" {
    matches="$(grep -R -n '^export' "${ROOT_DIR}/config" --include='*.env' || true)"
    [ -z "${matches}" ]
}

# bats test_tags=entry
@test "each implemented command has a successful command-level help" {
    local command_name

    for command_name in config doctor test report lint secret-scan ci-tools hooks image shell; do
        run project "${command_name}" --help
        [ "${status}" -eq 0 ]
        [ -n "${output}" ]
    done
}

# bats test_tags=entry
@test "shell help lists its dry-run and runtime options" {
    run project shell --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--dry-run"* ]]
    [[ "${output}" == *"--release"* ]]
}

# bats test_tags=entry
@test "unimplemented commands write one reason to stderr and exit two" {
    local command_name expected_reason stdout_file stderr_file

    stdout_file="${BATS_TEST_TMPDIR}/not-implemented.stdout"
    stderr_file="${BATS_TEST_TMPDIR}/not-implemented.stderr"
    for command_name in source build qemu review e2e; do
        run bash -c '"$1" "$2" >"$3" 2>"$4"; printf "%s" "$?"' \
            _ "${ROOT_DIR}/project.sh" "${command_name}" \
            "${stdout_file}" "${stderr_file}"
        [ "${status}" -eq 0 ]
        [ "${output}" = 2 ]
        [ ! -s "${stdout_file}" ]
        case "${command_name}" in
            source) expected_reason="C40 已改由 kas checkout 取代" ;;
            build) expected_reason="P1 #17 kas 落地后接管" ;;
            *) expected_reason="P2 阶段" ;;
        esac
        [ "$(cat "${stderr_file}")" = \
            "not implemented yet: ${command_name}（${expected_reason}）" ]
    done
}

# bats test_tags=entry
@test "test tags are forwarded to Bats as a filter" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat >"${BATS_TEST_TMPDIR}/bin/bats" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/bats"

    run env PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
        "${ROOT_DIR}/project.sh" test --tags entry
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--filter-tags"* ]]
    [[ "${output}" == *"entry"* ]]
}

# bats test_tags=entry
@test "shell dry-run prints one safe scarthgap docker command" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat >"${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/docker"

    run env -u WB_HOST_REPO_DIR -u WB_HOST_DOCKER_BIN \
        -u WB_HOST_DOCKER_PLUGIN_DIR \
        PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
        "${ROOT_DIR}/project.sh" shell --release scarthgap \
        --variant general --dry-run
    [ "${status}" -eq 0 ]
    [ "$(printf '%s\n' "${output}" | wc -l)" -eq 1 ]
    [[ "${output}" == *"--name yocto-scarthgap-general"* ]]
    [[ "${output}" != *"privileged"* ]]
}

# bats test_tags=entry
@test "shell dry-run applies defaults and launches a login shell" {
    mkdir -p "${BATS_TEST_TMPDIR}/bin"
    cat >"${BATS_TEST_TMPDIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${BATS_TEST_TMPDIR}/bin/docker"

    run env -u WB_HOST_REPO_DIR -u WB_HOST_DOCKER_BIN \
        -u WB_HOST_DOCKER_PLUGIN_DIR \
        PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" \
        "${ROOT_DIR}/project.sh" shell --release wrynose \
        --variant custom --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"--name yocto-wrynose-custom"* ]]
    [[ "${output}" == *"bash -l"* ]]
}

# bats test_tags=entry
@test "shell requires a release using the standard error path" {
    run env -u WB_HOST_REPO_DIR -u WB_HOST_DOCKER_BIN \
        -u WB_HOST_DOCKER_PLUGIN_DIR "${ROOT_DIR}/project.sh" shell
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"shell 必须指定 --release"* ]]
}

# bats test_tags=entry
@test "report defaults to all releases and general variant" {
    run project report --help
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[--release R]"* ]]
    [[ "${output}" == *"[--variant V]"* ]]
}

# bats test_tags=entry
@test "unknown shell options use the standard usage error status" {
    run env -u WB_HOST_REPO_DIR -u WB_HOST_DOCKER_BIN \
        -u WB_HOST_DOCKER_PLUGIN_DIR "${ROOT_DIR}/project.sh" \
        shell --release scarthgap --unknown
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"未知参数：--unknown"* ]]
}
