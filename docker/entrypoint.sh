#!/usr/bin/env bash
# 容器入口：构建前校验身份与挂载点属主（DES-003 / B-04 / 约束 7）
# 校验失败直接退出并给出修复命令，不带错属主继续。
set -euo pipefail

JENKINS_UID="$(id -u jenkins)"

# 1) 必须是非 root 的 jenkins 身份
if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: 容器禁止以 root 运行；请以 jenkins 用户启动（USER jenkins）。" >&2
  exit 1
fi
if [ "$(id -u)" != "${JENKINS_UID}" ]; then
  echo "ERROR: 当前 UID $(id -u) 与 jenkins UID ${JENKINS_UID} 不一致。" >&2
  exit 1
fi

# 2) 挂载点属主校验（S4 会真正挂载；本步目录不存在则跳过）
check_mount() {
  local dir="$1"
  [ -d "${dir}" ] || return 0
  local owner
  owner="$(stat -c %u "${dir}")"
  if [ "${owner}" != "${JENKINS_UID}" ]; then
    echo "ERROR: ${dir} 属主 UID=${owner}，与 jenkins UID=${JENKINS_UID} 不一致。" >&2
    echo "FIX:   host$ chown -R ${JENKINS_UID}:${JENKINS_UID} <挂载源目录>" >&2
    echo "       或用 --build-arg JENKINS_UID=${owner} 重建镜像。" >&2
    exit 1
  fi
}

check_mount /work/downloads
check_mount /work/sstate

# 3) 通过校验后执行传入命令
exec "$@"
