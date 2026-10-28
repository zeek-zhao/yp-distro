#!/usr/bin/env bash
# Runs BATS and generates a real-build QA report.
# Artifact details come from kas build output under work/; this script does not build.
# Use --render-only to create an archive without running tests or writing JUnit output.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=lib/artifacts.sh
source "${ROOT_DIR}/scripts/lib/artifacts.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/report.sh <release|all> [--variant V] [--render-only]
  scripts/report.sh --release R [--variant V] [--render-only]
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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    [[ $# -eq 1 ]] || die "--help 不接受其他参数"
    usage
    exit 0
fi

release=""
variant="general"
render_only=0
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die "--release 缺少参数"
            [[ -z "${release}" ]] || die "release 只能指定一次"
            release="$2"
            shift 2
            ;;
        --variant)
            (($# >= 2)) || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --render-only)
            render_only=1
            shift
            ;;
        -h | --help)
            [[ $# -eq 1 ]] || die "--help 不接受其他参数"
            usage
            exit 0
            ;;
        -*)
            die "未知参数：$1"
            ;;
        *)
            [[ -z "${release}" ]] || die "release 只能指定一次"
            release="$1"
            shift
            ;;
    esac
done
[[ -n "${release}" ]] || {
    usage >&2
    exit 2
}

if [[ "${release}" == "all" ]]; then
    report_tag="multiple"
    machine=""
    image=""
else
    resolve_all "${release}" "${variant}" qemux86-64
    report_tag="${TAG}"
    machine="${MACHINE}"
    image="${IMAGE}"
fi

if ((render_only == 0)); then
    command -v bats >/dev/null 2>&1 || die "找不到 bats"
    command -v python3 >/dev/null 2>&1 || die "找不到 python3（解析 JUnit 报告需要）"
fi

date_stamp="$(date +%Y%m%d)"
start_time="$(date --iso-8601=seconds)"
commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
fingerprint="$(source_fingerprint)"
hostname="$(hostname)"
mkdir -p "${ROOT_DIR}/docs/qa/${release}"
duration=0
bats_status=0
tests="n/a"
passed="n/a"
failures="n/a"
skipped="n/a"
failure_list=""

if ((render_only == 0)); then
    mkdir -p "${ROOT_DIR}/reports"
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
else
    end_time="$(date --iso-8601=seconds)"
fi

if [[ "${release}" != "all" ]]; then
    if [[ -n "${YP_DEPLOY_DIR:-}" ]]; then
        deploy_dir="${YP_DEPLOY_DIR}"
        [[ "${deploy_dir}" == /* ]] || deploy_dir="${ROOT_DIR}/${deploy_dir}"
    else
        deploy_dir="${ROOT_DIR}/work/kas-${release}-${variant}/build/tmp/deploy/images/${machine}"
    fi
    if primary_artifact="$(artifact_primary "${deploy_dir}" "${image}" "${machine}")"; then
        :
    else
        primary_artifact=""
    fi
    artifact_paths=()
    while IFS= read -r artifact_path; do
        [[ -n "${artifact_path}" ]] && artifact_paths+=("${artifact_path}")
    done < <(artifact_list "${deploy_dir}" "${image}" "${machine}")
else
    deploy_dir=""
    primary_artifact=""
    artifact_paths=()
fi

relative_path() {
    local path="$1"
    if [[ "${path}" == "${ROOT_DIR}/"* ]]; then
        printf '%s' "${path#"${ROOT_DIR}/"}"
    else
        printf '%s' "${path}"
    fi
}

if ((${#artifact_paths[@]} > 0)); then
    checksum_file="${ROOT_DIR}/docs/qa/${release}/artifacts.sha256"
    {
        printf '# Source: release=%s variant=%s commit=%s\n' \
            "${release}" "${variant}" "${commit}"
        for artifact_path in "${artifact_paths[@]}"; do
            printf '%s  %s\n' "$(artifact_sha256 "${artifact_path}")" \
                "$(relative_path "${artifact_path}")"
        done
    } >"${checksum_file}"
fi

degraded_file="${YP_DEGRADED_FILE:-${ROOT_DIR}/config/degraded.txt}"
[[ -f "${degraded_file}" ]] || die "降级配置不存在：${degraded_file}"
degraded_rows=()
while IFS='|' read -r aspect degraded_release reason requirement || [[ -n "${aspect:-}" ]]; do
    aspect="$(printf '%s' "${aspect:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    degraded_release="$(printf '%s' "${degraded_release:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    reason="$(printf '%s' "${reason:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    requirement="$(printf '%s' "${requirement:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${aspect}" || "${aspect}" == \#* ]] && continue
    [[ "${degraded_release}" == "${release}" ]] || continue
    degraded_rows+=("${aspect}|${reason}|${requirement}")
done <"${degraded_file}"

serial_log="${ROOT_DIR}/work/artifacts/${release}/${variant}/qemu-serial.log"
serial_exists=0
serial_login="no"
serial_bytes=""
if [[ -f "${serial_log}" ]]; then
    serial_exists=1
    grep -qi 'login:' "${serial_log}" && serial_login="yes"
    serial_bytes="$(stat -c %s -- "${serial_log}")"
fi

archive_name="${date_stamp}-${commit}"
((render_only == 0)) || archive_name+="-render"
archive="${ROOT_DIR}/docs/qa/${release}/${archive_name}.md"
{
    printf '# QA Report\n\n'
    if ((render_only)); then
        printf -- '- Kind: `render-only`\n'
    else
        printf -- '- Kind: `bats+build`\n'
    fi
    printf -- '- Release: `%s`\n' "${release}"
    printf -- '- Variant: `%s`\n' "${variant}"
    printf -- '- Commit: `%s`\n' "${commit}"
    printf -- '- Tag: `%s`\n' "${report_tag}"
    printf -- '- SOURCE_FINGERPRINT: `%s`\n' "${fingerprint}"
    printf -- '- Hostname: `%s`\n' "${hostname}"
    printf -- '- Start time: `%s`\n' "${start_time}"
    printf -- '- End time: `%s`\n' "${end_time}"
    printf -- '- Duration: `%ss`\n\n' "${duration}"
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
    printf '\n## 构建产物\n\n'
    if [[ -n "${primary_artifact}" ]]; then
        printf -- '- Deploy dir: `%s`\n' "$(relative_path "${deploy_dir}")"
        printf -- '- Artifact: `%s`\n' "$(basename "${primary_artifact}")"
        printf -- '- Artifact bytes: `%s`\n' "$(artifact_bytes "${primary_artifact}")"
        printf -- '- Artifact SHA-256: `%s`\n' "$(artifact_sha256 "${primary_artifact}")"
        printf -- '- Image digest: n/a（本地构建无 registry digest）\n'
        printf -- '- 全部产物 sha256: 见 `artifacts.sha256`（同目录，路径相对仓库根）\n'
    else
        printf -- '- Deploy dir: `%s`\n' \
            "$([[ -n "${deploy_dir}" ]] && relative_path "${deploy_dir}" || printf 'n/a')"
        printf -- '- Artifact: n/a（未构建）\n'
        printf -- '- Artifact bytes: n/a（未构建）\n'
        printf -- '- Artifact SHA-256: n/a（未构建）\n'
        printf -- '- Image digest: n/a（本地构建无 registry digest）\n'
    fi
    printf '\n## QEMU 串口\n\n'
    if ((serial_exists)); then
        printf -- '- 串口日志: `work/artifacts/%s/%s/qemu-serial.log`\n' \
            "${release}" "${variant}"
        printf -- '- 启动到 login prompt: `%s`（匹配到 `login:`）\n' "${serial_login}"
        printf -- '- 日志字节数: `%s`\n' "${serial_bytes}"
    else
        printf -- '- 串口日志: n/a（本次未执行 QEMU）\n'
    fi
    printf '\n## 降级清单\n\n'
    if ((${#degraded_rows[@]} == 0)); then
        printf '无（本版本全部能力按标准实现）\n'
    else
        printf '| aspect | 理由 | 需求条款 |\n|---|---|---|\n'
        for row in "${degraded_rows[@]}"; do
            IFS='|' read -r aspect reason requirement <<<"${row}"
            printf '| `%s` | %s | %s |\n' "${aspect}" "${reason}" "${requirement}"
        done
    fi
} >"${archive}"

if ((render_only == 0)); then
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf '| Release | Tests | Passed | Failed | Skipped | Duration |\n'
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf '| %-7s | %5s | %6s | %6s | %6s | %6ss   |\n' \
        "${release}" "${tests}" "${passed}" "${failures}" "${skipped}" "${duration}"
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf 'JUnit: %s\n' "${target_xml#${ROOT_DIR}/}"
fi
printf 'Archive: %s\n' "${archive#${ROOT_DIR}/}"

exit "${bats_status}"
