#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    WF_DIR="${ROOT_DIR}/.github/workflows"
    CI_YML="${WF_DIR}/ci.yml"
    IMG_YML="${WF_DIR}/images.yml"
    PULL_YML="${WF_DIR}/pull-check.yml"
}

fail() {
    printf '%s\n' "$*" >&2
    return 1
}

# bats test_tags=ci
@test "three workflow files exist and are nonempty" {
    local file
    for file in "${CI_YML}" "${IMG_YML}" "${PULL_YML}"; do
        run test -s "${file}"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=ci
@test "actionlint accepts every workflow without skipping" {
    local tool
    tool="$(command -v actionlint || true)"
    if [[ -z "${tool}" && -x "${HOME}/.local/bin/actionlint" ]]; then
        tool="${HOME}/.local/bin/actionlint"
    fi
    if [[ -z "${tool}" ]]; then
        fail "先跑 scripts/ci/install-tools.sh --prefix $HOME/.local"
        return 1
    fi
    run "${tool}" "${WF_DIR}"/*.yml
    [ "${status}" -eq 0 ]
}

# bats test_tags=ci
@test "image matrix releases and series match Dockerfiles and configurations" {
    run python3 - "${ROOT_DIR}" "${IMG_YML}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
workflow = pathlib.Path(sys.argv[2]).read_text()
pairs = re.findall(
    r'^\s+- release: ([a-z0-9-]+)\s*\n\s+series: "([0-9.]+)"\s*$',
    workflow, re.M,
)
matrix = dict(pairs)
dockerfiles = {
    path.parent.name: path for path in (root / "docker").glob("*/Dockerfile")
    if path.parent.name != "dev"
}
configs = {path.stem for path in (root / "config").glob("*.env")}
assert len(pairs) == len(matrix) == 4, pairs
assert set(matrix) == set(dockerfiles) == configs, (matrix, dockerfiles, configs)
for release, path in dockerfiles.items():
    series = re.findall(r'\bYOCTO_SERIES=["\']?([0-9.]+)', path.read_text())
    assert series and set(series) == {matrix[release]}, (release, series)
PY
    [ "${status}" -eq 0 ]
}

# bats test_tags=ci
@test "images use the automatic token and github contains no personal credentials" {
    run grep -F 'secrets.GITHUB_TOKEN' "${IMG_YML}"
    [ "${status}" -eq 0 ]
    run grep -R -nE 'ghp_|github_pat_|PERSONAL_ACCESS' "${ROOT_DIR}/.github"
    [ "${status}" -eq 1 ]
}

# bats test_tags=ci
@test "images grant package writes and push using the repository build context" {
    local pattern
    for pattern in \
        '^[[:space:]]+packages: write$' \
        '^[[:space:]]+push: true$' \
        '^[[:space:]]+context: \.$' \
        '^[[:space:]]+file: docker/\$\{\{ matrix.release \}\}/Dockerfile$'; do
        run grep -E "${pattern}" "${IMG_YML}"
        [ "${status}" -eq 0 ]
    done
}

# bats test_tags=ci
@test "L1 never builds images" {
    run grep -E 'build-push-action|docker[[:space:]]+build' "${CI_YML}"
    [ "${status}" -eq 1 ]
}

# bats test_tags=ci
@test "pull check remains anonymous" {
    run grep -E 'login-action|docker[[:space:]]+login|GITHUB_TOKEN' "${PULL_YML}"
    [ "${status}" -eq 1 ]
}

# bats test_tags=ci
@test "all workflow runners are pinned to ubuntu 24.04" {
    run python3 - "${CI_YML}" "${IMG_YML}" "${PULL_YML}" <<'PY'
import pathlib
import re
import sys

for filename in sys.argv[1:]:
    text = pathlib.Path(filename).read_text()
    runners = re.findall(r'^\s*runs-on:\s*(.+)$', text, re.M)
    assert runners and all(runner == "ubuntu-24.04" for runner in runners), runners
    assert "ubuntu-latest" not in text
PY
    [ "${status}" -eq 0 ]
}

# bats test_tags=ci
@test "all action references are pinned to major versions" {
    run python3 - "${WF_DIR}" <<'PY'
import pathlib
import re
import sys

references = []
for path in pathlib.Path(sys.argv[1]).glob("*.yml"):
    references.extend(re.findall(r'^\s*-?\s*uses:\s*(.+)$', path.read_text(), re.M))
assert references
assert all(re.fullmatch(r'[A-Za-z0-9_./-]+@v[0-9]+', ref) for ref in references), references
PY
    [ "${status}" -eq 0 ]
}

# bats test_tags=ci
@test "tool installer help lists every tool and prefix option" {
    run bash "${ROOT_DIR}/scripts/ci/install-tools.sh" --help
    [ "${status}" -eq 0 ]
    local item
    for item in shellcheck shfmt bats hadolint actionlint --prefix; do
        [[ "${output}" == *"${item}"* ]]
    done
}

# bats test_tags=ci
@test "tracked repository passes credential scanning" {
    run bash "${ROOT_DIR}/scripts/ci/secret-scan.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"secret-scan: clean ("* ]]
}

# bats test_tags=ci
@test "main is guarded by a branch guard job requiring PR provenance" {
    run grep -E '^  branch-guard:$' "${CI_YML}"
    [ "${status}" -eq 0 ]
    run grep -F "github.ref == 'refs/heads/main'" "${CI_YML}"
    [ "${status}" -eq 0 ]
    run grep -E '^[[:space:]]+pull-requests: read$' "${CI_YML}"
    [ "${status}" -eq 0 ]
    run grep -F '/commits/${SHA}/pulls' "${CI_YML}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=ci
@test "promised gates exist in repository: pre-push hook and make hooks" {
    run test -x "${ROOT_DIR}/.githooks/pre-push"
    [ "${status}" -eq 0 ]
    run grep -E '^hooks:$' "${ROOT_DIR}/Makefile"
    [ "${status}" -eq 0 ]
    run grep -F 'refs/heads/main' "${ROOT_DIR}/.githooks/pre-push"
    [ "${status}" -eq 0 ]
}
