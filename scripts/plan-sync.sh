#!/usr/bin/env bash
# =============================================================================
# scripts/plan-sync.sh — 从 GitHub Issues 生成 docs/issues.md
#
# 问题清单的真源只有一个：GitHub Issues。手抄一份到仓库必然漂移，所以这里
# 按需生成，并由 CI 用 --check 校验仓库里的副本是否最新。
#
# 用法：
#   scripts/plan-sync.sh                     # 写入 docs/issues.md
#   scripts/plan-sync.sh --check             # 只校验，过期则退出码 1
#   scripts/plan-sync.sh --stdout            # 打印到标准输出
#
# 认证：GITHUB_TOKEN / GH_TOKEN，或退化为 `gh auth token`。只读公开仓库时
# 完全不需要令牌，但匿名调用有速率限制。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"

OUT="${ROOT_DIR}/docs/issues.md"
mode="write"

while (($#)); do
    case "$1" in
        --check) mode="check" ;;
        --stdout) mode="stdout" ;;
        -h | --help)
            sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
    shift
done

command -v python3 >/dev/null 2>&1 || die "找不到 python3"

token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "${token}" ]] && command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null || true)"
fi

repo="${GITHUB_REPOSITORY:-zeek-zhao/yp-distro}"

tmp="$(mktemp)"
# 清理失败不能污染退出码：Windows 上 mktemp 的路径与原生 rm 的路径语义不一致，
# 清理报错会让 --check 在「已判定一致」之后仍然退出 1。
trap 'rm -f -- "${tmp}" 2>/dev/null || true' EXIT

python3 - "${repo}" "${token}" >"${tmp}" <<'PY'
import hashlib
import json
import sys
import urllib.error
import urllib.request

repo, token = sys.argv[1], sys.argv[2]
base = f"https://api.github.com/repos/{repo}"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "yp-distro-plan-sync"}
if token:
    headers["Authorization"] = f"Bearer {token}"


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as f:
            return json.load(f)
    except urllib.error.HTTPError as exc:
        print(f"GitHub API 调用失败：{url} -> HTTP {exc.code}", file=sys.stderr)
        raise SystemExit(2)


def paged(path):
    items, page = [], 1
    while True:
        batch = get(f"{base}{path}{'&' if '?' in path else '?'}per_page=100&page={page}")
        if not batch:
            return items
        items += batch
        if len(batch) < 100:
            return items
        page += 1


milestones = get(f"{base}/milestones?state=open&per_page=100")
issues = [i for i in paged("/issues?state=open") if "pull_request" not in i]

by_milestone = {}
for issue in issues:
    ms = issue.get("milestone")
    key = (ms["number"] if ms else 0, ms["title"] if ms else "未归入里程碑")
    by_milestone.setdefault(key, []).append(issue)

open_ms = {m["number"]: m for m in milestones}

out = []
out.append("# 开放问题清单")
out.append("")
out.append("> 本文件由 `scripts/plan-sync.sh` 从 GitHub Issues 生成，**请勿手改**。")
out.append("> 想改内容就去改 issue；CI 会校验此文件是否与线上一致。")
out.append(">")
out.append(f"> 生成时共 {len(issues)} 个开放 issue、{len(milestones)} 个开放里程碑。")
out.append("")

for (num, title), items in sorted(by_milestone.items(), key=lambda kv: (kv[0][0] == 0, kv[0][0])):
    out.append(f"## {title}")
    out.append("")
    ms = open_ms.get(num)
    if ms and ms.get("due_on"):
        out.append(f"到期：{ms['due_on'][:10]}")
        out.append("")
    out.append("| Issue | 标题 | 标签 |")
    out.append("|---|---|---|")
    for issue in sorted(items, key=lambda i: i["number"]):
        labels = ", ".join(f"`{l['name']}`" for l in issue.get("labels", [])) or "—"
        title_text = issue["title"].replace("|", "\\|")
        out.append(f"| [#{issue['number']}]({issue['html_url']}) | {title_text} | {labels} |")
    out.append("")

out.append("")
out.append("---")
out.append("")
# 指纹只覆盖「有哪些问题、各自属于哪个里程碑」。标签、正文、评论的改动不参与，
# 否则每改一次 issue 都会让 CI 变红，直到有人重新生成并提交——那会把清单同步
# 变成「任何 issue 编辑都要跟一次提交」，没人受得了。
fp_src = "\n".join(
    sorted(f"{i['number']}|{i['title']}|{(i.get('milestone') or {}).get('number', 0)}" for i in issues)
)
fingerprint = hashlib.sha256(fp_src.encode()).hexdigest()[:16]
out.append(f"<!-- plan-sync fingerprint: {fingerprint} -->")

print("\n".join(out).rstrip() + "\n", end="")
PY

case "${mode}" in
    stdout) cat "${tmp}" ;;
    write)
        cp -- "${tmp}" "${OUT}"
        log_info "已写入 ${OUT#"${ROOT_DIR}/"}"
        ;;
    check)
        if [[ ! -f "${OUT}" ]]; then
            log_error "缺少 ${OUT#"${ROOT_DIR}/"}，先跑 scripts/plan-sync.sh"
            exit 1
        fi
        fp_new="$(grep -o 'plan-sync fingerprint: [0-9a-f]*' "${tmp}" | head -n 1)"
        fp_old="$(grep -o 'plan-sync fingerprint: [0-9a-f]*' "${OUT}" | head -n 1)"
        if [[ -z "${fp_old}" ]]; then
            log_error "docs/issues.md 缺少指纹行，跑 scripts/plan-sync.sh 重新生成"
            exit 1
        fi
        if [[ "${fp_new}" != "${fp_old}" ]]; then
            log_error "开放 issue 集合已变化（新增/关闭/换里程碑），跑 scripts/plan-sync.sh 重新生成"
            log_error "  线上 ${fp_new:-<空>} vs 仓库 ${fp_old}"
            diff -u -- "${OUT}" "${tmp}" | head -n 40 >&2 || true
            exit 1
        fi
        log_info "docs/issues.md 与线上一致（${fp_old}）"
        ;;
esac
