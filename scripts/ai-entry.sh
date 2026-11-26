#!/usr/bin/env bash
# AI 开发入口：打印必读清单、当前进度与下一步，或直接给出可粘贴提示词。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="$ROOT/docs/m0/plan.md"

if [ ! -f "$PLAN" ]; then
  echo "缺少阶段计划 docs/m0/plan.md，先补文档再开工。" >&2
  exit 1
fi

# 从进度表中取第一个非「完成」的 Step
next_row="$(awk -F'|' '
  /^\| S[0-9]+ \|/ {
    step=$2; name=$3; state=$4;
    gsub(/^ +| +$/,"",step); gsub(/^ +| +$/,"",name); gsub(/^ +| +$/,"",state);
    if (state != "完成") { printf "%s\t%s\t%s\n", step, name, state; exit }
  }' "$PLAN")"

if [ "${1:-}" = "--next" ]; then
  IFS=$'\t' read -r step name state <<<"$next_row"
  cat <<EOF
继续 M0：实现 Step ${step}（${name}），当前状态 ${state}。

先文档，后代码：
1) 按 docs/m0/templates/design.md 写 docs/m0/design/${step}-*.md：目的、失败模式、验收命令、回滚
2) 自评四问（覆盖需求 / 失败模式 / 验收可执行 / 回滚可行），写入 docs/m0/reviews/RV-*.md
3) 再实现代码；遇到任何非预期现象，先开 docs/m0/issues/ISS-*.md，再修
4) 提交带 Refs: 设计编号 与 Doc: 路径；一次一步，提交后停下等评审
5) 回报六件事：改动文件、执行命令、已验证、未验证及原因、新增记录编号、下一步建议

资源基线（AGENTS.md §2.1）：标准执行机 32 核 / 128 GiB；docker build/run 不得加 --cpus/--memory 等限制；
每次构建前记录 nproc、MemTotal、docker info NCPU/MemTotal、docker inspect 的 NanoCpus/Memory/CpuQuota；
Docker 无限制不等于 bitbake 用满，并发须按实际资源设置。低于基线用实际全量并标 RESOURCE_PARTIAL。

约束与禁区见 AGENTS.md 与 docs/ai/m0-prompt.md，不得越界。
EOF
  exit 0
fi

echo "== yp-distro M0 =="
echo "分支     : $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
echo "最新提交 : $(git -C "$ROOT" log -1 --pretty='%h %s' 2>/dev/null || echo unknown)"
echo
echo "必读顺序 : AGENTS.md → README.md → docs/ai/m0-prompt.md → docs/m0/plan.md → docs/m0/iso-mapping.md"
echo "资源基线 : 32 核 / 128 GiB；容器不加 --cpus/--memory；低于基线标 RESOURCE_PARTIAL（AGENTS §2.1）"
echo
echo "进度（来自 docs/m0/plan.md）:"
awk -F'|' '/^\| S[0-9]+ \|/ {gsub(/^ +| +$/,"",$2);gsub(/^ +| +$/,"",$3);gsub(/^ +| +$/,"",$4); printf "  %-4s %-32s %s\n", $2, $3, $4}' "$PLAN"
echo
if [ -n "${next_row:-}" ]; then
  IFS=$'\t' read -r step name state <<<"$next_row"
  echo "下一步   : ${step} ${name}（${state}）"
  echo "取提示词 : scripts/ai-entry.sh --next"
else
  echo "下一步   : 全部 Step 已完成，转入验收（YP-M0-REC-001）"
fi
echo
echo "记录要求 : 未验证的结论写 UNVERIFIED；问题先开 ISS 单再修；变更先开 CHG 单再动。"
