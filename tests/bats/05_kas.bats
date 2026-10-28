#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    KAS_DIR="${ROOT_DIR}/kas"
    VERIFY_SCRIPT="${ROOT_DIR}/scripts/kas-verify.py"
}

# bats test_tags=kas
@test "kas configuration contains the complete release and variant matrix" {
    local yml_count target_count release variant
    yml_count="$(find "${KAS_DIR}" -name '*.yml' | wc -l)"
    target_count="$(find "${KAS_DIR}/targets" -name '*.yml' | wc -l)"
    [ "${yml_count}" -eq 16 ]
    [ "${target_count}" -eq 8 ]
    for release in dunfell kirkstone scarthgap wrynose; do
        for variant in general custom; do
            [ -f "${KAS_DIR}/targets/${release}-${variant}.yml" ]
        done
    done
}

# bats test_tags=kas
@test "builtin validator checks all eight targets" {
    run python3 "${VERIFY_SCRIPT}" --engine builtin
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"8 targets OK"* ]]
}

# bats test_tags=kas
@test "validator rejects release tags that drift from config" {
    local test_root
    test_root="${BATS_TEST_TMPDIR}/kas-root"
    mkdir -p "${test_root}"
    cp -R "${KAS_DIR}" "${test_root}/kas"
    cp -R "${ROOT_DIR}/config" "${test_root}/config"
    sed -i 's/tag: yocto-5\.0\.20/tag: yocto-5.0.21/' \
        "${test_root}/kas/releases/scarthgap.yml"
    run python3 "${VERIFY_SCRIPT}" --engine builtin --root "${test_root}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"FAIL"* ]]
}

# bats test_tags=kas
@test "every kas YAML declares header version 14" {
    run python3 -c '
from pathlib import Path
import sys
import yaml
root = Path(sys.argv[1])
files = sorted((root / "kas").rglob("*.yml"))
assert len(files) == 16, len(files)
for path in files:
    assert yaml.safe_load(path.read_text())["header"]["version"] == 14, path
' "${ROOT_DIR}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=kas
@test "base configuration does not define repositories" {
    run grep -q '^repos:' "${KAS_DIR}/base.yml"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "wrynose declares split repositories without poky" {
    local repo
    run grep -q '^  poky:' "${KAS_DIR}/releases/wrynose.yml"
    [ "${status}" -eq 1 ]
    for repo in openembedded-core bitbake meta-yocto; do
        grep -q "${repo}:" "${KAS_DIR}/releases/wrynose.yml"
    done
}

# bats test_tags=kas
@test "custom variant uses the agreed YP variable name" {
    grep -q 'YP_VARIANT = "custom"' "${KAS_DIR}/variants/custom.yml"
    run grep -c 'ZEEK_VARIANT' "${KAS_DIR}/variants/custom.yml"
    [ "${status}" -eq 1 ]
    [ "${output}" = "0" ]
}

# bats test_tags=kas
@test "dev Dockerfile installs kas and records its fingerprint" {
    grep -Fq 'kas==${KAS_VERSION}' "${ROOT_DIR}/docker/dev/Dockerfile"
    grep -Fq "printf 'kas=%s" "${ROOT_DIR}/docker/dev/Dockerfile"
}

# bats test_tags=kas
@test "kas command is wired through Makefile and project CLI" {
    grep -Eq '^PROJECT_TARGETS = .*([[:space:]]|^)kas([[:space:]]|$)' "${ROOT_DIR}/Makefile"
    grep -q 'kas ' "${ROOT_DIR}/project.sh"
    grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas$' \
        "${ROOT_DIR}/config/features.txt"
}

# bats test_tags=kas
@test "kas feature and BATS tag registration match" {
    grep -q '^# bats test_tags=kas$' "${BATS_TEST_DIRNAME}/05_kas.bats"
    grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas$' \
        "${ROOT_DIR}/config/features.txt"
}
