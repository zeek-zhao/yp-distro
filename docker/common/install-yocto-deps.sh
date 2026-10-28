#!/usr/bin/env bash
# The build flow uses kas' repos map and does not depend on Google's repo tool.
set -euo pipefail

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install-yocto-deps.sh [--help]

INSTALL_REPO=1 optionally installs Google's repo tool to /usr/local/bin/repo.
The Yocto build flow does not require repo; kas repos maps cover the required
multi-repository layouts.
EOF
}

if (($#)); then
    [[ $# -eq 1 && ("$1" == --help || "$1" == -h) ]] || die "Unknown option: $1"
    usage
    exit 0
fi

APT_MIRROR="${APT_MIRROR:-cn.archive.ubuntu.com}"
SDL_PKG="${SDL_PKG:?SDL_PKG is required}"
EXTRA_PKGS="${EXTRA_PKGS:-}"
UBUNTU_VERSION="${UBUNTU_VERSION:?UBUNTU_VERSION is required}"
BUILD_USER="${BUILD_USER:-builder}"
BUILD_UID="${BUILD_UID:-1000}"
BUILD_GID="${BUILD_GID:-1000}"
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-0.9.0}"
SHFMT_VERSION="${SHFMT_VERSION:-3.14.1}"
BATS_VERSION="${BATS_VERSION:-1.14.0}"
GH_DL="${GH_DL:-https://github.com}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

if [[ -f /etc/apt/sources.list ]]; then
    sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        -e "s|http://security.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        /etc/apt/sources.list
fi
if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
    sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        -e "s|http://security.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        /etc/apt/sources.list.d/ubuntu.sources
fi

base_packages=(
    gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat
    cpio curl python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping
    python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales
)
read -r -a extra_packages <<<"${EXTRA_PKGS}"
apt-get update
apt-get install -y --no-install-recommends \
    "${base_packages[@]}" "${SDL_PKG}" "${extra_packages[@]}"
apt-get clean
rm -rf /var/lib/apt/lists/*

pip_args=(install --no-cache-dir "kas==4.6")
if [[ "${UBUNTU_VERSION}" == "24.04" ]]; then
    pip_args+=(--break-system-packages)
fi
PIP_INDEX_URL="${PIP_INDEX_URL}" pip3 "${pip_args[@]}"
kas_version="$(kas --version)"
if ! grep -Eq '(^|[[:space:]])4\.6(\.[0-9]+)?([[:space:]]|$)' <<<"${kas_version}"; then
    die "Unexpected kas version '${kas_version}', expected 4.6.x"
fi

if [[ "${INSTALL_REPO:-0}" == "1" ]]; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
        -o /usr/local/bin/repo
    chmod 0755 /usr/local/bin/repo
fi

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

mkdir -p /work
if user_entry="$(getent passwd "${BUILD_USER}")"; then
    actual_uid="$(cut -d: -f3 <<<"${user_entry}")"
    [[ "${actual_uid}" == "${BUILD_UID}" ]] ||
        die "User ${BUILD_USER} has uid ${actual_uid}, expected ${BUILD_UID}"
    actual_gid="$(cut -d: -f4 <<<"${user_entry}")"
elif user_entry="$(getent passwd "${BUILD_UID}")"; then
    actual_user="${user_entry%%:*}"
    actual_gid="$(cut -d: -f4 <<<"${user_entry}")"
    if ! getent group "${actual_gid}" >/dev/null; then
        groupadd --gid "${actual_gid}" "${actual_user}"
    fi
    useradd --uid "${BUILD_UID}" --non-unique --gid "${actual_gid}" \
        --create-home --shell /bin/bash "${BUILD_USER}"
    # id -un resolves a shared UID to the first passwd entry, so drop the old
    # account to ensure the runtime name is BUILD_USER.
    userdel "${actual_user}"
else
    if ! getent group "${BUILD_GID}" >/dev/null; then
        groupadd --gid "${BUILD_GID}" "${BUILD_USER}"
    fi
    group_name="$(getent group "${BUILD_GID}" | cut -d: -f1)"
    useradd --uid "${BUILD_UID}" --gid "${group_name}" \
        --create-home --shell /bin/bash "${BUILD_USER}"
    actual_gid="${BUILD_GID}"
fi
chown "${BUILD_UID}:${actual_gid}" /work

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

wget -qO "${tmp_dir}/shellcheck.tar.xz" \
    "${GH_DL}/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
tar -xJf "${tmp_dir}/shellcheck.tar.xz" -C "${tmp_dir}"
install -m 0755 "${tmp_dir}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" \
    /usr/local/bin/shellcheck

wget -qO /usr/local/bin/shfmt \
    "${GH_DL}/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"
chmod 0755 /usr/local/bin/shfmt

wget -qO "${tmp_dir}/bats.tar.gz" \
    "${GH_DL}/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz"
mkdir "${tmp_dir}/bats"
tar -xzf "${tmp_dir}/bats.tar.gz" -C "${tmp_dir}/bats" --strip-components=1
"${tmp_dir}/bats/install.sh" /usr/local

printf '%s\n' \
    '=== image fingerprint ===' \
    "ubuntu=${UBUNTU_VERSION}" \
    "user=${BUILD_USER} uid=${BUILD_UID}" \
    "shellcheck=${SHELLCHECK_VERSION}" \
    "shfmt=${SHFMT_VERSION}" \
    "bats=${BATS_VERSION}" \
    "kas=${kas_version}" \
    "sdl=${SDL_PKG}" \
    "resolved_user=$(getent passwd "${BUILD_UID}" | cut -d: -f1)" \
    "resolved_gid=$(getent group "${actual_gid}" | cut -d: -f3)"
