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
# GitHub 的 noreply 合成身份放行：那是平台在网页合并时生成的，不含真实
# 个人信息；如果也拦，每次网页合并都要 force push 重写，PR 与提交的关联
# 反而会断。
#
# 外部贡献者的非 zeek 身份是合法的，不拦。
# =============================================================================
set -euo pipefail

readonly WANT_MAIL="zeek.zhao@foxmail.com"
# 2026-11-12 起本地新提交统一用 zeek-zhao <GitHub noreply 邮箱>：该邮箱
# 命中上面的 noreply 放行分支；本地钩子的等价校验见 .githooks/commit-msg。
# WANT_MAIL 保持历史口径——改它会让全历史检查变红（残留盘点见 #107）。
# 内部域名与内网网段。本脚本自身也在工作树里，靠下面的 :(exclude) 排除，
# 所以这里可以直接写完整字面量。
readonly SENSITIVE_RE='rollingwireless\.[a-z]+|@devops\.com|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
readonly SELF="scripts/ci/identity-guard.sh"

rc=0

# ------------------------------------------------------------ 1. 提交身份 --
while IFS='|' read -r name mail; do
    [[ -n "${mail}" ]] || continue
    # GitHub 侧的合成身份（网页合并 merge commit / Web 编辑产物）不含真实
    # 个人信息，也不代表维护者选错了身份，放行——否则每次通过网页合并 PR
    # 都会让门禁变红，只能靠 force push 重写，反而破坏 PR 与提交的关联。
    case "${mail}" in
        *@users.noreply.github.com | noreply@github.com) continue ;;
    esac
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

# ------------------------------------------------------ 3. AI 署名残留 --
# 2026-11-01 第二次历史重写删掉了全部 16 条 co-author trailer。这里保证它
# 不再回来。
#
# 只匹配**署名句式**，不做裸关键词匹配：仓库里 scripts/copilot-wrap.sh、
# .github/copilot-instructions.md 等实体仍在正常工作，提交消息里提到它们是
# 正常工程记录。若按裸关键词扫，门禁会把自己的工具链判成违规。
readonly AI_TOOL_RE='copilot|claude|anthropic|openai|chatgpt|gemini|cursor|codeium|tabnine|devin|aider|codex'
readonly AI_TRAILER_RE="^[[:space:]]*co-authored-by:.*(${AI_TOOL_RE})"
readonly AI_DECL_RE="(generated|written)[[:space:]]+(with|by)[[:space:]]+(${AI_TOOL_RE})|assisted[-[:space:]]by[[:space:]]*(${AI_TOOL_RE})|🤖"

if hits="$(git log --all --format='%H %s%n%b' | grep -inE "${AI_TRAILER_RE}|${AI_DECL_RE}" 2>/dev/null)" &&
    [[ -n "${hits}" ]]; then
    printf '[identity] 提交消息含 AI 署名或生成声明：\n%s\n' "${hits}" >&2
    rc=1
fi

if [[ "${rc}" -eq 0 ]]; then
    printf '[identity] 通过：身份统一、无内部信息残留、无 AI 署名\n'
fi
exit "${rc}"
