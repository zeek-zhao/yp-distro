#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"
cd -- "${ROOT_DIR}"
skip=""
while (($#)); do
    case "$1" in
        --skip)
            (($# >= 2)) || die "--skip 缺少参数"
            skip="$2"
            IFS=',' read -r -a skipped <<<"${skip}"
            for tool in "${skipped[@]}"; do
                [[ "${tool}" == hadolint || "${tool}" == actionlint ]] || die "不能跳过：${tool}"
            done
            shift 2
            ;;
        *) die "未知参数：$1" ;;
    esac
done
tools=(shellcheck shfmt hadolint actionlint)
for tool in "${tools[@]}"; do
    [[ ",${skip}," != *",${tool},"* ]] || continue
    command -v "${tool}" >/dev/null 2>&1 ||
        die "找不到 ${tool}，先跑 scripts/ci/install-tools.sh --prefix \$HOME/.local"
done
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT
git ls-files -z -- 'scripts/*.sh' 'project.sh' 'tests/bats/*.bash' >"${tmp}/files"
count=0
while IFS= read -r -d '' _file; do
    ((count += 1))
done <"${tmp}/files"
shopt -s nullglob
dockerfiles=(docker/*/Dockerfile)
workflows=(.github/workflows/*.yml)
counts=("${count} files" "${count} files" "${#dockerfiles[@]} files" "${#workflows[@]} workflows")
results=()
failed=0
for i in "${!tools[@]}"; do
    tool="${tools[i]}"
    log_info "=== ${tool} ==="
    if [[ ",${skip}," == *",${tool},"* ]]; then
        log_warn "显式跳过 ${tool}"
        results+=(SKIP)
        continue
    fi
    rc=0
    case "${tool}" in
        shellcheck) xargs -0 -r shellcheck -S warning -- <"${tmp}/files" >"${tmp}/${tool}" 2>&1 || rc=$? ;;
        shfmt) xargs -0 -r shfmt -d -i 4 -ci -- <"${tmp}/files" >"${tmp}/${tool}" 2>&1 || rc=$? ;;
        hadolint)
            ((${#dockerfiles[@]})) && hadolint "${dockerfiles[@]}" >"${tmp}/${tool}" 2>&1 || rc=1
            ;;
        actionlint)
            ((${#workflows[@]})) && actionlint "${workflows[@]}" >"${tmp}/${tool}" 2>&1 || rc=1
            ;;
    esac
    if ((rc)); then
        results+=(FAIL)
        failed=1
    else
        results+=(ok)
    fi
done
printf '=== lint summary ===\n'
for i in "${!tools[@]}"; do
    printf '%-11s %-4s (%s)\n' "${tools[i]}" "${results[i]}" "${counts[i]}"
    if [[ "${results[i]}" == FAIL ]]; then
        [[ ! -f "${tmp}/${tools[i]}" ]] || head -n 20 "${tmp}/${tools[i]}"
    fi
done
exit "${failed}"
