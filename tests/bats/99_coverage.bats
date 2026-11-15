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

# Test 4: feature records have five or six fields (第六列 = 证据级别，#131)，
#         valid releases, and valid status.
@test "features file has five fields, known releases, and valid status" {
    local line line_number=0 field_count feature release bats_file tag status evidence
    local releases=" all dunfell kirkstone scarthgap wrynose "
    local evidence_levels=" static build boot runtime "
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        field_count="${line//[^|]/}"
        if [[ "${#field_count}" -ne 4 && "${#field_count}" -ne 5 ]]; then
            printf 'features.txt line %s: %s (expected five or six | separated fields)\n' \
                "${line_number}" "${line}" >&2
            return 1
        fi
        IFS='|' read -r feature release bats_file tag status evidence rest <<<"${line}"
        feature="$(_trim "${feature}")"
        release="$(_trim "${release}")"
        bats_file="$(_trim "${bats_file}")"
        tag="$(_trim "${tag}")"
        status="$(_trim "${status}")"
        evidence="$(_trim "${evidence:-}")"
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
        if [[ -n "${evidence}" && "${evidence_levels}" != *" ${evidence} "* ]]; then
            printf 'features.txt line %s: %s (invalid evidence level: %s)\n' \
                "${line_number}" "${line}" "${evidence}" >&2
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
# （解析兼容六字段格式：多余列忽略）
@test "every degraded feature has a matching degraded-list reason" {
    local line feature release bats_file tag status aspect degraded_release reason requirement
    local feature_line=0 found degraded_covers release_item
    local -a feature_releases=()
    local extra
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        # 六字段格式（#131 证据级别列）：extra 吃掉多余列，status 保持纯净
        IFS='|' read -r feature release bats_file tag status extra <<<"${line}"
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
    # 只认「<date>-<sha>…md」这类构建报告：SDK 归档（sdk-<date>-<sha>.md）没有
    # 降级清单节，混进来会让本用例误判“最新报告缺节”。
    while IFS= read -r line; do
        report_files+=("${report_dir}/${line}")
    done < <(find "${report_dir}" -maxdepth 1 -type f -name '[0-9]*.md' -printf '%f\n' |
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

# Test 7: 表头列数与数据行列数必须一致（#131 表头补第 6 列「证据级别」后收口：
# 此前表头 5 列、数据 6 列，靠 Test 4 放宽到 5 或 6 字段硬扛）。
@test "features file header and data rows have the same column count" {
    local line line_number=0 header_pipes=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        local pipes
        pipes="${line//[^|]/}"
        if [[ -z "${header_pipes}" ]]; then
            header_pipes="${pipes}"
        elif [[ "${#pipes}" -ne "${#header_pipes}" ]]; then
            printf 'features.txt line %s: 表头 %s 列，此行 %s 列\n' \
                "${line_number}" "$(( ${#header_pipes} + 1 ))" "$(( ${#pipes} + 1 ))" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
    [[ -n "${header_pipes}" ]] || {
        printf 'features.txt 没有可解析的表头行\n' >&2
        return 1
    }
}

# Test 8: features.txt 第 6 列证据级别必须与 verification-flow §6.1 矩阵「档位」一致
# （文档单点失守的解药：矩阵漂移直接判红，不再靠人眼对 26 行）。
@test "features evidence levels match verification-flow section 6.1 matrix" {
    local matrix_file="${ROOT_DIR}/docs/01-requirements/verification-flow.md"
    local -A matrix_level=()
    local line feature release bats_file tag status evidence line_number=0
    local in_matrix=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "### 6.1 矩阵" ]]; then
            in_matrix=1
            continue
        fi
        [[ "${in_matrix}" == 1 ]] || continue
        [[ "${line}" == '### '* ]] && break
        if [[ "${line}" =~ ^\|[[:space:]]*[0-9]+[[:space:]]*\|[[:space:]]*\`([^\`]+)\`[[:space:]]*\|[[:space:]]*([a-z]+)[[:space:]]*\| ]]; then
            matrix_level["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done <"${matrix_file}"
    ((${#matrix_level[@]} > 0)) || {
        printf '§6.1 矩阵解析为空，请检查 %s 的矩阵表格式\n' "${matrix_file}" >&2
        return 1
    }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag status evidence rest <<<"${line}"
        feature="$(_trim "${feature}")"
        evidence="$(_trim "${evidence:-}")"
        if [[ -z "${evidence}" ]]; then
            printf 'features.txt line %s: %s 缺第 6 列证据级别\n' "${line_number}" "${feature}" >&2
            return 1
        fi
        if [[ -z "${matrix_level[${feature}]:-}" ]]; then
            printf 'features.txt line %s: %s 不在 §6.1 矩阵中\n' "${line_number}" "${feature}" >&2
            return 1
        fi
        if [[ "${matrix_level[${feature}]}" != "${evidence}" ]]; then
            printf 'features.txt line %s: %s 档位 %s ≠ §6.1 矩阵 %s\n' \
                "${line_number}" "${feature}" "${evidence}" "${matrix_level[${feature}]}" >&2
            return 1
        fi
    done <"${FEATURES_FILE}"
}

# Test 9: evidence=runtime 的 feature 必须在 smoke 动作集（scripts/smoke.sh）里有
# 对应动作——verification-flow.md:145 声称的绑定，此前只是头注口号，无人校验。
@test "runtime features are covered by the smoke action set" {
    local smoke_file="${ROOT_DIR}/scripts/smoke.sh"
    local line feature release bats_file tag status evidence
    local -a runtime_features=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*$ || "${line}" =~ ^[[:space:]]*# ]] && continue
        IFS='|' read -r feature release bats_file tag status evidence rest <<<"${line}"
        [[ "$(_trim "${evidence:-}")" == "runtime" ]] && runtime_features+=("$(_trim "${feature}")")
    done <"${FEATURES_FILE}"
    ((${#runtime_features[@]} > 0)) || {
        printf 'features.txt 没有 runtime 档位的 feature，动作集绑定无从校验\n' >&2
        return 1
    }
    local f
    for f in "${runtime_features[@]}"; do
        case "${f}" in
            yp-service)
                grep -Fq 'for svc in yp-hello-svc yp-statusd yp-collectd' "${smoke_file}" || {
                    printf 'yp-service：smoke 动作集缺自有服务 is-enabled/is-active 组\n' >&2
                    return 1
                }
                ;;
            demo-statusd)
                grep -Fq 'SM|statusd-json|' "${smoke_file}" || {
                    printf 'demo-statusd：smoke 动作集缺 statusd-json 动作\n' >&2
                    return 1
                }
                ;;
            demo-collectd)
                grep -Fq 'SM|collectd-journal|' "${smoke_file}" || {
                    printf 'demo-collectd：smoke 动作集缺 collectd-journal 动作\n' >&2
                    return 1
                }
                ;;
            *)
                printf 'runtime feature %s 在 99_coverage.bats 的 smoke 映射里没有登记，请补 case 分支\n' "${f}" >&2
                return 1
                ;;
        esac
    done
}
