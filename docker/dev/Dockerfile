# syntax=docker/dockerfile:1.7
###############################################################################
# yocto-dev — 工程开发与门禁容器
#
# 与「构建镜像」严格分工：
#   docker/<release>/      跑 bitbake，4 档 base（20.04 / 22.04 / 24.04 / 24.04）
#   docker/dev/（本文件）   跑 lint / BATS / review / 远程 AI CLI，统一 ubuntu 24.04
#
# dev 容器**不跑 bitbake**；需要 bitbake 时由 project.sh 调度构建镜像。
# 这样构建机不需要装 bats/shellcheck/shfmt/gh/node，全部隔离在容器内。
#
# 构建请走入口脚本（会按宿主 UID/GID 建用户，避免挂载产生 root 属主文件）：
#   scripts/dev.sh --build
###############################################################################
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── 工具版本（升级只改这里；全部可 --build-arg 覆盖）──────────────────────
ARG BATS_VERSION=1.14.0
ARG BATS_SUPPORT_VERSION=0.3.0
ARG BATS_ASSERT_VERSION=2.1.0
ARG SHFMT_VERSION=3.14.1
ARG HADOLINT_VERSION=2.15.1
ARG ACTIONLINT_VERSION=1.7.7
ARG GH_VERSION=2.103.3
ARG YQ_VERSION=4.54.1
ARG NODE_VERSION=22.23.4
ARG COPILOT_CLI_VERSION=1.0.105
ARG KAS_VERSION=4.6

# ── 用户映射（构建机上 jenkins uid/gid = 2000；构建时由 dev.sh 传入实际值）──
ARG DEV_UID=2000
ARG DEV_GID=2000
ARG DEV_USER=dev

# ── 软件源（全部可覆盖回官方，对应需求 §11 网络与源策略）──────────────────
ARG APT_MIRROR=archive.ubuntu.com
ARG PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple
ARG NPM_REGISTRY=https://registry.npmjs.org
ARG NODE_DIST=https://registry.npmmirror.com/-/binary/node
ARG GH_DL=https://github.com

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    TZ=Asia/Shanghai \
    DEBIAN_FRONTEND=noninteractive

###############################################################################
# 1. apt 基础层 + 系统工具链
###############################################################################
RUN sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        -e "s|http://security.ubuntu.com/ubuntu|http://${APT_MIRROR}/ubuntu|g" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git openssh-client gnupg \
        locales tzdata \
        jq unzip zip xz-utils tar file rsync less nano \
        vim tmux sudo bash-completion bc time \
        python3 python3-pip python3-venv \
    # chrpath / cpio / diffstat / gawk / zstd：poky 的 HOSTTOOLS 最小集。
    # 本镜像**不跑构建**，但远程 AI CLI（wf3 的 copilot 会话）需要 `bitbake -e`
    # 做只读解析验证；而 sanity 的 HOSTTOOLS 检查在解析末尾就执行，缺一个整条
    # 命令直接失败。不给这些工具，AI 只能盲改文件、无法自验 —— 实测代价是它会
    # 去研究 base.bbclass 试图用 hack 绕过检查，那比多装十几 MB 危险得多。
    # 各版列表不同：kirkstone/scarthgap 还要 lz4c（lz4 包），wrynose 不要。
        chrpath cpio diffstat gawk zstd lz4 \
        shellcheck \
        build-essential pkg-config \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# poky 还要求 pzstd / unzstd，Ubuntu 24.04 没有 pzstd 包。
# unzstd 是 zstd 按 argv[0] 判定的解压别名，软链即可；pzstd 用并行模式近似，
# 只为满足存在性检查 —— dev 容器不真构建，不会走到 pzstd 的真解压路径。
RUN ln -sf /usr/bin/zstd /usr/local/bin/unzstd \
    && printf '#!/bin/sh\nexec zstd -T0 "$@"\n' > /usr/local/bin/pzstd \
    && chmod +x /usr/local/bin/pzstd \
    && for t in chrpath cpio diffstat gawk zstd lz4c pzstd unzstd; do command -v "$t" >/dev/null || exit 1; done

RUN locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8

###############################################################################
# 2. BATS 核心 + 断言辅助库（报告机制的机器可读层依赖 ≥1.11 的 junit formatter）
###############################################################################
RUN curl -fsSL "${GH_DL}/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" \
        -o /tmp/bats.tar.gz \
    && mkdir -p /tmp/bats \
    && tar -xzf /tmp/bats.tar.gz -C /tmp/bats --strip-components=1 \
    && /tmp/bats/install.sh /usr/local \
    && rm -rf /tmp/bats /tmp/bats.tar.gz \
    && bats --version

RUN set -eux; \
    for pair in "support:${BATS_SUPPORT_VERSION}:bats-support" \
                "assert:${BATS_ASSERT_VERSION}:bats-assert"; do \
        name="${pair%%:*}"; rest="${pair#*:}"; ver="${rest%%:*}"; repo="${rest#*:}"; \
        curl -fsSL "${GH_DL}/bats-core/${repo}/archive/refs/tags/v${ver}.tar.gz" -o "/tmp/${name}.tar.gz"; \
        mkdir -p "/usr/local/lib/${repo}"; \
        tar -xzf "/tmp/${name}.tar.gz" -C "/usr/local/lib/${repo}" --strip-components=1; \
        rm -f "/tmp/${name}.tar.gz"; \
    done; \
    test -f /usr/local/lib/bats-support/load.bash \
    && test -f /usr/local/lib/bats-assert/load.bash

###############################################################################
# 3. 静态检查与 Git 工具（GitHub release 直连可用，实测 1.3s）
###############################################################################
RUN curl -fsSL "${GH_DL}/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64" \
        -o /usr/local/bin/shfmt \
    && chmod 0755 /usr/local/bin/shfmt \
    && shfmt --version

RUN curl -fsSL "${GH_DL}/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" \
        -o /usr/local/bin/hadolint \
    && chmod 0755 /usr/local/bin/hadolint \
    && hadolint --version

RUN curl -fsSL "${GH_DL}/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/actionlint.tar.gz \
    && mkdir -p /tmp/actionlint \
    && tar -xzf /tmp/actionlint.tar.gz -C /tmp/actionlint actionlint \
    && install -m 0755 /tmp/actionlint/actionlint /usr/local/bin/actionlint \
    && rm -rf /tmp/actionlint /tmp/actionlint.tar.gz \
    && actionlint --version

RUN curl -fsSL "${GH_DL}/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64" \
    && gh --version

RUN curl -fsSL "${GH_DL}/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /usr/local/bin/yq \
    && chmod 0755 /usr/local/bin/yq \
    && yq --version

###############################################################################
# 4. Python 质量工具（ubuntu 24.04 需 --break-system-packages）
###############################################################################
RUN python3 -m pip install --no-cache-dir --break-system-packages -i "${PIP_INDEX}" \
        pycodestyle \
        pytest \
        yamllint \
    && pycodestyle --version \
    && pytest --version \
    && yamllint --version

###############################################################################
# 4b. kas —— Yocto 配置层工具（仅用于 kas/*.yml 的静态解析校验，不跑 bitbake）
#     ubuntu 24.04 是 PEP668 受管环境；以 root 装到 /usr/local/bin
###############################################################################
RUN python3 -m pip install --no-cache-dir --break-system-packages -i "${PIP_INDEX}" \
        "kas==${KAS_VERSION}" \
    && kas --version

###############################################################################
# 5. Node + 远程 AI CLI（WF3 的编码端；构建机不装 node）
#    copilot 是 npm 包装器 + 平台专属二进制，optionalDependencies 在部分镜像上
#    不会自动解析，故显式安装平台包。
###############################################################################
RUN curl -fsSL "${NODE_DIST}/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
        -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
    && rm -f /tmp/node.tar.xz \
    && node --version \
    && npm --version

RUN npm config set registry "${NPM_REGISTRY}" --location=global \
    && npm install -g --no-audit --no-fund \
        "@github/copilot-linux-x64@${COPILOT_CLI_VERSION}" \
        "@github/copilot@${COPILOT_CLI_VERSION}" \
    && npm cache clean --force \
    && command -v copilot \
    && copilot --version

###############################################################################
# 6. Docker CLI —— 不在镜像内安装，由 scripts/dev.sh 运行时挂载宿主二进制
#
# 理由（实测）：
#   - 构建机 /usr/bin/docker 只依赖 libc + ld-linux（无 libdevmapper/libsystemd），
#     可直接挂进 ubuntu 24.04 容器运行；
#   - docker static 包（82MB）从 TUNA 只有 40KB/s、阿里云 637KB/s，每次重建都要等；
#   - 挂载宿主 CLI 能保证容器内 docker 版本与宿主/daemon 严格一致，
#     避免"CLI 28 配 daemon 27"这类隐性错配。
# 若换到没有宿主 docker 的机器，容器仍可用，只是没有 docker 能力。
###############################################################################

###############################################################################
# 7. 非 root 用户（UID/GID 与宿主对齐）
###############################################################################
RUN groupadd --gid "${DEV_GID}" "${DEV_USER}" \
    && useradd --uid "${DEV_UID}" --gid "${DEV_GID}" \
        --create-home --shell /bin/bash "${DEV_USER}" \
    && echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEV_USER}" \
    && chmod 0440 "/etc/sudoers.d/${DEV_USER}"

# 宿主 docker.sock 属组 gid=999：镜像内先加一次，运行时再用 --group-add 兜底
RUN groupadd --gid 999 docker 2>/dev/null || true; \
    usermod -aG docker "${DEV_USER}" 2>/dev/null || true; \
    id "${DEV_USER}"

###############################################################################
# 8. 版本指纹（供 01_docker_image.bats 断言，避免"装了但版本不对"静默通过）
###############################################################################
RUN { \
        printf 'image=yocto-dev\n'; \
        printf 'base=ubuntu:24.04\n'; \
        printf 'bats=%s\n'       "$(bats --version | awk '{print $2}')"; \
        printf 'shellcheck=%s\n' "$(shellcheck --version | awk '/^version:/{print $2}')"; \
        printf 'shfmt=%s\n'      "$(shfmt --version | tr -d 'v')"; \
        printf 'hadolint=%s\n'   "$(hadolint --version | awk '{print $4}')"; \
        printf 'actionlint=%s\n' "$(actionlint --version | head -1)"; \
        printf 'gh=%s\n'         "$(gh --version | head -1 | awk '{print $3}')"; \
        printf 'yq=%s\n'         "$(yq --version | awk '{print $4}')"; \
        printf 'node=%s\n'       "$(node --version | tr -d 'v')"; \
        printf 'copilot=%s\n'    "$(copilot --version 2>/dev/null | head -1)"; \
        printf 'kas=%s\n'        "$(kas --version | awk '{print $2}')"; \
        printf 'docker=host-mounted\n'; \
    } > /etc/yocto-dev-versions \
    && cat /etc/yocto-dev-versions

WORKDIR /work

USER ${DEV_USER}

CMD ["bash"]
