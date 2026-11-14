#!/usr/bin/env python3
# 生成 docs/01-requirements/scenarios/*.feature 与 traceability.md
# 数据源: config/features.txt（唯一事实源） + tests/bats/*.bats（test_tags + @test）
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))  # scripts/ci -> repo root
REQ = os.path.join(ROOT, "docs", "01-requirements")
SCN = os.path.join(REQ, "scenarios")

# ---------- 解析 features.txt ----------
feats = []  # dict: id, rel, bats, tag, status, ev
with open(os.path.join(ROOT, "config", "features.txt"), encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) == 6:
            fid, rel, bats, tag, status, ev = parts
            feats.append(dict(id=fid, rel=rel, bats=bats, tag=tag, status=status, ev=ev))
assert len(feats) == 26, f"features 行数 {len(feats)} != 26"
FR = {f["id"]: f"FR-{i+1:03d}" for i, f in enumerate(feats)}
BYID = {f["id"]: f for f in feats}

# ---------- 解析 bats 用例（name + test_tags） ----------
tests = []  # (file, name, tags)
for fn in sorted(os.listdir(os.path.join(ROOT, "tests", "bats"))):
    if not fn.endswith(".bats") or fn == "99_coverage.bats":
        continue
    cur_tags = None
    for line in open(os.path.join(ROOT, "tests", "bats", fn), encoding="utf-8"):
        m = re.match(r"\s*#\s*bats test_tags=(\S+)", line)
        if m:
            cur_tags = m.group(1)
            continue
        m = re.match(r'\s*@test\s+"([^"]+)"', line)
        if m:
            tests.append((fn, m.group(1), cur_tags or ""))
print(f"解析到 {len(tests)} 个非 meta 用例")
assert len(tests) == 205, f"用例数 {len(tests)} != 205"

# ---------- 共享文件的 FR 精细分派 ----------
# (bats文件, 用例名) -> feature_id；未列出的按 (file,tag) 唯一 feature 归属
OVERRIDES = {
    "03_container.bats": {
        "preflight reports kvm acceleration capability without failing": "kvm-accel",
        "kvm device is forwarded when the host exposes it": "kvm-accel",
        "missing kvm degrades to tcg without blocking preflight": "kvm-accel",
    },
    "11_compliance.bats": {
        "compliance.sh 校验必填参数与 --only 取值": "cve-tool",
        "compliance.sh status 在未采集时报缺失而不是失败": "cve-tool",
        "report.sh --compliance 缺 compliance.json 时给出可执行的下一步": "cve-tool",
        "report.sh --compliance 出五节归档并判 PASS": "cve-tool",
        "report.sh --compliance 对 6.0 写 sbom-cve-check 而不是“不适用”": "cve-tool",
        "report.sh --compliance 有节缺失时判 FAIL 并返回非零": "cve-tool",
        "report.sh --compliance 拒绝 all": "cve-tool",
        "compliance.sh --print-sbom 缺产物时指向 --spdx 构建": "spdx-format",
        "report.sh --compliance 索引型 SBOM 用聚合口径而不是「1 包」": "spdx-format",
        "report.sh --compliance 索引型对位不全时判 FAIL": "spdx-format",
        "sbom-stats.py 同时认 SPDX 2.2 与 3.0.1": "spdx-format",
        "sbom-stats.py 对无法识别的文档返回非零": "spdx-format",
        "sbom-stats.py 认索引型文档并按 documentNamespace 对位聚合": "spdx-format",
        "sbom-stats.py 不传 --spdx-dir 时索引型只报形态不聚合": "spdx-format",
        "foss-summary.py 按实际产出的 json 记账，失败包不进成功率": "foss-scan",
    },
}
# (file, tag) -> feature 列表（features.txt 允许多 feature 共享 (file,tag)）
FILETAG = {}
for f in feats:
    if f["bats"] == "-":
        continue
    key = (os.path.basename(f["bats"]), f["tag"])
    FILETAG.setdefault(key, [])
    if f["id"] not in FILETAG[key]:
        FILETAG[key].append(f["id"])
# 歧义时的文件级默认归属（主 FR）
FILE_DEFAULT = {"11_compliance.bats": "cve-tool", "03_container.bats": "container-runtime"}

assign = {}  # (file,name) -> feature_id
for fn, name, tags in tests:
    if name in OVERRIDES.get(fn, {}):
        oid = OVERRIDES[fn][name]
        if oid not in FR:
            raise SystemExit(f"override 指向未知 feature: {oid}")
        assign[(fn, name)] = oid
        continue
    cands = FILETAG.get((fn, tags), [])
    if len(cands) == 1:
        assign[(fn, name)] = cands[0]
    elif (fn, tags) in FILETAG and fn in FILE_DEFAULT:
        assign[(fn, name)] = FILE_DEFAULT[fn]
    else:
        raise SystemExit(f"用例归属歧义且无默认: {fn} / '{name}' / tags={tags} / 候选={cands}")

covered = len(assign)
assert covered == 205, f"分派数 {covered} != 205"

# ---------- 模块划分 ----------
MODULES = [
    ("m1-entry",      "工程入口与命令行", ["entry-unified"]),
    ("m2-images",     "容器与镜像",       ["docker-images", "container-runtime", "kvm-accel"]),
    ("m3-ci",         "CI 流水线治理",     ["ci-workflows", "supported-releases"]),
    ("m4-distro",     "层与发行版配置",    ["layer-structure", "kas-layer", "distro-features"]),
    ("m5-compliance", "合规与供应链",      ["spdx-format", "cve-tool", "cve-db", "foss-scan", "do-scancode"]),
    ("m6-report",     "报告与验证取证",    ["report-archive", "cross-version-diff", "syntax-matrix"]),
    ("m7-release",    "发布与部署工程",    ["deploy-guard", "release-check"]),
    ("m8-build",      "SDK 与共享缓存",    ["sdk", "shared-cache"]),
    ("m9-runtime",    "运行时与服务演示",  ["yp-service", "boot-time", "demo-statusd", "demo-collectd", "distro-backfill"]),
]

os.makedirs(SCN, exist_ok=True)
GHERKIN_HEADER = """# 本文件由 scripts/ci/gen_requirements.py 生成——请勿手改用例名。
# 数据源: config/features.txt + tests/bats/*.bats（BDD 场景层映射，bats 本体为唯一可执行事实）
# language: zh-CN
"""

lines_by_module = {m[0]: [] for m in MODULES}
for fid, frid in FR.items():
    f = BYID[fid]
    mod = next(m for m in MODULES if fid in m[2])
    L = lines_by_module[mod[0]]
    L.append(f"@{frid} @feature:{fid} @evidence:{f['ev']}")
    L.append(f"Feature: [{fid}] {fid}（证据级别 {f['ev']}，适用 release: {f['rel']}）")
    if f["bats"] == "-":
        L.append("  本特性无自动化 bats 用例（degraded/static），以文档证据归档为准。")
        L.append("")
        L.append("  Scenario: 文档证据——无自动化用例，按 degraded 登记口径归档")
        L.append("    Given features.txt 将该特性标记为 degraded 且无 bats 映射")
        L.append("    When 审阅 docs/01-requirements/features.md 与 docs/qa/ 对应 degraded 登记")
        L.append("    Then 证据级别为 static 且 degraded.txt 有对应登记原因")
    else:
        base = os.path.basename(f["bats"])
        tlist = [(fn, name) for (fn, name) in assign if assign[(fn, name)] == fid and fn == base]
        extra = [(fn, name) for (fn, name) in assign if assign[(fn, name)] == fid and fn != base]
        L.append(f"  BATS 源: {f['bats']}（tag {f['tag']}）")
        L.append("")
        for fn, name in tlist + extra:
            L.append(f"  Scenario: {name}")
            L.append(f"    Given features.txt 将 {fid} 注册为 {f['ev']} 级证据（适用 release: {f['rel']}）")
            L.append(f"    When 运行 tests/bats/{fn} 的用例 \"{name}\"")
            L.append("    Then 用例通过，证据按 report.sh 归档至 docs/qa/<release>/")
        assert tlist or extra, f"{fid} 无用例"

for mid, mname, ids in MODULES:
    p = os.path.join(SCN, f"{mid}.feature")
    with open(p, "w", encoding="utf-8") as f:
        f.write(GHERKIN_HEADER)
        f.write(f"# 模块: {mname}\n\n")
        f.write("\n".join(lines_by_module[mid]) + "\n")

# ---------- traceability.md ----------
T = ["# 需求追溯矩阵（traceability）", "",
     "> 生成物：scripts/ci/gen_requirements.py 从 config/features.txt（唯一事实源）与 tests/bats/*.bats 自动生成。",
     "> 方向：需求(FR) → Gherkin 场景(scenarios/*.feature) → bats 用例 → QA 归档证据(docs/qa/)。", "",
     "## FR 总表", "",
     "| FR | feature_id | release 范围 | 证据级别 | status | BATS 文件 | 用例数 | 场景文件 |",
     "|---|---|---|---|---|---|---|---|"]
for fid, frid in FR.items():
    f = BYID[fid]
    mod = next(m for m in MODULES if fid in m[2])
    n = 0 if f["bats"] == "-" else sum(1 for k, v in assign.items() if v == fid)
    bats_disp = f["bats"] if f["bats"] != "-" else "—（无自动化用例）"
    T.append(f"| {frid} | {fid} | {f['rel']} | {f['ev']} | {f['status']} | {bats_disp} | {n} | scenarios/{mod[0]}.feature |")
T += ["", f"覆盖合计：{covered} 个 bats 用例（99_coverage 为元测试不计），26 个 FR 全部有场景或文档证据。", "",
      "## NFR（非功能需求）", "",
      "| NFR | 描述 | 证据 |",
      "|---|---|---|",
      "| NFR-001 | 合并门禁：CI 五 job（bats/lint/secret-scan/identity-guard/plan-sync）全绿 | .github/workflows/ci.yml + GitHub runs |",
      "| NFR-002 | 提交身份合规：GitHub noreply 身份，identity-guard 全历史扫描 | scripts/ci/identity-guard.sh |",
      "| NFR-003 | 容器非 root：builder 用户 + host uid/gid 映射 | tests/bats/01_dockerfile.bats、03_container.bats |",
      "| NFR-004 | 磁盘自保：BB_DISKMON_DIRS 双阈值（STOPTASKS/ABORT） | tests/bats/05_kas.bats |",
      "| NFR-005 | APT 镜像可配：默认官方源，构建机可覆写 | docker/common/install-yocto-deps.sh + docs/06-process/ci.md |",
      "| NFR-006 | CVE 离线模式：CVE_DB_UPDATE_INTERVAL=-1，离线库优先 | tests/bats/09_cvedb.bats |",
      "| NFR-007 | 凭据安全：tracked 仓库无明文凭据，workflow 用自动 token | tests/bats/02_workflows.bats + secret-scan job |",
      "| NFR-008 | 测试覆盖完整性：features↔bats 双向注册校验（99_coverage 元测试 6 用例） | tests/bats/99_coverage.bats |",
      "", "## 用例级明细", "",
      "| FR | feature_id | bats 文件 | 用例 |", "|---|---|---|---|"]
for (fn, name), fid in sorted(assign.items(), key=lambda kv: (FR[kv[1]], kv[0][0], kv[0][1])):
    T.append(f"| {FR[fid]} | {fid} | {fn} | {name} |")
with open(os.path.join(REQ, "traceability.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(T) + "\n")

# ---------- README ----------
R = ["# docs/01-requirements —— 需求与 BDD 场景层（ISO/IEC/IEEE 29148 轻量落地）", "",
     "- `srs.md`：软件需求规格（29148 结构：引言/总体描述/具体需求/验收准则）",
     "- `traceability.md`：FR/NFR → Gherkin 场景 → bats 用例 → QA 证据 的追溯矩阵（生成物）",
     "- `scenarios/*.feature`：BDD 场景层，按 9 个模块组织，映射 205 个 bats 用例（生成物，勿手改用例名）",
     "- `acceptance-plan.md`：ISO/IEC/IEEE 12207 验收流程与判据", "",
     "**事实源约定**：功能清单唯一事实源仍是 `config/features.txt`；本目录全部生成物由 `scripts/ci/gen_requirements.py` 再生，bats 本体是唯一可执行事实。", ""]
with open(os.path.join(REQ, "README.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(R) + "\n")

print("scenarios:", sorted(os.listdir(SCN)))
print("traceability.md 行数:", len(T))
print("OK")
