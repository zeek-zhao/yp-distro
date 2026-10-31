#!/usr/bin/env bash
# =============================================================================
# scripts/wf3-tokens.sh — WF3 的 AI token / AI credit 台账与报表
#
#   scripts/wf3-tokens.sh ingest <TASK-ID> [rc]
#       读 logs/usage-<TASK-ID>.json（copilot --usage-output-file 产出）
#       追加一行到 logs/token-usage.tsv。**幂等**：同一 sessionStartTime 不重复记。
#       wf3.sh 在任务退出后自动调用，一般不用手跑。
#
#   scripts/wf3-tokens.sh                      全量汇总 + 按任务 + 按模型 + 最近 10 次
#   scripts/wf3-tokens.sh --task 56-foo        只看某个任务
#   scripts/wf3-tokens.sh --issue 56           只看某个 issue（按任务 ID 的数字前缀归组）
#   scripts/wf3-tokens.sh --last 5             只看最近 N 次
#   scripts/wf3-tokens.sh --json               机器可读（给报告/看板用）
#
#   scripts/wf3-tokens.sh publish               把台账发布进版本库并重渲看板：
#                                                 logs/token-usage.tsv → metrics/token-usage.tsv
#                                                 docs/tokens.html（自包含，见 tokens-dashboard.py）
#       logs/ 在 .gitignore 里，台账要进仓库必须落到 metrics/。两处是**同一份内容**，
#       publish 每次整体覆盖（台账是追加型，覆盖即同步，不需要增量合并）。
#
# 台账字段（TSV，14 列）：
#   ts  task  issue  session_start  model  in  out  cache_r  cache_w  total  credits  premium  dur_ms  rc
#
# 口径说明（容易误解，写在这里）：
#   in      = modelMetrics.*.usage.inputTokens，**已包含** cacheWriteTokens
#   cache_w = 本次写入 prompt cache 的量（首次调用几乎等于整个 prompt）
#   cache_r = 命中缓存复用的量（后续轮次才会出现）
#   total   = in + out，与 copilot 自己报表的 token 数一致
#   credits = totalNanoAiu / 1e9（AI credits）
#   premium = totalPremiumRequestCost（premium requests）
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${WF3_TOKEN_LEDGER:-${ROOT_DIR}/logs/token-usage.tsv}"
USAGE_DIR="${ROOT_DIR}/logs"

usage() {
    sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ------------------------------------------------------------------ ingest --
do_ingest() {
    local id="${1:-}" rc="${2:-0}"
    [[ -n "${id}" ]] || { printf '[tokens] 用法：wf3-tokens.sh ingest <TASK-ID> [rc]\n' >&2; return 1; }
    local uf="${USAGE_DIR}/usage-${id}.json"
    if [[ ! -f "${uf}" ]]; then
        printf '[tokens] 没有 usage 文件：%s（任务可能没跑起来，或 copilot 版本不支持 --usage-output-file）\n' "${uf}" >&2
        return 0
    fi
    mkdir -p "$(dirname "${LEDGER}")"
    python3 - "${uf}" "${id}" "${LEDGER}" "${rc}" <<'PY'
import json, sys, os, datetime

uf, task, ledger, rc = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    d = json.load(open(uf, encoding="utf-8"))
except Exception as e:
    print(f"[tokens] usage JSON 解析失败：{e}", file=sys.stderr)
    sys.exit(0)

mm = d.get("modelMetrics") or {}
if mm:
    inp = sum(int((v.get("usage") or {}).get("inputTokens", 0) or 0) for v in mm.values())
    out = sum(int((v.get("usage") or {}).get("outputTokens", 0) or 0) for v in mm.values())
    cr  = sum(int((v.get("usage") or {}).get("cacheReadTokens", 0) or 0) for v in mm.values())
    cw  = sum(int((v.get("usage") or {}).get("cacheWriteTokens", 0) or 0) for v in mm.values())
    model = ",".join(mm.keys())
else:
    td = d.get("tokenDetails") or {}
    def n(k):
        return int((td.get(k) or {}).get("tokenCount", 0) or 0)
    inp, out, cr, cw = n("input"), n("output"), n("cache_read"), n("cache_write")
    model = d.get("currentModel") or "-"

total = inp + out
credits = round(int(d.get("totalNanoAiu", 0) or 0) / 1e9, 3)
premium = int(d.get("totalPremiumRequestCost", 0) or 0)
dur = int(d.get("totalApiDurationMs", 0) or 0)
sess = d.get("sessionStartTime") or "-"

# 任务 ID 的数字前缀 = issue 号；P0-01 这类无数字前缀记 -
num = ""
for ch in task:
    if ch.isdigit():
        num += ch
    else:
        break
issue = num or "-"

ts = datetime.datetime.now().astimezone().isoformat(timespec="seconds")

# 幂等：同一 (task, sessionStartTime) 只记一次
if os.path.exists(ledger):
    with open(ledger, encoding="utf-8") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) > 3 and cols[1] == task and cols[3] == sess:
                print(f"[tokens] 已记账，跳过（task={task} session={sess}）", file=sys.stderr)
                sys.exit(0)

row = [ts, task, issue, sess, model, inp, out, cr, cw, total, credits, premium, dur, rc]
with open(ledger, "a", encoding="utf-8") as f:
    f.write("\t".join(str(x) for x in row) + "\n")

print(f"[tokens] task={task} model={model} in={inp}(cache_w={cw}) out={out} "
      f"total={total} credits={credits} premium={premium} dur={dur}ms rc={rc}")
PY
}

# ------------------------------------------------------------------ report --
do_report() {
    local task="" issue="" last="" as_json=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task)  task="${2:-}"; shift 2 ;;
            --issue) issue="${2:-}"; shift 2 ;;
            --last)  last="${2:-10}"; shift 2 ;;
            --json)  as_json=1; shift ;;
            *) printf '[tokens] 未知参数：%s\n' "$1" >&2; exit 2 ;;
        esac
    done
    if [[ ! -f "${LEDGER}" ]]; then
        printf '[tokens] 还没有台账：%s（先跑一个 wf3 任务）\n' "${LEDGER}"
        return 0
    fi
    python3 - "${LEDGER}" "${task}" "${issue}" "${last}" "${as_json}" <<'PY'
import sys, json

ledger, f_task, f_issue, f_last, as_json = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
# 注意：从 shell 传进来的是字符串 "0"/"1"，"0" 在 Python 里是真值，
# 必须显式比较，否则无参数调用也会走 JSON 分支
as_json = (as_json == "1")
COLS = ["ts","task","issue","session_start","model","in","out","cache_r","cache_w",
        "total","credits","premium","dur_ms","rc"]

rows = []
with open(ledger, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        c = line.split("\t")
        if len(c) < len(COLS):
            continue
        r = dict(zip(COLS, c))
        for k in ("in","out","cache_r","cache_w","total","premium","dur_ms"):
            r[k] = int(r[k] or 0)
        try:
            r["credits"] = float(r["credits"] or 0)
        except ValueError:
            r["credits"] = 0.0
        rows.append(r)

if f_task:
    rows = [r for r in rows if r["task"] == f_task]
if f_issue:
    rows = [r for r in rows if r["issue"] == f_issue]
if f_last:
    rows = rows[-int(f_last):]

def agg(rs):
    return {
        "runs": len(rs),
        "in": sum(r["in"] for r in rs),
        "out": sum(r["out"] for r in rs),
        "cache_r": sum(r["cache_r"] for r in rs),
        "cache_w": sum(r["cache_w"] for r in rs),
        "total": sum(r["total"] for r in rs),
        "credits": round(sum(r["credits"] for r in rs), 3),
        "premium": sum(r["premium"] for r in rs),
        "dur_ms": sum(r["dur_ms"] for r in rs),
        "failed": sum(1 for r in rs if str(r["rc"]) not in ("0", "None")),
    }

if as_json:
    out = {
        "ledger": ledger,
        "overall": agg(rows),
        "by_task": {k: agg([r for r in rows if r["task"] == k])
                    for k in sorted({r["task"] for r in rows})},
        "by_issue": {k: agg([r for r in rows if r["issue"] == k])
                     for k in sorted({r["issue"] for r in rows})},
        "by_model": {k: agg([r for r in rows if r["model"] == k])
                     for k in sorted({r["model"] for r in rows})},
        "rows": rows,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0)

if not rows:
    print("[tokens] 没有匹配的记录")
    sys.exit(0)

def fmt(a):
    return (f"runs={a['runs']:<3} total={a['total']:<10} in={a['in']:<10} out={a['out']:<8} "
            f"cache_r={a['cache_r']:<9} cache_w={a['cache_w']:<9} "
            f"credits={a['credits']:<9} premium={a['premium']:<5} "
            f"api={a['dur_ms']/1000:.1f}s" + (f" failed={a['failed']}" if a['failed'] else ""))

print("== 汇总 ==")
print("  " + fmt(agg(rows)))

print("\n== 按任务 ==")
for k in sorted({r["task"] for r in rows}):
    print(f"  {k:<34} " + fmt(agg([r for r in rows if r["task"] == k])))

print("\n== 按 issue ==")
for k in sorted({r["issue"] for r in rows}):
    print(f"  #{k:<33} " + fmt(agg([r for r in rows if r["issue"] == k])))

print("\n== 按模型 ==")
for k in sorted({r["model"] for r in rows}):
    print(f"  {k:<34} " + fmt(agg([r for r in rows if r["model"] == k])))

print("\n== 明细（最多最近 15 次）==")
for r in rows[-15:]:
    print(f"  {r['ts'][:19]}  {r['task']:<28} {r['model']:<16} "
          f"in={r['in']:<8} out={r['out']:<6} total={r['total']:<8} "
          f"credits={r['credits']:<8} rc={r['rc']}")
PY
}

# ------------------------------------------------------------------ publish --
# 台账落 metrics/（进版本库），再重渲 docs/tokens.html。
# 台账是追加型，整体覆盖即同步；不删 metrics 里已有的行，只以 logs 为准。
do_publish() {
    local pub_dir="${ROOT_DIR}/metrics" pub="${ROOT_DIR}/metrics/token-usage.tsv"
    if [[ ! -f "${LEDGER}" ]]; then
        printf '[tokens] 还没有台账：%s（先跑一个 wf3 任务）\n' "${LEDGER}"
        return 0
    fi
    mkdir -p "${pub_dir}"
    cp "${LEDGER}" "${pub}"
    local n
    n=$(wc -l < "${pub}")
    printf '[tokens] 台账已发布：metrics/token-usage.tsv（%s 行）\n' "${n}"
    # 以 metrics/ 那份为输入，而不是 logs/：看板上写的数据源就是仓库里能找到的那份
    ( cd "${ROOT_DIR}" && python3 scripts/tokens-dashboard.py metrics/token-usage.tsv docs/tokens.html ) \
        || { printf '[tokens] 看板渲染失败\n' >&2; return 1; }
    printf '[tokens] 提示：把 metrics/ 与 docs/tokens.html 一起提交，仓库里就有进度可查\n'
}

# -------------------------------------------------------------------- main --
[[ $# -ge 1 ]] || { do_report; exit 0; }
case "$1" in
    ingest)  shift; do_ingest "$@" ;;
    publish) shift; do_publish "$@" ;;
    report|"") shift || true; do_report "$@" ;;
    -h|--help|help) usage 0 ;;
    --*)     do_report "$@" ;;
    *)       printf '[tokens] 未知子命令：%s\n' "$1" >&2; exit 2 ;;
esac
