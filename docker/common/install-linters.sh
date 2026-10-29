#!/usr/bin/env bash
# hadolint + actionlint
#
# release 镜像要跑 scripts/report.sh，里面有两例分别调 hadolint 与 actionlint。
# 镜像缺这两个工具时，归档只能先临时装一遍，报告里的数字就依赖那次临时安装，
# "镜像本身可复现"也就没了（#46）。
#
# 刻意做成独立一层：塞进 install-yocto-deps.sh 会让那个 RUN 的缓存失效，
# 四个 release 镜像都要重跑一遍 apt 依赖（每个约 8 分钟）。
set -euo pipefail

: "${HADOLINT_VERSION:?}" "${ACTIONLINT_VERSION:?}" "${GH_DL:?}"

wget -qO /usr/local/bin/hadolint \
    "${GH_DL}/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64"
chmod 0755 /usr/local/bin/hadolint

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
wget -qO "${tmp_dir}/actionlint.tar.gz" \
    "${GH_DL}/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
tar -xzf "${tmp_dir}/actionlint.tar.gz" -C "${tmp_dir}" actionlint
install -m 0755 "${tmp_dir}/actionlint" /usr/local/bin/actionlint

# 指纹进构建日志：装了但版本不对要能看出来
printf '%s\n' \
    '=== linter fingerprint ===' \
    "hadolint=${HADOLINT_VERSION} reported=$(hadolint --version | awk '{print $4}')" \
    "actionlint=${ACTIONLINT_VERSION} reported=$(actionlint --version | head -1)"
