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
    [[ "${output}" == *"DISTRO=zeek-distro"* ]]
    [[ "${output}" == *"IMAGE=core-image-zeek"* ]]
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
