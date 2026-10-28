# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

ARG APT_MIRROR=cn.archive.ubuntu.com
ARG BUILD_UID=1000
ARG BUILD_GID=1000
ARG BUILD_USER=builder
ARG SHELLCHECK_VERSION=0.9.0
ARG SHFMT_VERSION=3.14.1
ARG BATS_VERSION=1.14.0
ARG GH_DL=https://github.com

ENV YOCTO_RELEASE=wrynose \
    YOCTO_SERIES=6.0 \
    UBUNTU_VERSION=24.04 \
    SDL_PKG=libsdl2-dev \
    EXTRA_PKGS="" \
    APT_MIRROR=${APT_MIRROR} \
    BUILD_UID=${BUILD_UID} \
    BUILD_GID=${BUILD_GID} \
    BUILD_USER=${BUILD_USER} \
    SHELLCHECK_VERSION=${SHELLCHECK_VERSION} \
    SHFMT_VERSION=${SHFMT_VERSION} \
    BATS_VERSION=${BATS_VERSION} \
    GH_DL=${GH_DL} \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="yocto-wrynose" \
      org.opencontainers.image.source="https://github.com/zeek-zhao/yocto" \
      org.opencontainers.image.description="Yocto 6.0 (wrynose) build image on Ubuntu 24.04" \
      org.opencontainers.image.licenses="MIT"

COPY docker/common/install-yocto-deps.sh /tmp/install-yocto-deps.sh
RUN bash /tmp/install-yocto-deps.sh && rm -f /tmp/install-yocto-deps.sh

USER ${BUILD_USER}
WORKDIR /work
CMD ["bash"]
