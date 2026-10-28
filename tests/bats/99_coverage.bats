#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    FEATURES_FILE="${ROOT_DIR}/config/features.txt"
}

_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# Test 1: every declared BATS file exists.
@test "every feature references an existing BATS file" {
    local line line_number=0 feature release bats_file tag
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag <<<"${line}"
        bats_file="$(_trim "${bats_file}")"
        if [[ ! -f "${ROOT_DIR}/${bats_file}" ]]; then
            printf 'features.txt line %s: %s (missing BATS file: %s)\n' \
                "${line_number}" "${line}" "${bats_file}" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
}

# Test 2: every feature tag is declared in its BATS file.
@test "every feature tag has a matching BATS test tag" {
    local line line_number=0 feature release bats_file tag
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag <<<"${line}"
        bats_file="$(_trim "${bats_file}")"
        tag="$(_trim "${tag}")"
        if [[ -z "${tag}" ]] ||
            { [[ -f "${ROOT_DIR}/${bats_file}" ]] &&
                ! grep -Eq "^# bats test_tags=.*${tag}" "${ROOT_DIR}/${bats_file}"; }; then
            printf 'features.txt line %s: %s (missing tag: %s)\n' \
                "${line_number}" "${line}" "${tag}" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
}

# Test 3: every non-meta BATS file is represented by a feature.
@test "every non-meta BATS file is referenced by a feature" {
    local bats_path bats_file line line_number
    for bats_path in "${ROOT_DIR}"/tests/bats/*.bats; do
        [[ -e "${bats_path}" ]] || continue
        [[ "$(basename "${bats_path}")" == "99_coverage.bats" ]] && continue
        bats_file="${bats_path#"${ROOT_DIR}/"}"
        if ! awk -F'|' -v target="${bats_file}" '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            {
                file = $3
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", file)
                if (file == target) found = 1
            }
            END { exit !found }
        ' "${FEATURES_FILE}"; then
            line_number=1
            line="$(head -n 1 "${bats_path}")"
            printf '%s line %s: %s (not referenced by features.txt)\n' \
                "${bats_file}" "${line_number}" "${line}" >&2
            return 1
        fi
    done
}

# Test 4: feature records have four fields and a valid release selector.
@test "features file has four fields and known release selectors" {
    local line line_number=0 field_count feature release bats_file tag
    local releases=" all dunfell kirkstone scarthgap wrynose "
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        field_count="${line//[^|]/}"
        if [[ "${#field_count}" -ne 3 ]]; then
            printf 'features.txt line %s: %s (expected exactly four | separated fields)\n' \
                "${line_number}" "${line}" >&2
            return 1
        fi
        IFS='|' read -r feature release bats_file tag <<<"${line}"
        feature="$(_trim "${feature}")"
        release="$(_trim "${release}")"
        bats_file="$(_trim "${bats_file}")"
        tag="$(_trim "${tag}")"
        if [[ -z "${feature}" || -z "${release}" || -z "${bats_file}" || -z "${tag}" ]]; then
            printf 'features.txt line %s: %s (fields must not be empty)\n' \
                "${line_number}" "${line}" >&2
            return 1
        fi
        if [[ "${release}" != "all" ]]; then
            local invalid=0 item
            IFS=',' read -r -a release_list <<<"${release}"
            for item in "${release_list[@]}"; do
                item="$(_trim "${item}")"
                if [[ "${releases}" != *" ${item} "* ]]; then
                    invalid=1
                    break
                fi
            done
            if ((invalid)); then
                printf 'features.txt line %s: %s (unknown release selector: %s)\n' \
                    "${line_number}" "${line}" "${release}" >&2
                return 1
            fi
        fi
    done <"${FEATURES_FILE}"
}
