#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"

tools=(shellcheck shfmt bats hadolint actionlint)
versions=(0.9.0 3.14.1 1.14.0 2.15.1 1.7.7)
prefix="${HOME}/.local"
[[ ! -w /usr/local ]] || prefix=/usr/local
only=""
print_env=0
while (($#)); do
    case "$1" in
        --prefix | --only)
            (($# >= 2)) && [[ -n "$2" ]] || die "$1 缺少参数"
            if [[ "$1" == --prefix ]]; then prefix="$2"; else only="$2"; fi
            shift 2
            ;;
        --print-env)
            print_env=1
            shift
            ;;
        -h | --help)
            printf '%s\n' 'Usage: scripts/ci/install-tools.sh [--prefix DIR] [--only tool1,tool2] [--print-env]' \
                'Tools: shellcheck shfmt bats hadolint actionlint; GH_DL overrides https://github.com'
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
done
if ((print_env)); then
    env_prefix="${prefix//\\/\\\\}"
    env_prefix="${env_prefix//\"/\\\"}"
    env_prefix="${env_prefix//\$/\\\$}"
    env_prefix="${env_prefix//\`/\\\`}"
    printf 'export PATH="%s/bin:$PATH"\n' "${env_prefix}"
    exit 0
fi
[[ "$(uname -m)" == x86_64 ]] || die "仅支持 x86_64"
if [[ -n "${only}" ]]; then
    IFS=',' read -r -a selected <<<"${only}"
    for tool in "${selected[@]}"; do
        [[ " ${tools[*]} " == *" ${tool} "* && -n "${tool}" ]] || die "未知工具：${tool}"
    done
    [[ "${only}" != *, ]] || die "--only 不能包含空工具名"
fi
mkdir -p -- "${prefix}/bin" 2>/dev/null ||
    die "prefix 不可写：${prefix}（换个 --prefix 或加权限）"
[[ -w "${prefix}" && -w "${prefix}/bin" ]] ||
    die "prefix 不可写：${prefix}（换个 --prefix 或加权限）"
GH_DL="${GH_DL:-https://github.com}"
urls=(
    "/koalaman/shellcheck/releases/download/v${versions[0]}/shellcheck-v${versions[0]}.linux.x86_64.tar.xz"
    "/mvdan/sh/releases/download/v${versions[1]}/shfmt_v${versions[1]}_linux_amd64"
    "/bats-core/bats-core/archive/refs/tags/v${versions[2]}.tar.gz"
    "/hadolint/hadolint/releases/download/v${versions[3]}/hadolint-Linux-x86_64"
    "/rhysd/actionlint/releases/download/v${versions[4]}/actionlint_${versions[4]}_linux_amd64.tar.gz"
)
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT
for i in "${!tools[@]}"; do
    tool="${tools[i]}"
    version="${versions[i]}"
    [[ -z "${only}" || ",${only}," == *",${tool},"* ]] || continue
    installed="${prefix}/bin/${tool}"
    if [[ ! -x "${installed}" ]]; then
        installed="$(command -v "${tool}" || true)"
    fi
    current=""
    if [[ -n "${installed}" ]]; then
        if ! current="$("${installed}" --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"; then
            log_warn "无法探测 ${tool} 版本，将重新安装"
            current=""
        fi
    fi
    if [[ "${current}" == "${version}" ]]; then
        log_info "skip ${tool} ${version} (already)"
        continue
    fi
    log_info "install ${tool} ${version}"
    curl --fail --location --retry 3 --silent --show-error \
        "${GH_DL%/}${urls[i]}" -o "${tmp}/download"
    case "${tool}" in
        shellcheck)
            tar -xJf "${tmp}/download" -C "${tmp}"
            install -m 755 "${tmp}/shellcheck-v${version}/shellcheck" "${prefix}/bin/shellcheck"
            ;;
        bats)
            tar -xzf "${tmp}/download" -C "${tmp}"
            bash "${tmp}/bats-core-${version}/install.sh" "${prefix}"
            ;;
        actionlint)
            tar -xzf "${tmp}/download" -C "${tmp}" actionlint
            install -m 755 "${tmp}/actionlint" "${prefix}/bin/actionlint"
            ;;
        *) install -m 755 "${tmp}/download" "${prefix}/bin/${tool}" ;;
    esac
done
printf '=== toolchain ===\nprefix=%s\n' "${prefix}"
for i in "${!tools[@]}"; do
    printf '%s=%s\n' "${tools[i]}" "${versions[i]}"
done
