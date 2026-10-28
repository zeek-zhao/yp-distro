#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/report.sh <release|all> [--variant V]
  scripts/report.sh --print-fingerprint
EOF
}

source_fingerprint() {
    local path revision material="" working_tree
    for path in config docker scripts layers; do
        revision="$(git -C "${ROOT_DIR}" rev-parse --short=7 "HEAD:${path}" 2>/dev/null || true)"
        [[ -n "${revision}" ]] && material+="${revision}"
    done
    working_tree="$(git -C "${ROOT_DIR}" diff --binary HEAD -- config docker scripts layers |
        sha256sum | awk '{print $1}')"
    material+="${working_tree}"
    printf '%s' "${material}" | sha256sum | awk '{print $1}'
}

if [[ "${1:-}" == "--print-fingerprint" ]]; then
    [[ $# -eq 1 ]] || die "--print-fingerprint 不接受其他参数"
    printf 'SOURCE_FINGERPRINT=%s\n' "$(source_fingerprint)"
    exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
    usage >&2
    exit 2
fi

release="$1"
shift
variant="general"
while (($# > 0)); do
    case "$1" in
        --variant)
            (($# >= 2)) || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
done

if [[ "${release}" == "all" ]]; then
    report_tag="multiple"
else
    resolve_all "${release}" "${variant}" qemux86-64
    report_tag="${TAG}"
fi

command -v bats >/dev/null 2>&1 || die "找不到 bats"
command -v python3 >/dev/null 2>&1 || die "找不到 python3（解析 JUnit 报告需要）"

date_stamp="$(date +%Y%m%d)"
start_time="$(date --iso-8601=seconds)"
commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
fingerprint="$(source_fingerprint)"
hostname="$(hostname)"
mkdir -p "${ROOT_DIR}/reports" "${ROOT_DIR}/docs/qa/${release}"
output_dir="$(mktemp -d "${ROOT_DIR}/reports/.bats-report.XXXXXX")"
target_xml="${ROOT_DIR}/reports/bats-${release}-${variant}-${date_stamp}.xml"

SECONDS=0
if bats --formatter junit --output "${output_dir}" -r "${ROOT_DIR}/tests/bats" \
    >"${output_dir}/bats.xml"; then
    bats_status=0
else
    bats_status=$?
fi
duration="${SECONDS}"
end_time="$(date --iso-8601=seconds)"

junit_source="${output_dir}/bats.xml"
if [[ ! -f "${junit_source}" ]]; then
    rmdir "${output_dir}" 2>/dev/null || true
    log_error "Bats 未生成预期的 JUnit 文件：${junit_source}"
    exit 1
fi
mv -- "${junit_source}" "${target_xml}"
rmdir "${output_dir}"

summary="$(
    python3 - "${target_xml}" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
tests = failures = skipped = 0
failure_rows = []
for suite in suites:
    tests += int(suite.attrib.get("tests", 0))
    failures += int(suite.attrib.get("failures", 0)) + int(suite.attrib.get("errors", 0))
    skipped += int(suite.attrib.get("skipped", 0))
    for case in suite.findall("testcase"):
        for result in list(case):
            if result.tag in ("failure", "error"):
                message = result.attrib.get("message", "").replace("\n", " ").strip()
                failure_rows.append(
                    f"- `{case.attrib.get('classname', '')}::{case.attrib.get('name', '')}`: {message}"
                )
print(tests)
print(failures)
print(skipped)
print("\n".join(failure_rows))
PY
)" || {
    log_error "无法解析 JUnit 报告：${target_xml}"
    exit 1
}
tests="$(printf '%s\n' "${summary}" | sed -n '1p')"
failures="$(printf '%s\n' "${summary}" | sed -n '2p')"
skipped="$(printf '%s\n' "${summary}" | sed -n '3p')"
passed=$((tests - failures - skipped))
failure_list="$(printf '%s\n' "${summary}" | tail -n +4)"

printf '+---------+-------+--------+--------+--------+----------+\n'
printf '| Release | Tests | Passed | Failed | Skipped | Duration |\n'
printf '+---------+-------+--------+--------+--------+----------+\n'
printf '| %-7s | %5s | %6s | %6s | %6s | %6ss   |\n' \
    "${release}" "${tests}" "${passed}" "${failures}" "${skipped}" "${duration}"
printf '+---------+-------+--------+--------+--------+----------+\n'
printf 'JUnit: %s\n' "${target_xml#${ROOT_DIR}/}"

archive="${ROOT_DIR}/docs/qa/${release}/${date_stamp}-${commit}.md"
{
    printf '# BATS QA Report\n\n'
    printf -- '- Release: `%s`\n' "${release}"
    printf -- '- Variant: `%s`\n' "${variant}"
    printf -- '- Commit: `%s`\n' "${commit}"
    printf -- '- Tag: `%s`\n' "${report_tag}"
    printf -- '- SOURCE_FINGERPRINT: `%s`\n' "${fingerprint}"
    printf -- '- Hostname: `%s`\n' "${hostname}"
    printf -- '- Start time: `%s`\n' "${start_time}"
    printf -- '- End time: `%s`\n' "${end_time}"
    printf -- '- Duration: `%ss`\n' "${duration}"
    printf -- '- Image digest: n/a（P0 未实现）\n'
    printf -- '- Artifact SHA-256: n/a（P0 未实现）\n\n'
    printf '## Test statistics\n\n'
    printf '| Tests | Passed | Failed | Skipped |\n|---:|---:|---:|---:|\n'
    printf '| %s | %s | %s | %s |\n\n' \
        "${tests}" "${passed}" "${failures}" "${skipped}"
    printf '## Failures\n\n'
    if [[ -n "${failure_list}" ]]; then
        printf '%s\n' "${failure_list}"
    else
        printf 'None\n'
    fi
} >"${archive}"
printf 'Archive: %s\n' "${archive#${ROOT_DIR}/}"

exit "${bats_status}"
