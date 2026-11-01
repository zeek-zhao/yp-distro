#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"
cd -- "${ROOT_DIR}"
ids=(gh-token gh-fine-grained aws-key private-key slack-token generic-sk)
patterns=(
    'ghp_[A-Za-z0-9]{36}'
    'github_pat_[A-Za-z0-9_]{22,}'
    'AKIA[0-9A-Z]{16}'
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'sk-[A-Za-z0-9]{32,}'
)
trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}
allowed=()
if [[ -f scripts/ci/secret-scan.allow ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "${line//[^|]/}" == '||' ]] || die "允许清单必须是 path | pattern-id | reason"
        IFS='|' read -r path id reason <<<"${line}"
        path="$(trim "${path}")"
        id="$(trim "${id}")"
        reason="$(trim "${reason}")"
        [[ -n "${path}" && -n "${reason}" && " ${ids[*]} " == *" ${id} "* && -n "${id}" ]] ||
            die "允许清单缺少有效路径、模式或理由"
        allowed+=("${path}|${id}")
    done <scripts/ci/secret-scan.allow
fi
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT
git ls-files -z >"${tmp}/files"
count=0
failed=0
while IFS= read -r -d '' file; do
    case "${file}" in .devhome/*) continue ;; esac
    [[ -f "${file}" ]] || die "跟踪文件不可读：${file}"
    # grep -I emits nothing for binary input; an empty text file still counts.
    rc=0
    grep -I -q '^' -- "${file}" || rc=$?
    ((rc <= 1)) || die "无法读取：${file}"
    if ((rc == 1)) && [[ -s "${file}" ]]; then continue; fi
    ((count += 1))
    for i in "${!ids[@]}"; do
        exempt=0
        for entry in "${allowed[@]}"; do
            if [[ "${entry}" == "${file}|${ids[i]}" ]]; then
                exempt=1
                break
            fi
        done
        ((exempt == 0)) || continue
        rc=0
        grep -I -nE -- "${patterns[i]}" "${file}" >"${tmp}/matches" || rc=$?
        ((rc <= 1)) || die "扫描失败：${file}"
        while IFS= read -r match; do
            printf '%s:%s: %s\n' "${file}" "${match%%:*}" "${ids[i]}"
            failed=1
        done <"${tmp}/matches"
    done
done <"${tmp}/files"
if ((failed)); then exit 1; fi
printf 'secret-scan: clean (%s files scanned)\n' "${count}"
