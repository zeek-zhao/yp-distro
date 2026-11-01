#!/usr/bin/env python3
"""scripts/tokens-dashboard.py — 把 token 台账渲染成自包含 HTML 看板

用法：
  python3 scripts/tokens-dashboard.py [台账TSV] [输出HTML]

默认：logs/token-usage.tsv → docs/tokens.html

设计约束（都是踩过坑才写成这样）：
  - **零外部依赖**：不引 CDN、不引 JS 框架。构建机出网受限，离线双击也要能看。
  - 数据内嵌：台账整体塞进 <script type="application/json">，单文件可拷可发。
  - 双主题：用 prefers-color-scheme 跟随系统，浅底深字 / 深底浅字两套变量。
  - 口径不猜：in 已含 cacheWrite，total = in + out，与 copilot 自报一致；
    看板上把 cache 单独显示，但**不重复计入总量**。
"""

import json
import sys
import os
import datetime

COLS = ["ts", "task", "issue", "session_start", "model", "in", "out",
        "cache_r", "cache_w", "total", "credits", "premium", "dur_ms", "rc"]
INT_COLS = ("in", "out", "cache_r", "cache_w", "total", "premium", "dur_ms")


def load(ledger):
    rows = []
    if not os.path.exists(ledger):
        return rows
    with open(ledger, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            c = line.split("\t")
            if len(c) < len(COLS):
                continue
            r = dict(zip(COLS, c))
            for k in INT_COLS:
                try:
                    r[k] = int(r[k] or 0)
                except ValueError:
                    r[k] = 0
            try:
                r["credits"] = float(r["credits"] or 0)
            except ValueError:
                r["credits"] = 0.0
            r["ok"] = str(r["rc"]) in ("0", "None", "")
            rows.append(r)
    return rows


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
        "failed": sum(0 if r["ok"] else 1 for r in rs),
    }


HTML = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>WF3 Token 消耗看板</title>
<style>
  :root{
    --bg:#f6f7f9; --panel:#ffffff; --line:#e3e6eb; --fg:#1b1f24; --muted:#6b7280;
    --in:#4f8cff; --in-soft:#cfe0ff; --out:#8b5cf6; --out-soft:#e2d6ff;
    --ok:#16a34a; --bad:#dc2626; --accent:#0ea5e9;
  }
  @media (prefers-color-scheme: dark){
    :root{
      --bg:#0f1115; --panel:#171a21; --line:#262b35; --fg:#e6e8ec; --muted:#98a0ae;
      --in:#5b9bff; --in-soft:#23406b; --out:#a78bfa; --out-soft:#463173;
      --ok:#34d399; --bad:#f87171; --accent:#38bdf8;
    }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);
    font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans SC","Microsoft YaHei",sans-serif}
  .wrap{max-width:1180px;margin:0 auto;padding:28px 20px 64px}
  h1{font-size:20px;margin:0 0 4px;letter-spacing:.2px}
  .sub{color:var(--muted);font-size:12.5px;margin-bottom:22px}
  .sub code{background:var(--panel);border:1px solid var(--line);border-radius:4px;padding:1px 5px}
  .kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:22px}
  .kpi{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
  .kpi .k{color:var(--muted);font-size:12px;letter-spacing:.3px}
  .kpi .v{font-size:23px;font-weight:600;margin-top:5px;font-variant-numeric:tabular-nums}
  .kpi .n{color:var(--muted);font-size:11.5px;margin-top:3px}
  .panel{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin-bottom:18px}
  .bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:14px}
  .seg{display:inline-flex;background:var(--bg);border:1px solid var(--line);border-radius:8px;overflow:hidden}
  .seg button{background:none;border:0;color:var(--muted);padding:6px 13px;font-size:12.5px;cursor:pointer;font-family:inherit}
  .seg button.on{background:var(--accent);color:#fff}
  input[type=search]{background:var(--bg);border:1px solid var(--line);border-radius:8px;
    padding:6px 11px;color:var(--fg);font-size:12.5px;font-family:inherit;min-width:190px}
  .legend{display:flex;gap:16px;color:var(--muted);font-size:12px;margin-left:auto}
  .legend i{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:5px;vertical-align:middle}
  .rows{display:flex;flex-direction:column;gap:9px}
  .row{display:grid;grid-template-columns:210px 1fr 118px;gap:12px;align-items:center}
  .row .lb{font-size:12.5px;color:var(--fg);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .row .lb small{color:var(--muted)}
  .track{background:var(--bg);border-radius:5px;height:20px;display:flex;overflow:hidden;position:relative}
  .track .s{height:100%;transition:width .25s ease}
  .track .s.in{background:var(--in-soft)}
  .track .s.out{background:var(--out)}
  .row .num{text-align:right;font-size:12.5px;color:var(--muted);font-variant-numeric:tabular-nums}
  table{width:100%;border-collapse:collapse;font-size:12.5px}
  th,td{padding:7px 9px;text-align:left;border-bottom:1px solid var(--line);white-space:nowrap}
  th{color:var(--muted);font-weight:500;cursor:pointer;user-select:none;font-size:12px}
  th:hover{color:var(--fg)}
  th.num,td.num{text-align:right;font-variant-numeric:tabular-nums}
  tbody tr:hover{background:var(--bg)}
  .tag{display:inline-block;padding:0 6px;border-radius:4px;font-size:11px;line-height:18px}
  .tag.ok{background:rgba(22,163,74,.12);color:var(--ok)}
  .tag.bad{background:rgba(220,38,38,.12);color:var(--bad)}
  .empty{color:var(--muted);padding:26px 0;text-align:center}
  .note{color:var(--muted);font-size:12px;line-height:1.75}
  .note b{color:var(--fg);font-weight:600}
  @media (max-width:760px){
    .kpis{grid-template-columns:repeat(2,1fr)}
    .row{grid-template-columns:120px 1fr 84px}
  }
</style>
</head>
<body>
<div class="wrap">
  <h1>WF3 · AI Token 消耗看板</h1>
  <div class="sub" id="meta"></div>

  <div class="kpis" id="kpis"></div>

  <div class="panel">
    <div class="bar">
      <span class="seg" id="dim">
        <button data-dim="task" class="on">按任务</button>
        <button data-dim="issue">按 issue</button>
        <button data-dim="model">按模型</button>
      </span>
      <input type="search" id="q" placeholder="筛选任务 / issue / 模型…">
      <span class="legend">
        <span><i style="background:var(--in-soft)"></i>输入 token</span>
        <span><i style="background:var(--out)"></i>输出 token</span>
      </span>
    </div>
    <div class="rows" id="chart"></div>
  </div>

  <div class="panel">
    <div class="bar"><strong style="font-size:13px">明细</strong>
      <span class="legend" id="cnt"></span></div>
    <div style="overflow-x:auto">
      <table>
        <thead><tr>
          <th data-k="ts">时间</th>
          <th data-k="task">任务</th>
          <th data-k="issue">issue</th>
          <th data-k="model">模型</th>
          <th class="num" data-k="in">in</th>
          <th class="num" data-k="out">out</th>
          <th class="num" data-k="cache_w">cache 写</th>
          <th class="num" data-k="total">total</th>
          <th class="num" data-k="credits">credits</th>
          <th class="num" data-k="dur_ms">API 耗时</th>
          <th data-k="rc">结果</th>
        </tr></thead>
        <tbody id="tbody"></tbody>
      </table>
    </div>
  </div>

  <div class="panel note">
    <b>口径</b>（与 <code>scripts/wf3-tokens.sh</code> 一致，不另算一套）<br>
    · <b>in</b> = <code>modelMetrics.*.usage.inputTokens</code>，<b>已包含</b> cache 写入量；<b>total</b> = in + out，与 copilot 自报数字对得上<br>
    · <b>cache 写</b> 单列只为观察 prompt 复用情况，<b>不重复计入 total</b><br>
    · <b>credits</b> = <code>totalNanoAiu / 1e9</code>；<b>API 耗时</b> = <code>totalApiDurationMs</code>，不含排队与本地工具执行<br>
    · 台账按 <code>(task, sessionStartTime)</code> 幂等，同一会话重跑不会重复计数<br>
    · 本页由 <code>scripts/wf3-tokens.sh publish</code> 生成，数据源 <code>metrics/token-usage.tsv</code>
  </div>
</div>

<script type="application/json" id="data">__DATA__</script>
<script>
const D = JSON.parse(document.getElementById('data').textContent);
const fmt = n => n >= 1e6 ? (n/1e6).toFixed(2)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'k' : String(n);
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

document.getElementById('meta').innerHTML =
  '生成于 <code>' + esc(D.generated) + '</code> · 数据源 <code>' + esc(D.source) + '</code> · ' +
  D.rows.length + ' 条记录 / ' + Object.keys(D.by_task).length + ' 个任务';

const o = D.overall;
document.getElementById('kpis').innerHTML = [
  ['总 token', fmt(o.total), 'in ' + fmt(o.in) + ' + out ' + fmt(o.out)],
  ['AI credits', o.credits.toFixed(3), o.premium + ' premium requests'],
  ['任务数', Object.keys(D.by_task).length, o.runs + ' 次运行' + (o.failed ? ' · ' + o.failed + ' 次失败' : '')],
  ['平均每任务', Object.keys(D.by_task).length ? fmt(Math.round(o.total / Object.keys(D.by_task).length)) : '0', 'token / 任务'],
].map(([k,v,n]) => `<div class="kpi"><div class="k">${k}</div><div class="v">${v}</div><div class="n">${n}</div></div>`).join('');

let dim = 'task', sortKey = 'ts', sortAsc = false, query = '';

function groups(){
  const src = dim === 'task' ? D.by_task : dim === 'issue' ? D.by_issue : D.by_model;
  let arr = Object.entries(src).map(([k,v]) => ({k, ...v}));
  if (query) arr = arr.filter(g => g.k.toLowerCase().includes(query));
  return arr.sort((a,b) => b.total - a.total);
}

function drawChart(){
  const gs = groups();
  const el = document.getElementById('chart');
  if (!gs.length){ el.innerHTML = '<div class="empty">没有匹配的数据</div>'; return; }
  const max = Math.max(...gs.map(g => g.total)) || 1;
  el.innerHTML = gs.map(g => {
    const wi = g.in / max * 100, wo = g.out / max * 100;
    const label = dim === 'issue' ? '#' + g.k : g.k;
    return `<div class="row" title="${esc(g.k)}&#10;in ${g.in} / out ${g.out}&#10;credits ${g.credits}${g.failed ? '&#10;失败 ' + g.failed + ' 次' : ''}">
      <div class="lb">${esc(label)} <small>×${g.runs}</small></div>
      <div class="track">
        <div class="s in" style="width:${wi}%"></div>
        <div class="s out" style="width:${wo}%"></div>
      </div>
      <div class="num">${fmt(g.total)}<br><small>${g.credits.toFixed(3)} cr</small></div>
    </div>`;
  }).join('');
}

function drawTable(){
  let rs = D.rows.filter(r =>
    !query || r.task.toLowerCase().includes(query) || r.issue.includes(query) || r.model.toLowerCase().includes(query));
  rs = rs.slice().sort((a,b) => {
    let x = a[sortKey], y = b[sortKey];
    if (typeof x === 'number') return sortAsc ? x - y : y - x;
    return sortAsc ? String(x).localeCompare(y) : String(y).localeCompare(x);
  });
  document.getElementById('cnt').textContent = rs.length + ' / ' + D.rows.length + ' 条';
  const tb = document.getElementById('tbody');
  if (!rs.length){ tb.innerHTML = '<tr><td colspan="11" class="empty">没有匹配的记录</td></tr>'; return; }
  tb.innerHTML = rs.map(r => `<tr>
    <td>${esc(r.ts.replace('T',' ').slice(0,19))}</td>
    <td>${esc(r.task)}</td>
    <td>${esc(r.issue)}</td>
    <td>${esc(r.model)}</td>
    <td class="num">${r.in}</td>
    <td class="num">${r.out}</td>
    <td class="num">${r.cache_w}</td>
    <td class="num">${r.total}</td>
    <td class="num">${r.credits.toFixed(3)}</td>
    <td class="num">${(r.dur_ms/1000).toFixed(1)}s</td>
    <td><span class="tag ${r.ok?'ok':'bad'}">${r.ok?'ok':'rc='+esc(r.rc)}</span></td>
  </tr>`).join('');
}

document.getElementById('dim').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  [...e.currentTarget.children].forEach(x => x.classList.toggle('on', x === b));
  dim = b.dataset.dim; drawChart();
});
document.getElementById('q').addEventListener('input', e => {
  query = e.target.value.trim().toLowerCase(); drawChart(); drawTable();
});
document.querySelectorAll('th[data-k]').forEach(th => th.addEventListener('click', () => {
  const k = th.dataset.k;
  if (sortKey === k) sortAsc = !sortAsc; else { sortKey = k; sortAsc = false; }
  drawTable();
}));

drawChart(); drawTable();
</script>
</body>
</html>
"""


def main():
    ledger = sys.argv[1] if len(sys.argv) > 1 else "logs/token-usage.tsv"
    out = sys.argv[2] if len(sys.argv) > 2 else "docs/tokens.html"

    rows = load(ledger)
    payload = {
        "generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "source": ledger,
        "overall": agg(rows),
        "by_task": {k: agg([r for r in rows if r["task"] == k])
                    for k in sorted({r["task"] for r in rows})},
        "by_issue": {k: agg([r for r in rows if r["issue"] == k])
                     for k in sorted({r["issue"] for r in rows})},
        "by_model": {k: agg([r for r in rows if r["model"] == k])
                     for k in sorted({r["model"] for r in rows})},
        "rows": rows,
    }

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    html = HTML.replace("__DATA__", json.dumps(payload, ensure_ascii=False))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(html)

    print(f"[tokens] 看板已生成：{out}（{len(rows)} 条记录，{len(html)} 字节）")
    if not rows:
        print("[tokens] 注意：台账为空，看板只有空态")


if __name__ == "__main__":
    main()
