#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    mkdir -p "${ROOT_DIR}/work"
    test_root="$(mktemp -d "${ROOT_DIR}/work/crossdiff-test.XXXXXX")"
}

teardown() {
    if [[ -n "${render_archive:-}" ]]; then
        rm -f -- "${render_archive}"
    fi
    rm -r -- "${test_root}"
}

validate_crossdiff() {
    local releases="" path
    for path in "${ROOT_DIR}"/config/*.env; do
        path="${path##*/}"
        releases+=" ${path%.env}"
    done
    awk -F'|' -v releases="${releases}" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        function invalid(reason) {
            printf "%s:%d: %s\n", FILENAME, FNR, reason > "/dev/stderr"
            failed = 1
        }
        BEGIN {
            count = split(trim(releases), names, /[[:space:]]+/)
            for (i = 1; i <= count; i++) legal[names[i]] = 1
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            rows++
            aspect = trim($1)
            if (aspect == "" || aspects[aspect]++) invalid("empty or duplicate aspect")
            if (NF < 3) invalid("expected at least three columns")
            for (i = 2; i <= NF; i++) {
                field = trim($i)
                separator = index(field, "=")
                name = substr(field, 1, separator - 1)
                value = trim(substr(field, separator + 1))
                if (!separator || !(name in legal) || value == "")
                    invalid("expected known release=nonempty value")
                if (seen[NR, name]++) invalid("duplicate release")
            }
        }
        END {
            if (!rows) invalid("no data rows")
            exit failed
        }
    ' "$1"
}

render_crossdiff_report() {
    run env YP_DEPLOY_DIR="${test_root}/no-artifacts" "$@" \
        bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant general --render-only
    [ "${status}" -eq 0 ]
    render_archive="${ROOT_DIR}/${output##*Archive: }"
    crossdiff_section="$(sed -n '/^## 跨版本差异$/,$p' "${render_archive}")"
    [[ "${crossdiff_section}" == *"## 跨版本差异"* ]]
}

# bats test_tags=crossdiff
@test "crossdiff source has unique aspects and known releases with nonempty values" {
    run validate_crossdiff "${ROOT_DIR}/config/crossdiff.txt"
    [ "${status}" -eq 0 ]
}

# bats test_tags=crossdiff
@test "crossdiff validator rejects malformed fixtures under repo work" {
    local bad
    for bad in \
        'kernel | wrynose=6.18' \
        'kernel | unknown=6.6 | wrynose=6.18' \
        'kernel | scarthgap=6.6 | wrynose=6.18|extra' \
        'kernel | scarthgap=6.6 | wrynose= ' \
        'kernel | wrynose=6.18 | wrynose=6.18' \
        $'kernel | scarthgap=6.6 | wrynose=6.18\nkernel | scarthgap=6.6 | wrynose=6.18'; do
        printf '%s\n' "${bad}" >"${test_root}/bad.txt"
        run validate_crossdiff "${test_root}/bad.txt"
        [ "${status}" -ne 0 ]
        [[ "${output}" == *"${test_root}/bad.txt:"* ]]
    done
}

# bats test_tags=crossdiff
@test "render-only report contains one crossdiff table row per source aspect" {
    render_crossdiff_report
    local expected actual
    expected="$(awk '!/^[[:space:]]*(#|$)/ { count++ } END { print count+0 }' \
        "${ROOT_DIR}/config/crossdiff.txt")"
    actual="$(printf '%s\n' "${crossdiff_section}" | grep -c '^| `')"
    [ "${expected}" -gt 0 ]
    [ "${actual}" -eq "${expected}" ]
    [[ "${crossdiff_section}" == *'| aspect | 本版本(wrynose) | scarthgap |'* ]]
}

# Issue #19「不许复制粘贴」验收：报告的 wrynose 与 scarthgap 列至少一行不同。
# bats test_tags=crossdiff
@test "rendered wrynose and scarthgap values are not copy pasted" {
    render_crossdiff_report
    printf '%s\n' "${crossdiff_section}" | awk -F'|' '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        /^\| aspect / {
            for (i = 3; i < NF; i++) {
                if (trim($i) == "本版本(wrynose)") current = i
                if (trim($i) == "scarthgap") other = i
            }
        }
        /^\| `/ {
            if (current && other && trim($current) != trim($other)) different++
        }
        END { exit !(different > 0) }
    '
}

# bats test_tags=crossdiff
@test "crossdiff without a comparable archive is n/a and does not add degraded items" {
    local fixture="${test_root}/crossdiff.txt" kind
    for kind in missing empty single absent-current; do
        case "${kind}" in
            missing) ;;
            empty) printf '# no archives\n' >"${fixture}" ;;
            single) printf 'kernel | wrynose=6.18\n' >"${fixture}" ;;
            absent-current) printf 'kernel | scarthgap=6.6 | kirkstone=5.15\n' >"${fixture}" ;;
        esac
        render_crossdiff_report YP_CROSSDIFF_FILE="${fixture}"
        [ "${crossdiff_section}" = $'## 跨版本差异\n\nn/a（尚无其它版本归档，无可比对象）' ]
        ! grep -Fq 'cross-version-diff' "${render_archive}"
    done
}

# bats test_tags=crossdiff
@test "crossdiff renders all release columns by name rather than source position" {
    cat >"${test_root}/crossdiff.txt" <<'EOF'
kernel | scarthgap=6.6 | wrynose=6.18 | kirkstone=5.15
gcc | kirkstone=11.% | scarthgap=13.% | wrynose=15.%
EOF
    render_crossdiff_report YP_CROSSDIFF_FILE="${test_root}/crossdiff.txt"
    [[ "${crossdiff_section}" == *'| aspect | 本版本(wrynose) | scarthgap | kirkstone |'* ]]
    [[ "${crossdiff_section}" == *'| `kernel` | 6.18 | 6.6 | 5.15 |'* ]]
    [[ "${crossdiff_section}" == *'| `gcc` | 15.% | 13.% | 11.% |'* ]]
}
