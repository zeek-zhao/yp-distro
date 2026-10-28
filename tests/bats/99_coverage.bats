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
    local line line_number=0 feature release bats_file tag status
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag status <<<"${line}"
        bats_file="$(_trim "${bats_file}")"
        [[ "${bats_file}" == "-" ]] && continue
        if [[ ! -f "${ROOT_DIR}/${bats_file}" ]]; then
            printf 'features.txt line %s: %s (missing BATS file: %s)\n' \
                "${line_number}" "${line}" "${bats_file}" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
}

# Test 2: every feature tag is declared in its BATS file.
@test "every feature tag has a matching BATS test tag" {
    local line line_number=0 feature release bats_file tag status
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag status <<<"${line}"
        bats_file="$(_trim "${bats_file}")"
        tag="$(_trim "${tag}")"
        [[ "${bats_file}" == "-" && "${tag}" == "-" ]] && continue
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

# Test 4: feature records have five fields, valid releases, and valid status.
@test "features file has five fields, known releases, and valid status" {
    local line line_number=0 field_count feature release bats_file tag status
    local releases=" all dunfell kirkstone scarthgap wrynose "
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        field_count="${line//[^|]/}"
        if [[ "${#field_count}" -ne 4 ]]; then
            printf 'features.txt line %s: %s (expected exactly five | separated fields)\n' \
                "${line_number}" "${line}" >&2
            return 1
        fi
        IFS='|' read -r feature release bats_file tag status <<<"${line}"
        feature="$(_trim "${feature}")"
        release="$(_trim "${release}")"
        bats_file="$(_trim "${bats_file}")"
        tag="$(_trim "${tag}")"
        status="$(_trim "${status}")"
        if [[ -z "${feature}" || -z "${release}" || -z "${bats_file}" ||
            -z "${tag}" || -z "${status}" ]]; then
            printf 'features.txt line %s: %s (fields must not be empty)\n' \
                "${line_number}" "${line}" >&2
            return 1
        fi
        if [[ "${status}" != "ok" && "${status}" != "degraded" ]]; then
            printf 'features.txt line %s: %s (invalid status: %s)\n' \
                "${line_number}" "${line}" "${status}" >&2
            return 1
        fi
        if [[ "${bats_file}" == "-" && "${tag}" != "-" ]] ||
            [[ "${bats_file}" != "-" && "${tag}" == "-" ]]; then
            printf 'features.txt line %s: %s (BATS file and tag must both be -)\n' \
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

# Test 5: every degraded feature has a release-matching reason.
@test "every degraded feature has a matching degraded-list reason" {
    local line feature release bats_file tag status aspect degraded_release reason requirement
    local feature_line=0 found degraded_covers release_item
    local -a feature_releases=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag status <<<"${line}"
        feature="$(_trim "${feature}")"
        release="$(_trim "${release}")"
        status="$(_trim "${status}")"
        [[ "${status}" == "degraded" ]] || continue
        ((feature_line += 1))
        IFS=',' read -r -a feature_releases <<<"${release}"
        found=0
        while IFS='|' read -r aspect degraded_release reason requirement ||
            [[ -n "${aspect:-}" ]]; do
            aspect="$(_trim "${aspect:-}")"
            degraded_release="$(_trim "${degraded_release:-}")"
            [[ -z "${aspect}" || "${aspect}" == \#* ]] && continue
            [[ "${aspect}" == "${feature}" ]] || continue
            degraded_covers=1
            for release_item in "${feature_releases[@]}"; do
                release_item="$(_trim "${release_item}")"
                if [[ "${release_item}" == "all" ]]; then
                    [[ "${degraded_release}" == "all" ]] || degraded_covers=0
                elif [[ "${degraded_release}" != "all" &&
                    "${release_item}" != "${degraded_release}" ]]; then
                    degraded_covers=0
                fi
                ((degraded_covers)) || break
            done
            if ((degraded_covers)); then
                found=1
                break
            fi
        done <"${ROOT_DIR}/config/degraded.txt"
        if ((found == 0)); then
            printf 'degraded feature %s (%s) has no reason in config/degraded.txt\n' \
                "${feature}" "${release}" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
    ((feature_line > 0)) || {
        printf 'features.txt contains no degraded feature records\n' >&2
        return 1
    }
}

# Test 6: the latest report and degraded-list source must have identical aspects.
@test "latest report degraded list matches degraded.txt" {
    local release="${BATS_TEST_RELEASE:-wrynose}"
    local report_dir="${ROOT_DIR}/docs/qa/${release}"
    local latest_report line in_section=0 aspect degraded_release reason requirement
    local expected actual
    local -a report_files=()
    local -A report_aspects=() config_aspects=()

    [[ -d "${report_dir}" ]] || skip "需要报告归档"
    while IFS= read -r line; do
        report_files+=("${report_dir}/${line}")
    done < <(find "${report_dir}" -maxdepth 1 -type f -name '*.md' -printf '%f\n' |
        LC_ALL=C sort)
    ((${#report_files[@]} > 0)) || skip "需要报告归档"
    latest_report="${report_files[${#report_files[@]} - 1]}"
    grep -Fq '## 降级清单' "${latest_report}" || {
        printf '最新报告缺少降级清单节，需重新生成: %s\n' "${latest_report}" >&2
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "## 降级清单" ]]; then
            in_section=1
            continue
        fi
        [[ "${line}" == '## '* ]] && {
            ((in_section == 0)) || break
        }
        ((in_section == 1)) || continue
        if [[ "${line}" =~ ^\|[[:space:]]*\`([^\`]*)\`[[:space:]]*\| ]]; then
            report_aspects["${BASH_REMATCH[1]}"]=1
        fi
    done <"${latest_report}"
    while IFS='|' read -r aspect degraded_release reason requirement ||
        [[ -n "${aspect:-}" ]]; do
        aspect="$(_trim "${aspect:-}")"
        degraded_release="$(_trim "${degraded_release:-}")"
        [[ -z "${aspect}" || "${aspect}" == \#* ]] && continue
        [[ "${degraded_release}" == "${release}" ]] || continue
        config_aspects["${aspect}"]=1
    done <"${ROOT_DIR}/config/degraded.txt"
    expected="$(printf '%s\n' "${!config_aspects[@]}" | LC_ALL=C sort)"
    actual="$(printf '%s\n' "${!report_aspects[@]}" | LC_ALL=C sort)"
    [[ "${actual}" == "${expected}" ]] || {
        printf '报告降级项与 config/degraded.txt 不一致（报告: %s；配置: %s）\n' \
            "${actual}" "${expected}" >&2
        return 1
    }
}
