#!/usr/bin/env bash
# =============================================================================
# scripts/ci/identity-guard.sh — 发布历史里的身份与内部信息门禁
#
# 2026-11-01 做过一次历史重写：4 种提交身份统一为 zeek.zhao <zeek.zhao@foxmail.com>，
# 内网地址替换为 127.0.0.1，reference/ 目录整体移除。这个脚本保证它们不回来。
#
# 检查两件事（都覆盖**全部历史**，不只看最新提交）：
#   1. 任何提交的 author/committer 邮箱里带 zeek 时，必须正好是标准邮箱
#   2. 工作树与提交消息里不得出现内部域名、内网网段
#
# 外部贡献者的非 zeek 身份是合法的，不拦。
# =============================================================================
set -euo pipefail

readonly WANT_MAIL="zeek.zhao@foxmail.com"
# 内部域名与内网网段。本脚本自身也在工作树里，靠下面的 :(exclude) 排除，
# 所以这里可以直接写完整字面量。
readonly SENSITIVE_RE='rollingwireless\.[a-z]+|@devops\.com|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
readonly SELF="scripts/ci/identity-guard.sh"

rc=0

# ------------------------------------------------------------ 1. 提交身份 --
while IFS='|' read -r name mail; do
    [[ -n "${mail}" ]] || continue
    [[ "${mail}" == *zeek* ]] || continue
    if [[ "${mail}" != "${WANT_MAIL}" ]]; then
        printf '[identity] %s <%s> 使用了非标准维护者邮箱（应为 %s）\n' \
            "${name}" "${mail}" "${WANT_MAIL}" >&2
        rc=1
    fi
done < <(git log --all --format='%an|%ae%n%cn|%ce' | sort -u)

# -------------------------------------------------------- 2. 内部信息残留 --
if hits="$(git grep -I -nE "${SENSITIVE_RE}" -- . ":(exclude)${SELF}" 2>/dev/null)" && [[ -n "${hits}" ]]; then
    printf '[identity] 工作树含内部域名或内网地址：\n%s\n' "${hits}" >&2
    rc=1
fi

if hits="$(git log --all --format='%H %s%n%b' | grep -nE "${SENSITIVE_RE}" 2>/dev/null)" && [[ -n "${hits}" ]]; then
    printf '[identity] 提交消息含内部域名或内网地址：\n%s\n' "${hits}" >&2
    rc=1
fi

if [[ "${rc}" -eq 0 ]]; then
    printf '[identity] 通过：身份统一、无内部信息残留\n'
fi
exit "${rc}"
