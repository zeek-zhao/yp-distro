#!/usr/bin/env bash
# =============================================================================
# scripts/ci/skip-gate.sh — 把「悄悄跳过」变成「显式偿还」
#
# BATS 的 skip 在 CI 上是隐形的：用例显示 ok，实际什么都没验。仓库转公开后
# runner 资源不再是约束，唯一还成立的跳过理由是宿主物理限制（无 /dev/kvm）。
# 这个门禁给 skip 设上限，超了就让 job 红——逼着要么补环境，要么把理由写进
# config/degraded.txt。
#
# 用法：scripts/ci/skip-gate.sh <junit.xml> [最大允许跳过数]
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"

xml="${1:-}"
max="${2:-${MAX_SKIPS:-4}}"

[[ -n "${xml}" ]] || {
    log_error "用法：scripts/ci/skip-gate.sh <junit.xml> [最大允许跳过数]"
    exit 2
}
[[ -f "${xml}" ]] || {
    log_error "找不到 JUnit 报告：${xml}"
    exit 2
}

# JUnit 里 skip 的两种写法：<skipped/> 与 <skipped message="..."/>。
#
# 注意 grep 的退出码：没有匹配时 grep 返回 1，在 `set -o pipefail` 下会让整条
# 管道失败、脚本静默退出——「跳过了 0 个」这个最理想的情况反而把门禁自己打死。
# 所有计数都必须显式吞掉 grep 的退出码。
count_matches() {
    { grep -o "$1" "$2" || true; } | wc -l | tr -d ' '
}

skipped="$(count_matches '<skipped' "${xml}")"
total="$(count_matches '<testcase' "${xml}")"

log_info "BATS 用例总数 ${total}，跳过 ${skipped}，上限 ${max}"

if ((skipped > max)); then
    log_error "跳过用例数超限（${skipped} > ${max}）。"
    log_error "要么补齐环境让用例真跑，要么在 config/degraded.txt 登记理由并调高上限。"
    # 把跳过的用例名列出来，方便定位
    grep -o '<testcase name="[^"]*"[^>]*>[[:space:]]*<skipped' "${xml}" 2>/dev/null |
        sed -E 's/^<testcase name="([^"]*)".*/  skip: \1/' >&2 || true
    exit 1
fi

log_info "skip 门禁通过"
