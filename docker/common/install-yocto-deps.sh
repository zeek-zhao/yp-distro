#!/usr/bin/env bash
set -euo pipefail

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

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

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
    cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping
    python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales
)
read -r -a extra_packages <<<"${EXTRA_PKGS}"
apt-get update
apt-get install -y --no-install-recommends \
    "${base_packages[@]}" "${SDL_PKG}" "${extra_packages[@]}"
apt-get clean
rm -rf /var/lib/apt/lists/*

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
    "sdl=${SDL_PKG}" \
    "resolved_user=$(getent passwd "${BUILD_UID}" | cut -d: -f1)" \
    "resolved_gid=$(getent group "${actual_gid}" | cut -d: -f3)"
