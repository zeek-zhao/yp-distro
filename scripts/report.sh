#!/usr/bin/env bash
# Runs BATS and generates a real-build QA report.
# Artifact details come from kas build output under work/; this script does not build.
# Use --render-only to create an archive without running tests or writing JUnit output.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=lib/artifacts.sh
source "${ROOT_DIR}/scripts/lib/artifacts.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/report.sh <release|all> [--variant V] [--machine M] [--render-only]
  scripts/report.sh --release R [--variant V] [--machine M] [--render-only]
  scripts/report.sh --release R [--variant V] [--machine M] --sdk
  scripts/report.sh --release R [--variant V] [--machine M] --compliance
  scripts/report.sh --print-fingerprint

--sdk / --compliance 只出那一类归档，不跑 BATS：
  sdk        读 work/artifacts/.../sdk.json（scripts/sdk.sh 产出）
  compliance 读 work/artifacts/.../compliance.json（scripts/compliance.sh 产出）
EOF
}

# source_fingerprint 在 scripts/lib/common.sh（#114：deploy-guard 也要用，单一真源）。

if [[ "${1:-}" == "--print-fingerprint" ]]; then
    [[ $# -eq 1 ]] || die "--print-fingerprint 不接受其他参数"
    printf 'SOURCE_FINGERPRINT=%s\n' "$(source_fingerprint)"
    exit 0
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    [[ $# -eq 1 ]] || die "--help 不接受其他参数"
    usage
    exit 0
fi

release=""
variant="general"
machine_arg="qemux86-64"
render_only=0
sdk_mode=0
compliance_mode=0
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die "--release 缺少参数"
            [[ -z "${release}" ]] || die "release 只能指定一次"
            release="$2"
            shift 2
            ;;
        --variant)
            (($# >= 2)) || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die "--machine 缺少参数"
            machine_arg="$2"
            shift 2
            ;;
        --render-only)
            render_only=1
            shift
            ;;
        --sdk)
            sdk_mode=1
            shift
            ;;
        --compliance)
            compliance_mode=1
            shift
            ;;
        -h | --help)
            [[ $# -eq 1 ]] || die "--help 不接受其他参数"
            usage
            exit 0
            ;;
        -*)
            die "未知参数：$1"
            ;;
        *)
            [[ -z "${release}" ]] || die "release 只能指定一次"
            release="$1"
            shift
            ;;
    esac
done
[[ -n "${release}" ]] || {
    usage >&2
    exit 2
}

if [[ "${release}" == "all" ]]; then
    report_tag="multiple"
    machine=""
    image=""
else
    resolve_all "${release}" "${variant}" "${machine_arg}"
    report_tag="${TAG}"
    machine="${MACHINE}"
    image="${IMAGE}"
fi

# machine 后缀：默认 qemux86-64 为空，与 build.sh / qemu.sh 规则一致。
# 日期与 commit 在 --sdk 与常规两条路径都要用，统一提前算。
machine_sfx="$(machine_suffix "${machine_arg}")"
variant_sfx=""
[[ "${variant}" == "general" ]] || variant_sfx="-${variant}"
date_stamp="$(date +%Y%m%d)"
commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"

if ((sdk_mode)); then
    [[ "${release}" != "all" ]] || die "--sdk 不支持 all，请逐个 release 出归档"
    # 路径可用环境变量顶掉：BATS 用例要在不污染 work/artifacts 与 docs/qa 的前提下
    # 验证渲染逻辑（与 YP_DEPLOY_DIR / YP_DEGRADED_FILE 同一套路）。
    sdk_json="${YP_SDK_JSON:-${ROOT_DIR}/work/artifacts/${release}/${variant}${machine_sfx}/sdk.json}"
    [[ -f "${sdk_json}" ]] || die "缺少 ${sdk_json#"${ROOT_DIR}/"}；先跑 scripts/sdk.sh --release ${release} --variant ${variant}"
    command -v python3 >/dev/null 2>&1 || die "找不到 python3（渲染 SDK 归档需要）"
    if [[ -n "${YP_SDK_ARCHIVE:-}" ]]; then
        sdk_archive="${YP_SDK_ARCHIVE}"
    else
        sdk_archive="${ROOT_DIR}/docs/qa/${release}/sdk-${date_stamp}-${commit}"
        [[ "${variant}" == "general" ]] || sdk_archive+="-${variant}"
        sdk_archive+="${machine_sfx}.md"
    fi
    mkdir -p -- "$(dirname -- "${sdk_archive}")"
    sdk_status=0
    python3 - "${sdk_json}" "${sdk_archive}" "${sdk_json#"${ROOT_DIR}/"}" <<'PY' || sdk_status=$?
import json
import sys

source, target, source_rel = sys.argv[1:4]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)

sdk = data.get("sdk", {})
esdk = data.get("esdk", {})
build_seconds = data.get("build_seconds")
checks = [
    ("SDK 安装脚本可执行且 source 后 gcc 可用", sdk.get("installed") and sdk.get("gcc") not in ("", "n/a")),
    ("eSDK 安装后 devtool 可用", esdk.get("installed") and esdk.get("devtool") == "ok"),
]
passed = all(ok for _, ok in checks)

lines = [
    "# SDK / eSDK 归档",
    "",
    "- Release: `%s`" % data.get("release"),
    "- Variant: `%s`" % data.get("variant"),
    "- Machine: `%s`" % data.get("machine"),
    "- Commit: `%s`" % data.get("commit"),
    "- Tag: `%s`" % data.get("tag"),
    "- 数据来源: `%s`" % source_rel,
    "- 构建耗时: %s" % ("%ss" % build_seconds if build_seconds is not None else "n/a"),
    "",
    "## 产物",
    "",
    "| 类型 | 文件 | 字节 | SHA-256 |",
    "|---|---|---:|---|",
]
for label, item in (("SDK", sdk), ("eSDK", esdk)):
    lines.append(
        "| %s | `%s` | %s | `%s` |"
        % (label, item.get("file", "n/a"), item.get("bytes", "n/a"), item.get("sha256", "n/a"))
    )

lines += [
    "",
    "## 安装验证",
    "",
    "| 检查项 | 结果 |",
    "|---|---|",
]
lines.append("| SDK 安装后 `gcc -dumpversion` | `%s` |" % sdk.get("gcc", "n/a"))
lines.append("| eSDK 安装后 `devtool --help` | `%s` |" % esdk.get("devtool", "n/a"))
lines.append("")
lines.append("## 验收结论")
lines.append("")
lines.append("**%s**" % ("PASS（需求 §7.3：不允许降级）" if passed else "FAIL"))
lines.append("")
for label, ok in checks:
    lines.append("- [%s] %s" % ("x" if ok else " ", label))
lines.append("")

with open(target, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines))

print("SDK  : %s gcc=%s" % (sdk.get("file", "n/a"), sdk.get("gcc", "n/a")))
print("eSDK : %s devtool=%s" % (esdk.get("file", "n/a"), esdk.get("devtool", "n/a")))
print("结论 : %s" % ("PASS" if passed else "FAIL"))
sys.exit(0 if passed else 1)
PY
    printf 'Archive: %s\n' "${sdk_archive#"${ROOT_DIR}/"}"
    exit "${sdk_status}"
fi

# ---- 合规证据归档（issue #26）----
# 独立文件，不并入主报告：主报告已被 140+ 例 BATS 校验，塞进 SBOM/FOSS
# 这些大块内容后，任何格式调整都会连带打断主报告的用例。
if ((compliance_mode)); then
    [[ "${release}" != "all" ]] || die "--compliance 不支持 all，请逐个 release 出归档"
    compliance_json="${YP_COMPLIANCE_JSON:-${ROOT_DIR}/work/artifacts/${release}/${variant}${machine_sfx}/compliance.json}"
    [[ -f "${compliance_json}" ]] ||
        die "缺少 ${compliance_json#"${ROOT_DIR}/"}；先跑 scripts/compliance.sh --release ${release} --variant ${variant}"
    compliance_archive="${YP_COMPLIANCE_ARCHIVE:-${ROOT_DIR}/docs/qa/${release}/compliance-${date_stamp}-${commit}${variant_sfx}${machine_sfx}.md}"
    mkdir -p -- "$(dirname -- "${compliance_archive}")"
    compliance_status=0
    python3 - "${compliance_json}" "${compliance_archive}" "${release}" "${variant}" \
        "${machine_arg}" "${report_tag}" "${commit}" "${date_stamp}" \
        "${YP_DEGRADED_FILE:-${ROOT_DIR}/config/degraded.txt}" <<'PY' || compliance_status=$?
import json
import os
import sys

(
    json_path,
    target,
    release,
    variant,
    machine,
    tag,
    commit,
    date_stamp,
    degraded_file,
) = sys.argv[1:10]

with open(json_path, encoding="utf-8") as handle:
    data = json.load(handle)
sbom = data.get("sbom") or {}
cve = data.get("cve") or {}
foss = data.get("foss") or {}

# 合规相关的降级项。distro-backfill 之类与本报告无关，列进来只会稀释结论。
COMPLIANCE_ASPECTS = {"spdx-format", "cve-tool", "foss-scan"}
degraded_rows = []
if os.path.isfile(degraded_file):
    with open(degraded_file, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = [field.strip() for field in line.split("|")]
            if len(fields) < 4:
                continue
            aspect, row_release, reason, requirement = fields[:4]
            if aspect in COMPLIANCE_ASPECTS and row_release == release:
                degraded_rows.append((aspect, reason, requirement))

sbom_index = sbom.get("kind") == "spdx2-index"
sbom_aggregate = sbom.get("aggregate") or {}
# 索引型文档（3.1/4.0/5.0）的「镜像里到底有什么」只能从外部文档聚合出来，
# 聚合不齐就等于 SBOM 不可用，所以这条进验收门，而不像 PURL 那样只做观测。
index_ok = (not sbom_index) or (
    bool(sbom_aggregate) and (sbom_aggregate.get("missing_count") or 0) == 0
)

checks = [
    ("SBOM 已产出并可解析", bool(sbom.get("available"))),
    ("SBOM 外部引用全部对位（索引型必检）", index_ok),
    ("CVE 清单已产出（采集工具可随版本分叉）", bool(cve.get("available"))),
    ("FOSS 批量扫描有结果", bool(foss.get("available"))),
    ("FOSS 覆盖率 > 0", (foss.get("coverage") or 0) > 0),
    ("PURL 非空率 >= 90%（CRA 漏洞匹配前提，观测项）", (sbom.get("purl_ratio") or 0) >= 0.9),
]
gate = checks[:5]
passed = all(ok for _, ok in gate)

lines = [
    "# 合规证据报告",
    "",
    "- Kind: `compliance`",
    "- Release: `%s`" % release,
    "- Variant: `%s`" % variant,
    "- Machine: `%s`" % machine,
    "- Tag: `%s`" % tag,
    "- Commit: `%s`" % commit,
    "- Date: `%s`" % date_stamp,
    "",
    "> 采集口径：SBOM 与 CVE 在构建期/构建后取，FOSS 是构建后对 `work/downloads`",
    "> 的源码包做批量扫描。三者都不参与构建增量决策。",
    "",
    "## SBOM",
    "",
]

if sbom.get("available"):
    kind = sbom.get("kind", "spdx2-full")
    aggregate = sbom.get("aggregate") or {}
    kind_text = {
        "spdx2-index": "索引型：文档内只有 1 个 image 包，组件清单以 `externalDocumentRefs` 指向 `deploy/spdx/` 下的 per-recipe 文档",
        "spdx2-full": "自包含：2.2 文档内直接列出组件",
        "spdx3": "自包含：单个 `@graph` 内同时含包与文件",
    }.get(kind, "`%s`" % kind)
    rows = [
        ("格式", "`%s`" % sbom.get("format", "n/a")),
        ("文件", "`%s`" % sbom.get("path", "n/a")),
        ("体积", "%s（%s 字节）"
         % ("%.1f MB" % (int(sbom.get("bytes") or 0) / 1048576.0), sbom.get("bytes", "n/a"))),
        ("SHA-256", "`%s`" % sbom.get("sha256", "n/a")),
        ("打包形态", "`%s`" % sbom.get("packaging", "n/a")),
        ("文档形态", kind_text),
    ]
    if kind == "spdx2-index":
        missing = aggregate.get("missing") or []
        rows += [
            ("外部文档引用", "%s" % sbom.get("external_documents", "n/a")),
            ("镜像组件（CONTAINS 对位）", "%s" % sbom.get("components", "n/a")),
            ("已解析外部文档", "%s%s"
             % (aggregate.get("documents", "n/a"),
                "" if not missing else "（缺 %s 份：%s）"
                % (aggregate.get("missing_count", len(missing)),
                   "、".join("`%s`" % name for name in missing[:5])))),
            ("聚合包元素", "%s" % aggregate.get("packages", "n/a")),
            ("聚合文件元素", "%s" % aggregate.get("files", "n/a")),
        ]
    else:
        rows += [
            ("包元素", "%s" % sbom.get("packages", "n/a")),
            ("文件元素", "%s" % sbom.get("files", "n/a")),
        ]
    denominator = sbom.get("packages")
    if kind == "spdx2-index" and aggregate.get("packages"):
        denominator = aggregate["packages"]
    rows.append(
        ("PURL 非空率", "%.1f%%（%s/%s）"
         % ((sbom.get("purl_ratio") or 0) * 100, sbom.get("purl_nonempty", "n/a"), denominator))
    )
    lines += ["| 项 | 值 |", "|---|---|"]
    lines += ["| %s | %s |" % (name, value) for name, value in rows]
    vex = sbom.get("vex")
    if vex:
        lines.append(
            "| VEX | fixed %s / not_affected %s / vulnerability %s |"
            % (vex.get("fixed", 0), vex.get("not_affected", 0), vex.get("vulnerability", 0))
        )
    else:
        lines.append("| VEX | 本版本无（`vex.bbclass` 只有 5.0/6.0 有） |")
    licenses = (aggregate.get("licenses") if kind == "spdx2-index" else None) or sbom.get("licenses") or {}
    if licenses:
        top = "，".join("`%s` %s" % (name, count) for name, count in list(licenses.items())[:8])
        lines += ["| 许可证 top | %s |" % top]
    if kind == "spdx2-index":
        lines += [
            "",
            "索引型的包数不能直接照抄文档里的 `packages`（那是 1 个 image 包）。",
            "上表的「镜像组件」「聚合包元素」是沿 `CONTAINS` 关系把 %s 份外部文档按"
            % aggregate.get("documents", sbom.get("components", "n/a")),
            "`documentNamespace` 逐个对位后累加出来的，口径与 6.0 自包含文档一致。",
        ]
else:
    lines += ["未产出：%s" % sbom.get("reason", "n/a")]

lines += ["", "## CVE", ""]
if cve.get("available"):
    lines += [
        "| 项 | 值 |",
        "|---|---|",
        "| 采集工具 | `%s` |" % cve.get("source", "n/a"),
        "| 清单 | `%s` |" % (cve.get("manifest") or "（逐包清单聚合）"),
        "| 包数 | %s |" % cve.get("packages", "n/a"),
        "| 未修复 / 已修复 / 忽略 | %s / %s / %s |"
        % (cve.get("unpatched", "n/a"), cve.get("patched", "n/a"), cve.get("ignored", "n/a")),
        "| 数据源 | `%s` |" % cve.get("db", "n/a"),
    ]
    if cve.get("db_revision"):
        lines.append(
            "| 库版本 | `%s`（%s） |" % (cve.get("db_revision"), cve.get("db_date", "n/a"))
        )
    if cve.get("db_built_at"):
        lines.append("| 库构建时间 | %s |" % cve.get("db_built_at"))
    if cve.get("scope"):
        lines.append("| 统计口径 | `%s` |" % cve.get("scope"))
    if cve.get("source") == "sbom-cve-check":
        lines += [
            "",
            "6.0 没有 `cve-check.bbclass`，这里用构建后 CLI 扫镜像 SBOM 得到清单，",
            "导出格式选 `yocto-cve-check-manifest`，与前三版 `cve-check` 的字段和",
            "`status` 取值一致，所以统计口径可以并排看。扫描时开了 `--offline-mode`：",
            "它会让任何 clone/fetch 直接失败，能跑通即证明全程只读本地库。",
        ]
else:
    lines += ["未产出：%s" % cve.get("reason", "n/a")]

lines += ["", "## FOSS", ""]
if foss.get("available"):
    lines += [
        "| 项 | 值 |",
        "|---|---|",
        "| 工具 | `%s` |" % foss.get("tool", "n/a"),
        "| 源码来源 | `%s` |" % foss.get("source", "n/a"),
        "| 镜像内软件包 | %s |" % foss.get("declared", "n/a"),
        "| 本次已扫 | %s（上限 %s） |" % (foss.get("scanned", "n/a"), foss.get("limit", "n/a")),
        "| 覆盖率 | %.1f%% |" % ((foss.get("coverage") or 0) * 100),
        "| 扫描文件数 | %s |" % foss.get("files_total", "n/a"),
        "| 产物 | `%s/`（每包 json/csv/spdx，前 3 个另有 html） |" % foss.get("artifacts", "n/a"),
    ]
    if foss.get("failed"):
        lines.append("| 失败包 | %s |" % "、".join("`%s`" % name for name in foss["failed"][:8]))
    licenses = foss.get("licenses") or {}
    if licenses:
        top = "，".join("`%s` %s" % (name, count) for name, count in list(licenses.items())[:10])
        lines += ["", "许可证表达式分布（按检出次数）：", "", top]
    packages = foss.get("packages") or []
    if packages:
        lines += [
            "",
            "| 包 | 源码包 | 文件数 | 清晰度 | 主要许可证 |",
            "|---|---|---:|---:|---|",
        ]
        for entry in packages[:25]:
            top = "、".join(list(entry.get("licenses") or {})[:3]) or "-"
            lines.append(
                "| `%s` | `%s` | %s | %s | %s |"
                % (
                    entry.get("package"),
                    entry.get("archive", ""),
                    entry.get("files", 0),
                    entry.get("clarity", "-"),
                    top,
                )
            )
        if len(packages) > 25:
            lines.append("")
            lines.append("（其余 %d 个包的明细见 `foss-summary.json`）" % (len(packages) - 25))
    lines += [
        "",
        "覆盖率不是 100% 是预期的：`work/downloads` 只覆盖有 `SRC_URI` 归档的上游源码，",
        "`file://` 与 git 源的包不在其中，缺口按包名如实记账，不做静默补齐。",
    ]
else:
    lines += ["未产出：%s" % foss.get("reason", "n/a")]

lines += [
    "",
    "## 格式差异",
    "",
    "SPDX 不强行统一（3.1/4.0/5.0 出 2.2，6.0 只出 3.0.1），跨版本只比",
    "「包名 + 版本 + 许可证」，不比文档内部结构。本节把差异写死，避免把",
    "口径不同当成回归。",
    "",
    "| release | SPDX | 镜像级 SBOM 形态 | 文档自包含性 | VEX |",
    "|---|---|---|---|---|",
    "| dunfell 3.1.33 | 2.2 | `<image>-<machine>.spdx.tar.gz`（包内 `<image>-<ts>.spdx.json`） | 索引型 | 无 |",
    "| kirkstone 4.0.35 | 2.2 | `<image>-<machine>.spdx.json` 单文件 | 索引型 | 无 |",
    "| scarthgap 5.0.20 | 2.2（默认） | `<image>-<machine>.rootfs.spdx.tar.zst` | 索引型 | 有 |",
    "| wrynose 6.0.4 | 3.0.1 | `<image>-<machine>.rootfs.spdx.json` 单文件 | 自包含 | 有 |",
    "",
    "本版本实际：格式 `%s`，打包形态 `%s`，文档形态 `%s`。"
    % (sbom.get("format", "n/a"), sbom.get("packaging", "n/a"), sbom.get("kind", "n/a")),
    "",
    "语义差异（不能直接比大小）：",
    "",
    "- 3.1/4.0/5.0 的镜像文档是**索引**：`packages` 只有 1 个 image 包，组件靠",
    "  `externalDocumentRefs` + `CONTAINS` 指向 `deploy/spdx/<ver>/` 下的 per-recipe 文档，",
    "  照抄 `packages` 会得到「1 个包」的假象，必须聚合后再比；",
    "- 6.0 的 `software_Package` 把构建期元素也算进去，数字天然比 2.2 的聚合值大，",
    "  两版包数不能当回归指标；",
    "- PURL 只有 6.0 默认产出（`SPDX_PACKAGE_URL`），2.2 的 per-recipe 文档没有 purl，",
    "  所以前三版 PURL 非空率是 0%，这是能力差异不是采集失败；",
    "- 3.0.1 的 VEX 由 `security_Vex*` 关系元素承载（`SPDX_INCLUDE_VEX`），2.2 没有对应表达；",
    "- 5.0 的镜像级 SBOM 是归档，要解压后才能当输入用，6.0 是可直接喂工具的单文件。",
    "",
    "## 降级清单",
    "",
]
if not degraded_rows:
    lines.append("无（本版本合规相关能力全部按标准实现）")
else:
    lines += ["| aspect | 理由 | 需求条款 |", "|---|---|---|"]
    for aspect, reason, requirement in degraded_rows:
        lines.append("| `%s` | %s | %s |" % (aspect, reason, requirement))

lines += ["", "## 验收结论", "", "**%s**" % ("PASS" if passed else "FAIL"), ""]
for label, ok in checks:
    lines.append("- [%s] %s" % ("x" if ok else " ", label))
lines.append("")

with open(target, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines))

if sbom.get("kind") == "spdx2-index":
    aggregate = sbom.get("aggregate") or {}
    print(
        "SBOM : %s 索引型 %s 组件（聚合 %s 包，PURL %.0f%%）"
        % (
            sbom.get("format", "n/a"),
            sbom.get("components", "n/a"),
            aggregate.get("packages", "n/a"),
            (sbom.get("purl_ratio") or 0) * 100,
        )
    )
else:
    print(
        "SBOM : %s %s 包（PURL %.0f%%）"
        % (sbom.get("format", "n/a"), sbom.get("packages", "n/a"), (sbom.get("purl_ratio") or 0) * 100)
    )
print(
    "CVE  : %s %s/%s/%s"
    % (
        cve.get("source", "n/a"),
        cve.get("unpatched", "n/a"),
        cve.get("patched", "n/a"),
        cve.get("ignored", "n/a"),
    )
)
print("FOSS : %s/%s 包（覆盖率 %.1f%%）" % (
    foss.get("scanned", "n/a"), foss.get("declared", "n/a"), (foss.get("coverage") or 0) * 100))
print("结论 : %s" % ("PASS" if passed else "FAIL"))
sys.exit(0 if passed else 1)
PY
    printf 'Archive: %s\n' "${compliance_archive#"${ROOT_DIR}/"}"
    exit "${compliance_status}"
fi

if ((render_only == 0)); then
    command -v docker >/dev/null 2>&1 ||
        die "找不到 docker（BATS 在开发容器里跑，见 docs/build-env.md）"
    command -v python3 >/dev/null 2>&1 || die "找不到 python3（解析 JUnit 报告需要）"
fi

start_time="$(date --iso-8601=seconds)"
fingerprint="$(source_fingerprint)"
hostname="$(hostname)"
mkdir -p "${ROOT_DIR}/docs/qa/${release}"
duration=0
bats_status=0
tests="n/a"
passed="n/a"
failures="n/a"
skipped="n/a"
failure_list=""

if ((render_only == 0)); then
    mkdir -p "${ROOT_DIR}/reports"
    target_xml="${ROOT_DIR}/reports/bats-${release}-${variant}${machine_sfx}-${date_stamp}.xml"

    SECONDS=0
    # BATS 必须跑在容器里，用宿主 bats 是错的：
    #   1) 版本不可控——构建机上实测 /usr/bin/bats 是 1.2.1，镜像里是 1.14；
    #      老版本对**嵌套 bats**（03_container.bats 会再调一层验 skip 语义）的
    #      处理不同，会把外层 BATS_TEST_NAME 漏进内层，报
    #      `bats: unknown test name 'test_xxx'`。同一个用例在两种 bats 上结论
    #      不同，比用例失败更糟：会让人开始怀疑用例本身。
    #   2) 1.14 的 junit formatter 直接把 XML 写 **stdout**（--output 目录被
    #      忽略），所以不再需要中间目录，也不该再 mv。
    # dev.sh 自带「已在容器内就直接本地执行」的分支，所以这条命令在 CI 容器里
    # 与工作机上行为一致。
    # stdin 必须重定向：部分用例的 teardown 会 rm -r 含只读 git 对象的临时仓库，
    # rm 在 tty 上会停在 “remove write-protected regular file?” 提示上永久阻塞。
    if bash "${ROOT_DIR}/scripts/dev.sh" bats --formatter junit \
        -r /work/tests/bats >"${target_xml}" </dev/null; then
        bats_status=0
    else
        bats_status=$?
    fi
    duration="${SECONDS}"
    end_time="$(date --iso-8601=seconds)"

    junit_source="${target_xml}"
    if [[ ! -s "${junit_source}" ]]; then
        log_error "Bats 未生成预期的 JUnit 文件：${junit_source}"
        exit 1
    fi
    # stdout 必须只有 XML。dev.sh 首次运行会自动构建镜像，构建日志如果落在
    # stdout 上就会顶到 `<?xml` 前面，后面 ET.parse 报「syntax error: line 1,
    # column 0」——报错完全没提真正的原因，所以这里先把第一行验一道。
    first_line="$(head -n 1 "${junit_source}")"
    if [[ "${first_line}" != '<?xml'* && "${first_line}" != '<testsuites'* ]]; then
        log_error "JUnit 文件首行不是 XML，说明有其它输出混进了 stdout："
        head -n 5 "${junit_source}" >&2
        exit 1
    fi

    summary="$(
        python3 - "${target_xml}" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
tests = failures = skipped = 0
failure_rows = []
for suite in suites:
    tests += int(suite.attrib.get("tests", 0))
    failures += int(suite.attrib.get("failures", 0)) + int(suite.attrib.get("errors", 0))
    skipped += int(suite.attrib.get("skipped", 0))
    for case in suite.findall("testcase"):
        for result in list(case):
            if result.tag in ("failure", "error"):
                message = result.attrib.get("message", "").replace("\n", " ").strip()
                failure_rows.append(
                    f"- `{case.attrib.get('classname', '')}::{case.attrib.get('name', '')}`: {message}"
                )
print(tests)
print(failures)
print(skipped)
print("\n".join(failure_rows))
PY
    )" || {
        log_error "无法解析 JUnit 报告：${target_xml}"
        exit 1
    }
    tests="$(printf '%s\n' "${summary}" | sed -n '1p')"
    failures="$(printf '%s\n' "${summary}" | sed -n '2p')"
    skipped="$(printf '%s\n' "${summary}" | sed -n '3p')"
    passed=$((tests - failures - skipped))
    failure_list="$(printf '%s\n' "${summary}" | tail -n +4)"
else
    end_time="$(date --iso-8601=seconds)"
fi

if [[ "${release}" != "all" ]]; then
    if [[ -n "${YP_DEPLOY_DIR:-}" ]]; then
        deploy_dir="${YP_DEPLOY_DIR}"
        [[ "${deploy_dir}" == /* ]] || deploy_dir="${ROOT_DIR}/${deploy_dir}"
    else
        deploy_dir="${ROOT_DIR}/work/kas-${release}-${variant}${machine_sfx}/build/tmp/deploy/images/${machine}"
    fi
    if primary_artifact="$(artifact_primary "${deploy_dir}" "${image}" "${machine}")"; then
        :
    else
        primary_artifact=""
    fi
    artifact_paths=()
    while IFS= read -r artifact_path; do
        [[ -n "${artifact_path}" ]] && artifact_paths+=("${artifact_path}")
    done < <(artifact_list "${deploy_dir}" "${image}" "${machine}")
else
    deploy_dir=""
    primary_artifact=""
    artifact_paths=()
fi

relative_path() {
    local path="$1"
    if [[ "${path}" == "${ROOT_DIR}/"* ]]; then
        printf '%s' "${path#"${ROOT_DIR}/"}"
    else
        printf '%s' "${path}"
    fi
}

render_crossdiff() {
    local crossdiff_file="${YP_CROSSDIFF_FILE:-${ROOT_DIR}/config/crossdiff.txt}"
    if [[ ! -f "${crossdiff_file}" ]]; then
        printf 'n/a（尚无其它版本归档，无可比对象）\n'
        return
    fi
    awk -F'|' -v current="${release}" '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            aspects[++rows] = trim($1)
            for (i = 2; i <= NF; i++) {
                field = trim($i)
                separator = index(field, "=")
                name = substr(field, 1, separator - 1)
                values[rows, name] = substr(field, separator + 1)
                if (!(name in seen)) {
                    seen[name] = 1
                    releases[++columns] = name
                }
            }
        }
        END {
            if (!rows || !(current in seen) || columns < 2) {
                print "n/a（尚无其它版本归档，无可比对象）"
                exit
            }
            printf "| aspect | 本版本(%s) |", current
            for (i = 1; i <= columns; i++)
                if (releases[i] != current) printf " %s |", releases[i]
            printf "\n|---|---|"
            for (i = 1; i < columns; i++) printf "---|"
            printf "\n"
            for (row = 1; row <= rows; row++) {
                value = values[row, current]
                printf "| `%s` | %s |", aspects[row], (value == "" ? "n/a" : value)
                for (i = 1; i <= columns; i++) {
                    if (releases[i] == current) continue
                    value = values[row, releases[i]]
                    printf " %s |", (value == "" ? "n/a" : value)
                }
                printf "\n"
            }
        }
    ' "${crossdiff_file}"
}

# 只有真跑过测试/构建的归档才写 sha256：--render-only 常在测试里被调用，
# 若在 render 时重写，会把已归档文件的 commit 头改成当前 HEAD（#41）。
# 校验文件名跟归档名走：artifacts-<date>-<sha>[-<variant>].sha256。
# 原来固定叫 artifacts.sha256，同一 release 每跑一次报告就重写一次，
# 于是旧归档报告（<date>-<old-sha>.md）指向的文件头部 commit 已经不是它了。
checksum_name="artifacts-${date_stamp}-${commit}"
[[ "${variant}" == "general" ]] || checksum_name+="-${variant}"
checksum_name+="${machine_sfx}"

if ((render_only == 0)) && ((${#artifact_paths[@]} > 0)); then
    checksum_file="${ROOT_DIR}/docs/qa/${release}/${checksum_name}.sha256"
    {
        printf '# Source: release=%s variant=%s commit=%s\n' \
            "${release}" "${variant}" "${commit}"
        for artifact_path in "${artifact_paths[@]}"; do
            printf '%s  %s\n' "$(artifact_sha256 "${artifact_path}")" \
                "$(relative_path "${artifact_path}")"
        done
    } >"${checksum_file}"
fi

# ---- CVE 检查（issue #48 / #26）----
# 是否开启记录在 build.sh 写的 .flags 里：没跑过 --cve 的构建不能凭空写出 CVE 结论。
build_flags_file="${ROOT_DIR}/work/logs/build-${release}-${variant}${machine_sfx}.flags"
cve_enabled=0
if [[ -f "${build_flags_file}" ]] && grep -qx 'cve=1' "${build_flags_file}"; then
    cve_enabled=1
fi

count_cve_status() {
    local manifest="$1"
    command -v python3 >/dev/null 2>&1 || {
        printf 'n/a'
        return 0
    }
    python3 - "${manifest}" <<'PY' 2>/dev/null || printf 'n/a'
import json, sys
counts = {"Unpatched": 0, "Patched": 0, "Ignored": 0}
with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)
for package in report.get("package", []):
    for issue in package.get("issue", []):
        status = issue.get("status", "Unpatched")
        counts[status] = counts.get(status, 0) + 1
print("%d / %d / %d" % (counts["Unpatched"], counts["Patched"], counts["Ignored"]))
PY
}

count_db_cves() {
    local db="$1"
    command -v python3 >/dev/null 2>&1 || {
        printf 'n/a'
        return 0
    }
    python3 - "$db" <<'PY' 2>/dev/null || printf 'n/a'
import sqlite3, sys
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
print(conn.execute("SELECT count(*) FROM NVD").fetchone()[0])
PY
}

db_built_at() {
    local meta="$1"
    command -v python3 >/dev/null 2>&1 || {
        printf 'n/a'
        return 0
    }
    python3 - "$meta" <<'PY' 2>/dev/null || printf 'n/a'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("built_at", "n/a"))
PY
}

render_cve() {
    local db_name="" db_path="" lib_rows="n/a" lib_built="n/a"
    local manifest="" manifest_name="n/a" status_counts="n/a"
    local compliance_json="${ROOT_DIR}/work/artifacts/${release}/${variant}${machine_sfx}/compliance.json"

    # 有 compliance.json 就以它为准：6.0 的结论只能从 sbom-cve-check 来，
    # 走留在这里的旧分支必然写成「不适用」。#26 之后四版都走这条。
    if [[ -f "${compliance_json}" ]] &&
        python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); sys.exit(0 if (d.get("cve") or {}).get("available") else 1)' \
            "${compliance_json}" 2>/dev/null; then
        python3 - "${compliance_json}" "${compliance_json#"${ROOT_DIR}/"}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    cve = json.load(handle).get("cve") or {}
relative = sys.argv[2]

print("| 项 | 值 |")
print("|---|---|")
print("| 采集工具 | `%s` |" % cve.get("source", "n/a"))
print("| 清单 | `%s` |" % (cve.get("manifest") or "（逐包清单聚合）"))
print("| 包数 | %s |" % cve.get("packages", "n/a"))
print("| 未修复 / 已修复 / 忽略 | %s / %s / %s |"
      % (cve.get("unpatched", "n/a"), cve.get("patched", "n/a"), cve.get("ignored", "n/a")))
if cve.get("db_revision"):
    print("| 数据源 | `%s`（`%s`） |" % (cve.get("db"), cve.get("db_revision")))
else:
    print("| 数据源 | `%s` |" % cve.get("db", "n/a"))
print("| 明细 | `%s` |" % relative)
PY
        return
    fi

    if ((cve_enabled == 0)); then
        printf '未开启（本次构建没有 --cve；CVE 只对 custom variant 有意义）\n'
        return
    fi

    if db_name="$(cve_db_filename "${release}")"; then
        db_path="${ROOT_DIR}/work/downloads/CVE_CHECK/${db_name}"
    else
        # 6.0 没有 cve-check.bbclass，走 sbom-cve-check 的 git 型数据库。
        printf '6.0 不适用：wrynose 用 sbom-cve-check（nvd-json-data-feeds / cvelistV5），不读 sqlite 库\n'
        return
    fi
    if [[ -f "${db_path}" ]]; then
        lib_rows="$(count_db_cves "${db_path}")"
        if [[ -f "${db_path}.meta.json" ]]; then
            lib_built="$(db_built_at "${db_path}.meta.json")"
        fi
    fi

    if [[ -n "${deploy_dir}" ]]; then
        # 镜像清单名跨版本不同：3.1 的 IMAGE_NAME 自带时间戳、也没有
        # IMAGE_NAME_SUFFIX（<image>-<machine>-<ts>.json）；3.2+ 是
        # <image>-<machine>.rootfs.json。三种都试，别只认一种。
        local candidate newest=""
        for candidate in \
            "${deploy_dir}/${image}-${machine}.rootfs.json" \
            "${deploy_dir}/${image}-${machine}.json"; do
            if [[ -f "${candidate}" ]]; then
                manifest="${candidate}"
                break
            fi
        done
        if [[ -z "${manifest}" ]]; then
            for candidate in "${deploy_dir}/${image}-${machine}-"*.json; do
                [[ -f "${candidate}" ]] || continue
                case "${candidate}" in *.testdata.json) continue ;; esac
                if [[ -z "${newest}" || "${candidate}" -nt "${newest}" ]]; then
                    newest="${candidate}"
                fi
            done
            manifest="${newest}"
        fi
        if [[ -n "${manifest}" ]]; then
            manifest_name="$(basename "${manifest}")"
            status_counts="$(count_cve_status "${manifest}")"
        fi
    fi

    printf '| 项 | 值 |\n|---|---|\n'
    printf '| 开关 | `--cve`（kas/features/cve.yml） |\n'
    printf '| 离线库 | `%s` |\n' \
        "$([[ -f "${db_path}" ]] && relative_path "${db_path}" || printf '缺失')"
    printf '| 库内 CVE 数 | %s |\n' "${lib_rows}"
    printf '| 库构建时间 | %s |\n' "${lib_built}"
    printf '| 镜像 CVE 清单 | `%s` |\n' "${manifest_name}"
    printf '| 未修复 / 已修复 / 忽略 | %s |\n' "${status_counts}"
}

degraded_file="${YP_DEGRADED_FILE:-${ROOT_DIR}/config/degraded.txt}"
[[ -f "${degraded_file}" ]] || die "降级配置不存在：${degraded_file}"
degraded_rows=()
while IFS='|' read -r aspect degraded_release reason requirement || [[ -n "${aspect:-}" ]]; do
    aspect="$(printf '%s' "${aspect:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    degraded_release="$(printf '%s' "${degraded_release:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    reason="$(printf '%s' "${reason:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    requirement="$(printf '%s' "${requirement:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "${aspect}" || "${aspect}" == \#* ]] && continue
    [[ "${degraded_release}" == "${release}" ]] || continue
    degraded_rows+=("${aspect}|${reason}|${requirement}")
done <"${degraded_file}"

serial_log="${ROOT_DIR}/work/artifacts/${release}/${variant}${machine_sfx}/qemu-serial.log"
serial_exists=0
serial_login="no"
serial_bytes=""
if [[ -f "${serial_log}" ]]; then
    serial_exists=1
    grep -qi 'login:' "${serial_log}" && serial_login="yes"
    serial_bytes="$(stat -c %s -- "${serial_log}")"
fi

# 缺失构建统计只能记 n/a，不能新增 degraded；config/degraded.txt 是唯一真本，
# 99_coverage.bats 会双向校验报告降级清单（CI 不执行真构建）。
build_log="${ROOT_DIR}/work/logs/build-${release}-${variant}${machine_sfx}.log"
build_meta="${build_log%.log}.meta"
build_duration="n/a"
tasks_summary="n/a"
sstate_hit="n/a"
if [[ -f "${build_meta}" ]]; then
    meta_value="$(cat -- "${build_meta}")"
    [[ ! "${meta_value}" =~ ^[0-9]+$ ]] || build_duration="${meta_value}s"
fi
if [[ -f "${build_log}" ]]; then
    tasks_value="$(sed -nE "s/.*NOTE: Tasks Summary: Attempted ([0-9]+) tasks of which ([0-9]+) didn't need to be rerun.*/\1 \/ \2/p" "${build_log}" | tail -n 1)"
    # Current is the total objects in the cache directory, not the number of hits.
    # 4.0+ 的格式：
    #   Sstate summary: Wanted 50 Local 20 Mirrors 0 Missed 30 Current 40 (40% match, ...)
    # 3.1（bitbake 1.46）没有 Local/Mirrors，命中数叫 Found：
    #   Sstate summary: Wanted 1108 Found 0 Missed 1108 Current 0 (0% match, 0% complete)
    # 两种都得认，否则 dunfell 的 Sstate hit 会退化成 n/a。
    sstate_value="$(sed -nE 's/.*Sstate summary: Wanted ([0-9]+) Local ([0-9]+) Mirrors [0-9]+ Missed [0-9]+ Current [0-9]+ \(([0-9]+)% match,.*/\2\/\1 (\3%)/p' "${build_log}" | tail -n 1)"
    if [[ -z "${sstate_value}" ]]; then
        sstate_value="$(sed -nE 's/.*Sstate summary: Wanted ([0-9]+) Found ([0-9]+) Missed [0-9]+ Current [0-9]+ \(([0-9]+)% match,.*/\2\/\1 (\3%)/p' "${build_log}" | tail -n 1)"
    fi
    [[ -z "${tasks_value}" ]] || tasks_summary="${tasks_value}"
    [[ -z "${sstate_value}" ]] || sstate_hit="${sstate_value}"
fi

# 归档名：general 保持 <date>-<sha>[-render]（历史文件不动），
# 其它 variant 追加 -<variant>，否则同一 release 的两个 variant 会互相覆盖。
archive_name="${date_stamp}-${commit}"
[[ "${variant}" == "general" ]] || archive_name+="-${variant}"
archive_name+="${machine_sfx}"
((render_only == 0)) || archive_name+="-render"
archive="${ROOT_DIR}/docs/qa/${release}/${archive_name}.md"
{
    printf '# QA Report\n\n'
    if ((render_only)); then
        printf -- '- Kind: `render-only`\n'
    else
        printf -- '- Kind: `bats+build`\n'
    fi
    printf -- '- Release: `%s`\n' "${release}"
    printf -- '- Variant: `%s`\n' "${variant}"
    printf -- '- Machine: `%s`\n' "$([[ -n "${machine}" ]] && printf '%s' "${machine}" || printf 'n/a')"
    printf -- '- Commit: `%s`\n' "${commit}"
    printf -- '- Tag: `%s`\n' "${report_tag}"
    printf -- '- SOURCE_FINGERPRINT: `%s`\n' "${fingerprint}"
    printf -- '- Hostname: `%s`\n' "${hostname}"
    printf -- '- Start time: `%s`\n' "${start_time}"
    printf -- '- End time: `%s`\n' "${end_time}"
    printf -- '- Duration: `%ss`\n\n' "${duration}"
    printf '## Test statistics\n\n'
    printf '| Tests | Passed | Failed | Skipped |\n|---:|---:|---:|---:|\n'
    printf '| %s | %s | %s | %s |\n\n' \
        "${tests}" "${passed}" "${failures}" "${skipped}"
    printf '## Failures\n\n'
    if [[ -n "${failure_list}" ]]; then
        printf '%s\n' "${failure_list}"
    else
        printf 'None\n'
    fi
    printf '\n## 构建产物\n\n'
    if [[ -n "${primary_artifact}" ]]; then
        printf -- '- Deploy dir: `%s`\n' "$(relative_path "${deploy_dir}")"
        printf -- '- Artifact: `%s`\n' "$(basename "${primary_artifact}")"
        printf -- '- Artifact bytes: `%s`\n' "$(artifact_bytes "${primary_artifact}")"
        printf -- '- Artifact SHA-256: `%s`\n' "$(artifact_sha256 "${primary_artifact}")"
        printf -- '- Image digest: n/a（本地构建无 registry digest）\n'
        printf -- '- 全部产物 sha256: 见 `%s.sha256`（同目录，路径相对仓库根）\n' \
            "${checksum_name}"
    else
        printf -- '- Deploy dir: `%s`\n' \
            "$([[ -n "${deploy_dir}" ]] && relative_path "${deploy_dir}" || printf 'n/a')"
        printf -- '- Artifact: n/a（未构建）\n'
        printf -- '- Artifact bytes: n/a（未构建）\n'
        printf -- '- Artifact SHA-256: n/a（未构建）\n'
        printf -- '- Image digest: n/a（本地构建无 registry digest）\n'
    fi
    printf '\n### 构建统计\n\n'
    printf -- '- Build duration: %s\n' "${build_duration}"
    printf -- '- Tasks attempted / cached: %s\n' "${tasks_summary}"
    printf -- '- Sstate hit: %s\n' "${sstate_hit}"
    if [[ -f "${build_log}" ]]; then
        printf -- '- Build log: `%s`\n' "${build_log}"
    fi
    printf '\n## QEMU 串口\n\n'
    if ((serial_exists)); then
        printf -- '- 串口日志: `work/artifacts/%s/%s%s/qemu-serial.log`\n' \
            "${release}" "${variant}" "${machine_sfx}"
        printf -- '- 启动到 login prompt: `%s`（匹配到 `login:`）\n' "${serial_login}"
        printf -- '- 日志字节数: `%s`\n' "${serial_bytes}"
    else
        printf -- '- 串口日志: n/a（本次未执行 QEMU）\n'
    fi
    printf '\n## CVE 检查\n\n'
    render_cve
    printf '\n## 降级清单\n\n'
    if ((${#degraded_rows[@]} == 0)); then
        printf '无（本版本全部能力按标准实现）\n'
    else
        printf '| aspect | 理由 | 需求条款 |\n|---|---|---|\n'
        for row in "${degraded_rows[@]}"; do
            IFS='|' read -r aspect reason requirement <<<"${row}"
            printf '| `%s` | %s | %s |\n' "${aspect}" "${reason}" "${requirement}"
        done
    fi
    printf '\n## 跨版本差异\n\n'
    render_crossdiff
} >"${archive}"

if ((render_only == 0)); then
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf '| Release | Tests | Passed | Failed | Skipped | Duration |\n'
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf '| %-7s | %5s | %6s | %6s | %6s | %6ss   |\n' \
        "${release}" "${tests}" "${passed}" "${failures}" "${skipped}" "${duration}"
    printf '+---------+-------+--------+--------+--------+----------+\n'
    printf 'JUnit: %s\n' "${target_xml#${ROOT_DIR}/}"
fi
printf 'Archive: %s\n' "${archive#${ROOT_DIR}/}"

exit "${bats_status}"
