# yp-builder — Yocto wrynose 构建容器
# 基础镜像依据：Yocto 6.0 官方支持矩阵含 Ubuntu 24.04 (LTS)，与宿主一致（ADR-003）
# 主机依赖依据：Yocto 6.0 ref-manual 1.4.1 Ubuntu and Debian
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# 1) Yocto 官方主机依赖 + kas 安装前置（pipx / python3-websockets）
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential chrpath cpio debianutils diffstat file gawk gcc \
      git iputils-ping libacl1 libcrypt-dev locales \
      python3 python3-git python3-jinja2 python3-pexpect python3-pip \
      python3-subunit socat texinfo unzip wget xz-utils zstd \
      python3-websockets pipx ca-certificates \
    && sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen \
    && locale-gen \
    && pipx ensurepath \
    && rm -rf /var/lib/apt/lists/*

# 2) kas（官方推荐 pipx 安装，隔离依赖）；放入全局 PATH
# 锁定 5.5：依赖基线冻结，避免重建时版本漂移破坏两次 kas dump 一致性（CHG-001 / DES-002）
ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin
RUN pipx install kas==5.5

# 3) 固定非 root 构建用户，UID/GID 可配（约束 7 / B-04）
ARG JENKINS_UID=1000
ARG JENKINS_GID=1000
# ubuntu:24.04 预置 ubuntu 用户/组占用 UID/GID 1000；若与目标冲突先移除（ISS-003）。
# userdel 会连带删除同名主组，故 groupdel 需按「删完后是否仍占用」判断并容错。
RUN OLD_USER="$(getent passwd "${JENKINS_UID}" | cut -d: -f1)" \
    && OLD_GROUP="$(getent group "${JENKINS_GID}" | cut -d: -f1)" \
    && { [ -z "${OLD_USER}" ] || userdel "${OLD_USER}"; } \
    && { [ -z "${OLD_GROUP}" ] || { getent group "${JENKINS_GID}" >/dev/null && groupdel "${OLD_GROUP}"; } || true; } \
    && groupadd --gid "${JENKINS_GID}" jenkins \
    && useradd --uid "${JENKINS_UID}" --gid "${JENKINS_GID}" \
        --create-home --shell /bin/bash jenkins \
    && mkdir -p /work/downloads /work/sstate /work/build \
    && chown -R "${JENKINS_UID}:${JENKINS_GID}" /work

# 4) 入口校验脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER jenkins
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
