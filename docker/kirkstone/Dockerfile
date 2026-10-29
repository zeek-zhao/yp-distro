# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04

ARG APT_MIRROR=cn.archive.ubuntu.com
ARG BUILD_UID=1000
ARG BUILD_GID=1000
ARG BUILD_USER=builder
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG SHELLCHECK_VERSION=0.9.0
ARG SHFMT_VERSION=3.14.1
ARG BATS_VERSION=1.14.0
ARG HADOLINT_VERSION=2.15.1
ARG ACTIONLINT_VERSION=1.7.7
ARG GH_DL=https://github.com

ENV YOCTO_RELEASE=kirkstone \
    YOCTO_SERIES=4.0 \
    UBUNTU_VERSION=22.04 \
    SDL_PKG=libsdl1.2-dev \
    EXTRA_PKGS="" \
    APT_MIRROR=${APT_MIRROR} \
    BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=${BUILD_USER} \
    SHELLCHECK_VERSION=${SHELLCHECK_VERSION} \
    SHFMT_VERSION=${SHFMT_VERSION} \
    BATS_VERSION=${BATS_VERSION} \
    HADOLINT_VERSION=${HADOLINT_VERSION} \
    ACTIONLINT_VERSION=${ACTIONLINT_VERSION} \
    GH_DL=${GH_DL} \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="yocto-kirkstone" \
      org.opencontainers.image.source="https://github.com/zeek-zhao/yocto" \
      org.opencontainers.image.description="Yocto 4.0 (kirkstone) build image on Ubuntu 22.04" \
      org.opencontainers.image.licenses="MIT"

COPY docker/common/install-yocto-deps.sh /tmp/install-yocto-deps.sh
RUN bash /tmp/install-yocto-deps.sh && rm -f /tmp/install-yocto-deps.sh
COPY docker/common/install-linters.sh /tmp/install-linters.sh
RUN bash /tmp/install-linters.sh && rm -f /tmp/install-linters.sh

USER builder
WORKDIR /work
CMD ["bash"]
