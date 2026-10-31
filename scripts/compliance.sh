#!/usr/bin/env bash
# =============================================================================
# scripts/compliance.sh — 开源合规证据采集（SBOM / CVE / FOSS）
#
# 采集口径（四版本）：
#   SBOM  3.1/4.0/5.0 出 SPDX 2.2，6.0 只出 3.0.1 —— 不强行统一，
#         报告层出「格式差异」节说明语义差别（见 docs/compliance.md）。
#   CVE   3.1/4.0/5.0 读构建期 cve-check 的清单；6.0 没有 cve-check.bbclass，
#         构建后跑 sbom-cve-check CLI 导出 yocto-cve-check-manifest，
#         两者字段与 status 取值一致，所以统计口径可以复用。
#   FOSS  统一「构建后批量」：从 work/downloads 取源码包，容器内跑 ScanCode，
#         每包四件（json/csv/spdx/html）+ 一份汇总。镜像内软件包数取自
#         <image>.rootfs.manifest，覆盖率按「已扫 / 镜像内包数」如实记账。
#
# 产物：
#   work/artifacts/<release>/<variant><sfx>/compliance.json      汇总（report.sh 读它）
#   work/artifacts/<release>/<variant><sfx>/compliance.d/*.json  各节明细（可单独重跑）
#   work/artifacts/<release>/<variant><sfx>/cve/*.json           CVE 清单（6.0）
#   work/artifacts/<release>/<variant><sfx>/foss/*                扫描结果
#
# 用法：
#   scripts/compliance.sh --release <r> [--variant <v>] [--machine <m>]
#                         [--only sbom|cve|foss] [--foss-limit N] [--force]
#   scripts/compliance.sh status --release <r> [--variant <v>]
#
# 环境变量：
#   YP_SBOM_CVE_CHECK_VERSION  sbom-cve-check 版本，默认 1.3.5
#   YP_CVE_SBOM_CACHE          6.0 的 git 型 CVE 库，默认 work/cve-cache/sbom
#   YP_DEPLOY_DIR / YP_ARTIFACT_DIR  测试用路径覆盖
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

SCV_VERSION="${YP_SBOM_CVE_CHECK_VERSION:-1.3.5}"
SCV_DIR="${ROOT_DIR}/work/tools/sbom-cve-check-${SCV_VERSION}"
CVE_SBOM_CACHE="${YP_CVE_SBOM_CACHE:-${ROOT_DIR}/work/cve-cache/sbom}"
NVD_FKIE="${CVE_SBOM_CACHE}/nvd-fkie"
FOSS_LIMIT=20
HTML_TOP=3

usage() {
    cat <<'EOF'
用法：
  scripts/compliance.sh --release <r> [--variant general|custom] [--machine <m>]
                        [--only sbom|cve|foss] [--foss-limit N] [--force]
  scripts/compliance.sh status --release <r> [--variant general|custom]
  scripts/compliance.sh --print-sbom --release <r> [--variant V] [--machine M]

--only      只跑某一件，其余节保留上一次的结果（默认三件全跑）
--foss-limit    批量扫描的源码包上限，默认 20，0 表示不限
--force     丢弃 compliance.d/ 后重跑
--print-sbom   只打印镜像级 SBOM 的绝对路径（找不到则返回非零）
EOF
}

die_usage() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

###############################################################################
# 路径规则
###############################################################################
deploy_root() { printf '%s' "${YP_DEPLOY_DIR:-${ROOT_DIR}/work/kas-${release}-${variant}${sfx}/build/tmp/deploy}"; }
artifact_dir() { printf '%s' "${YP_ARTIFACT_DIR:-${ROOT_DIR}/work/artifacts/${release}/${variant}${sfx}}"; }
# 各节明细目录。用变量而不是函数：下面有多处 "${SECTIONS_DIR}/x.json" 形式的
# 引用，函数名当变量展开在 set -u 下直接报 unbound。
SECTIONS_DIR=""

relpath() {
    local path="$1"
    [[ "${path}" == "${ROOT_DIR}/"* ]] && printf '%s' "${path#"${ROOT_DIR}/"}" || printf '%s' "${path}"
}

# 镜像内软件包清单：两代命名不同（3.1/4.0 没有 .rootfs 中缀）。
image_manifest() {
    local deploy candidate
    deploy="$(deploy_root)"
    for candidate in \
        "${deploy}/images/${machine}/${image}-${machine}.rootfs.manifest" \
        "${deploy}/images/${machine}/${image}-${machine}.manifest"; do
        [[ -f "${candidate}" ]] && {
            printf '%s' "${candidate}"
            return 0
        }
    done
    return 1
}

# 镜像级 SBOM。四版的形态各不相同（都实测过）：
#   3.1 dunfell   <image>-<machine>.spdx.tar.gz       包内 <image>.spdx.json
#   4.0 kirkstone <image>-<machine>.spdx.json         单文件（没有 .rootfs 中缀）
#   5.0 scarthgap <image>-<machine>.rootfs.spdx.tar.zst 包内 <image>.rootfs-<ts>.spdx.json
#   6.0 wrynose   <image>-<machine>.rootfs.spdx.json  单文件
# 所以走「候选列表 + 归档解包」，不按 release 分支写死。
sbom_file() {
    local deploy imgs candidate
    deploy="$(deploy_root)"
    imgs="${deploy}/images/${machine}"
    for candidate in \
        "${imgs}/${image}-${machine}.rootfs.spdx.json" \
        "${imgs}/${image}-${machine}.spdx.json" \
        "${deploy}/spdx/${machine}/${image}-${machine}.rootfs.spdx.json" \
        "${deploy}/spdx/${image}-${machine}.rootfs.spdx.json"; do
        [[ -f "${candidate}" ]] && {
            printf '%s' "${candidate}"
            return 0
        }
    done
    for candidate in \
        "${imgs}/${image}-${machine}.rootfs.spdx.tar.zst" \
        "${imgs}/${image}-${machine}.spdx.tar.zst" \
        "${imgs}/${image}-${machine}.spdx.tar.gz" \
        "${imgs}/${image}-${machine}.rootfs.spdx.tar.gz"; do
        [[ -f "${candidate}" ]] || continue
        extract_sbom_from_archive "${candidate}" && return 0
    done
    # 兜底 glob：2.2 的 by-machine 目录在不同小版本间有出入
    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        printf '%s' "${candidate}"
        return 0
    done < <(find "${deploy}/spdx" -maxdepth 2 -name "${image}*.rootfs.spdx.json" 2>/dev/null |
        LC_ALL=C sort | head -n 1)
    return 1
}

extract_sbom_from_archive() {
    local archive="$1" dest member name listing
    dest="$(artifact_dir)/sbom"
    mkdir -p -- "${dest}"
    case "${archive}" in
        *.tar.zst) listing="$(tar --zstd -tf "${archive}" 2>/dev/null)" ;;
        *) listing="$(tar -tzf "${archive}" 2>/dev/null)" ;;
    esac
    # 包内既有镜像 SBOM 也有逐 recipe 的（recipe-*.spdx.json），只认以镜像名开头的那个。
    member="$(printf '%s\n' "${listing}" |
        grep -E "(^|/)${image}[-.][^/]*\.spdx\.json$" | LC_ALL=C sort | head -n 1)"
    [[ -n "${member}" ]] || return 1
    name="$(basename -- "${member}")"
    case "${archive}" in
        *.tar.zst) tar --zstd -xOf "${archive}" "${member}" >"${dest}/${name}" ;;
        *) tar -xzOf "${archive}" "${member}" >"${dest}/${name}" ;;
    esac
    [[ -s "${dest}/${name}" ]] || return 1
    printf '%s' "${dest}/${name}"
}

# cve-check 的镜像级清单：3.1 是 <image>-<ts>.json，4.0/5.0 是 <image>.rootfs.json。
image_cve_manifest() {
    local deploy imgs candidate newest=""
    deploy="$(deploy_root)"
    imgs="${deploy}/images/${machine}"
    for candidate in \
        "${imgs}/${image}-${machine}.rootfs.json" \
        "${imgs}/${image}-${machine}.json"; do
        [[ -f "${candidate}" ]] && {
            printf '%s' "${candidate}"
            return 0
        }
    done
    for candidate in "${imgs}/${image}-${machine}-"*.json; do
        [[ -f "${candidate}" ]] || continue
        case "${candidate}" in *.testdata.json) continue ;; esac
        if [[ -z "${newest}" || "${candidate}" -nt "${newest}" ]]; then
            newest="${candidate}"
        fi
    done
    [[ -n "${newest}" ]] || return 1
    printf '%s' "${newest}"
}

###############################################################################
# SBOM
###############################################################################
step_sbom() {
    local sbom stats_out section
    if ! sbom="$(sbom_file)"; then
        write_section sbom <<'JSON'
{"available": false, "reason": "找不到镜像级 SBOM；先跑 scripts/build.sh --release <r> --variant <v> --spdx"}
JSON
        log_warn "SBOM：找不到镜像级产物（先跑 --spdx 构建）"
        return 0
    fi
    stats_out="$(mktemp)"
    python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${sbom}" >"${stats_out}"
    local bytes sha packaging="single-json"
    # 5.0 把镜像级 SBOM 打成 tar.zst、3.1 打成 tar.gz，4.0/6.0 是单文件；
    # 报告里要写清形态差异，否则「为什么 3.1 的 SBOM 只剩一个压缩包」没法解释。
    if [[ "${sbom}" == "$(artifact_dir)"/* ]]; then
        local imgs
        imgs="$(deploy_root)/images/${machine}"
        if [[ -f "${imgs}/${image}-${machine}.rootfs.spdx.tar.zst" ||
            -f "${imgs}/${image}-${machine}.spdx.tar.zst" ]]; then
            packaging="tar.zst"
        else
            packaging="tar.gz"
        fi
    fi
    bytes="$(stat -Lc %s -- "${sbom}")"
    sha="$(sha256sum -- "${sbom}" | awk '{print $1}')"
    python3 - "${stats_out}" "${sbom}" "${bytes}" "${sha}" "$(relpath "${sbom}")" "${packaging}" <<'PY' >"${SECTIONS_DIR}/sbom.json"
import json, sys
stats_path, sbom, size, digest, relative, packaging = sys.argv[1:7]
with open(stats_path, encoding="utf-8") as handle:
    stats = json.load(handle)
stats.update({
    "available": True,
    "path": relative,
    "packaging": packaging,
    "bytes": int(size),
    "sha256": digest,
})
json.dump({"sbom": stats}, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
sys.stdout.write("\n")
PY
    rm -f -- "${stats_out}"
    log_info "SBOM：$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["sbom"];print("%s %d 包 %d 文件 %.1f MB PURL %.0f%%" % (d["format"], d["packages"], d["files"], d["bytes"]/1048576, d["purl_ratio"]*100))' "${SECTIONS_DIR}/sbom.json")"
}

###############################################################################
# CVE
###############################################################################
ensure_scv() {
    [[ -x "${SCV_DIR}/bin/sbom-cve-check" ]] && return 0
    command -v pip3 >/dev/null 2>&1 ||
        die "缺少 pip3：装 sbom-cve-check ${SCV_VERSION} 需要它（${SCV_DIR}）"
    log_info "安装 sbom-cve-check ${SCV_VERSION} 到 work/tools/（pip3 --target，只一次）"
    mkdir -p -- "${SCV_DIR}"
    pip3 install --quiet --disable-pip-version-check --target "${SCV_DIR}" \
        "sbom-cve-check==${SCV_VERSION}"
    [[ -x "${SCV_DIR}/bin/sbom-cve-check" ]] || die "安装后仍找不到 ${SCV_DIR}/bin/sbom-cve-check"
}

# 6.0：构建后跑 CLI。--offline-mode 是「全程没联网」的机器化证据：
# 开了它 clone/fetch 直接失败，能跑通就说明只读了本地库。
cve_wrynose() {
    local sbom manifest counts db_rev db_date
    sbom="$(sbom_file)" || {
        write_section cve <<'JSON'
{"available": false, "reason": "6.0 的 CVE 结论来自 SBOM，缺 SPdx 产物时无法扫描"}
JSON
        log_warn "CVE：缺 SBOM，跳过（先跑 --spdx 构建）"
        return 0
    }
    [[ -d "${NVD_FKIE}" ]] ||
        die "缺少 6.0 的 CVE 库 ${NVD_FKIE#"${ROOT_DIR}/"}；先跑 scripts/cve-db.sh sync --release wrynose"
    ensure_scv
    manifest="$(artifact_dir)/cve/yocto-cve-check-manifest.json"
    mkdir -p -- "$(dirname -- "${manifest}")"
    log_info "CVE：sbom-cve-check 扫描镜像 SBOM（离线，约 10~40 秒）"
    PYTHONPATH="${SCV_DIR}" python3 "${SCV_DIR}/bin/sbom-cve-check" \
        --databases-dir "${CVE_SBOM_CACHE}" \
        --sbom-type spdx3 --sbom-path "${sbom}" \
        --disable-auto-updates --offline-mode \
        --set-db-cfg cvelist disabled=true \
        --export-type yocto-cve-check-manifest \
        --export-path "${manifest}" >"$(artifact_dir)/cve/sbom-cve-check.log" 2>&1 ||
        {
            tail -n 20 "$(artifact_dir)/cve/sbom-cve-check.log" >&2
            die "sbom-cve-check 失败，日志见 work/artifacts/.../cve/sbom-cve-check.log"
        }
    [[ -s "${manifest}" ]] || die "sbom-cve-check 未产出清单：${manifest}"
    db_rev="$(git -C "${NVD_FKIE}" rev-parse --short HEAD 2>/dev/null || printf 'n/a')"
    db_date="$(git -C "${NVD_FKIE}" log -1 --format=%cI 2>/dev/null || printf 'n/a')"
    python3 - "${manifest}" "${db_rev}" "${db_date}" "$(relpath "${manifest}")" <<'PY' >"${SECTIONS_DIR}/cve.json"
import json, sys
path, db_rev, db_date, relative = sys.argv[1:5]
counts = {"Unpatched": 0, "Patched": 0, "Ignored": 0}
with open(path, encoding="utf-8") as handle:
    report = json.load(handle)
for package in report.get("package", []):
    for issue in package.get("issue", []):
        status = issue.get("status", "Unpatched")
        counts[status] = counts.get(status, 0) + 1
data = {
    "available": True,
    "source": "sbom-cve-check",
    "tool_version": None,
    "manifest": relative,
    "packages": len(report.get("package", [])),
    "db": "nvd-json-data-feeds (nvd-fkie)",
    "db_revision": db_rev,
    "db_date": db_date,
    "unpatched": counts["Unpatched"],
    "patched": counts["Patched"],
    "ignored": counts["Ignored"],
}
json.dump({"cve": data}, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
sys.stdout.write("\n")
PY
    log_info "CVE：$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["cve"];print("%d 包 %d/%d/%d" % (d["packages"], d["unpatched"], d["patched"], d["ignored"]))' "${SECTIONS_DIR}/cve.json")"
}

# 3.1/4.0/5.0：优先读镜像级清单；没有就按 manifest 过滤 deploy/cve/ 下的逐包清单。
cve_cve_check() {
    local db_name db_path manifest cve_dir
    db_name="$(cve_db_filename "${release}" || true)"
    db_path="${ROOT_DIR}/work/downloads/CVE_CHECK/${db_name}"
    manifest="$(image_cve_manifest || true)"
    cve_dir="$(deploy_root)/cve"
    if [[ -z "${manifest}" && ! -d "${cve_dir}" ]]; then
        write_section cve <<'JSON'
{"available": false, "reason": "既没有镜像级 CVE 清单，也没有 deploy/cve/ 逐包清单；本组合没跑 --cve 构建"}
JSON
        log_warn "CVE：没有清单（本组合没跑 --cve 构建）"
        return 0
    fi
    python3 - "${manifest:-}" "${cve_dir}" "$(image_manifest || true)" \
        "${release}" "${db_name}" "$([[ -f "${db_path}" ]] && relpath "${db_path}" || printf '缺失')" \
        "$([[ -f "${db_path}.meta.json" ]] && python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("built_at","n/a"))' "${db_path}.meta.json" || printf 'n/a')" \
        <<'PY' >"${SECTIONS_DIR}/cve.json"
import glob
import json
import os
import sys

manifest, cve_dir, image_manifest, release, db_name, db_rel, db_built = sys.argv[1:8]
names = set()
if image_manifest and os.path.isfile(image_manifest):
    with open(image_manifest, encoding="utf-8") as handle:
        for line in handle:
            fields = line.split()
            if fields:
                names.add(fields[0])

counts = {"Unpatched": 0, "Patched": 0, "Ignored": 0}
packages = 0
scope = "image-manifest"
source = "cve-check"
relative = os.path.basename(manifest) if manifest else ""

if manifest and os.path.isfile(manifest):
    with open(manifest, encoding="utf-8") as handle:
        report = json.load(handle)
    for package in report.get("package", []):
        packages += 1
        for issue in package.get("issue", []):
            status = issue.get("status", "Unpatched")
            counts[status] = counts.get(status, 0) + 1
else:
    # 逐包清单（deploy/cve/<recipe>_cve.json）。按 manifest 过滤，保证
    # 与 6.0 的「只看镜像内容」口径一致；过滤后一个包都没对上时退回全量并标注。
    scoped = []
    for path in sorted(glob.glob(os.path.join(cve_dir, "*_cve.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
        except (ValueError, OSError):
            continue
        for package in data.get("package", []):
            if names and package.get("name") not in names:
                continue
            scoped.append(package)
    if not scoped:
        scope = "all-recipes"
        for path in sorted(glob.glob(os.path.join(cve_dir, "*_cve.json"))):
            try:
                with open(path, encoding="utf-8") as handle:
                    data = json.load(handle)
            except (ValueError, OSError):
                continue
            scoped.extend(data.get("package", []))
    packages = len(scoped)
    for package in scoped:
        for issue in package.get("issue", []):
            status = issue.get("status", "Unpatched")
            counts[status] = counts.get(status, 0) + 1

data = {
    "available": True,
    "source": source,
    "manifest": relative or None,
    "packages": packages,
    "scope": scope,
    "db": db_name,
    "db_file": db_rel,
    "db_built_at": db_built,
    "unpatched": counts["Unpatched"],
    "patched": counts["Patched"],
    "ignored": counts["Ignored"],
}
json.dump({"cve": data}, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
sys.stdout.write("\n")
PY
    log_info "CVE：$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["cve"];print("%d 包 %d/%d/%d (%s)" % (d["packages"], d["unpatched"], d["patched"], d["ignored"], d.get("scope","-")))' "${SECTIONS_DIR}/cve.json")"
}

step_cve() {
    if [[ "${release}" == "wrynose" ]]; then
        cve_wrynose
    else
        cve_cve_check
    fi
}

###############################################################################
# FOSS
###############################################################################
scancode_bin_in_container() {
    bash "${ROOT_DIR}/scripts/scancode.sh" path --release "${release}" 2>/dev/null
}

ensure_scancode() {
    local bin
    bin="$(scancode_bin_in_container)" || die "scancode.sh 不认识 release ${release}"
    local host_dir="${ROOT_DIR}/work/tools/$(basename -- "$(dirname -- "${bin}")")"
    if [[ ! -x "${host_dir}/scancode" ]]; then
        log_info "ScanCode 未就绪，先准备（约 140~220 MB，只一次）"
        bash "${ROOT_DIR}/scripts/scancode.sh" sync --release "${release}"
    fi
    printf '%s' "${bin}"
}

# 从 work/downloads 里给镜像内的每个包找源码包。找不到的（file:// / git 源）
# 记在缺口里，不静默跳过 —— 覆盖率要能对上账。
collect_foss_input() {
    local input="$1" manifest pkg found count=0
    manifest="$(image_manifest || true)"
    [[ -n "${manifest}" ]] || {
        log_warn "FOSS：缺 <image>.rootfs.manifest，无法确定镜像内软件包"
        return 1
    }
    : >"${input}"
    printf '# package\tsource-archive\n' >>"${input}"
    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] || continue
        found="$(find "${ROOT_DIR}/work/downloads" -maxdepth 1 -type f \
            \( -name "${pkg}-*.tar.*" -o -name "${pkg}-*.tgz" -o -name "${pkg}-*.zip" \) \
            ! -name '*.done' 2>/dev/null | LC_ALL=C sort | head -n 1)"
        [[ -n "${found}" ]] || continue
        printf '%s\t%s\n' "${pkg}" "$(relpath "${found}")" >>"${input}"
        ((count += 1))
        if ((FOSS_LIMIT > 0)) && ((count >= FOSS_LIMIT)); then
            break
        fi
    done < <(awk '{print $1}' "${manifest}" | LC_ALL=C sort -u)
    awk 'NR>1' "${input}" | wc -l
}

step_foss() {
    local art input rel_art rel_input declared scanned
    art="$(artifact_dir)"
    mkdir -p -- "${art}/foss" "${ROOT_DIR}/work/tmp"
    input="${ROOT_DIR}/work/tmp/foss-input-${release}${sfx}.tsv"
    if ! declared="$(collect_foss_input "${input}")"; then
        write_section foss <<'JSON'
{"available": false, "reason": "缺镜像 manifest，无法确定镜像内软件包"}
JSON
        return 0
    fi
    declared="$(awk '{print $1}' "$(image_manifest)" | LC_ALL=C sort -u | wc -l)"
    scanned="$(awk 'NR>1' "${input}" | wc -l)"
    if ((scanned == 0)); then
        write_section foss <<'JSON'
{"available": false, "reason": "work/downloads 里没有能与镜像内软件包对上的源码包"}
JSON
        log_warn "FOSS：没有可扫的源码包"
        return 0
    fi
    local bin
    bin="$(ensure_scancode)"
    rel_art="$(relpath "${art}")"
    rel_input="$(relpath "${input}")"
    log_info "FOSS：容器内扫描 ${scanned} 个源码包（单包含解包与四件产物，预计 5~20 分钟）"
    ./project.sh shell --release "${release}" --variant "${variant}" --machine "${machine}" \
        -- bash "/work/scripts/lib/foss-scan-in-container.sh" \
        "${bin}" "/work/${rel_art}/foss" "/work/${rel_input}" "${HTML_TOP}" ||
        log_warn "FOSS：扫描脚本返回非零，按已产出的结果汇总"
    python3 "${ROOT_DIR}/scripts/lib/foss-summary.py" \
        "${art}/foss" "${input}" "${SECTIONS_DIR}/foss-section.json" \
        "${declared}" "${FOSS_LIMIT}" >/dev/null
    python3 - "${SECTIONS_DIR}/foss-section.json" "${FOSS_LIMIT}" "${rel_art}/foss" <<'PY' >"${SECTIONS_DIR}/foss.json"
import json, sys
path, limit, artifacts = sys.argv[1:4]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
os_ok = data.get("scanned", 0) > 0
data.update({
    "available": os_ok,
    "limit": int(limit),
    "artifacts": artifacts,
    "tool": "scancode-toolkit",
    "source": "work/downloads",
})
if not os_ok:
    data["reason"] = "扫描没有产出任何结果"
json.dump({"foss": data}, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
sys.stdout.write("\n")
PY
    rm -f -- "${SECTIONS_DIR}/foss-section.json"
    log_info "FOSS：$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))["foss"];print("%d/%d 包，%d 文件，覆盖率 %.1f%%" % (d["scanned"], d["declared"], d["files_total"], d["coverage"]*100))' "${SECTIONS_DIR}/foss.json")"
}

###############################################################################
# 汇总
###############################################################################
write_section() {
    local section="$1"
    # 节文件统一是 {"<section>": {...}} 的形状（merge_sections 直接 update 顶层键），
    # 失败分支给的是裸对象，这里补上外层键，否则合并后 compliance.json 里
    # "sbom" 会整个消失，只留下一个孤零零的 available=false。
    {
        printf '{"%s": ' "${section}"
        cat
        printf '}\n'
    } >"${SECTIONS_DIR}/${section}.json"
}

merge_sections() {
    local out="$1"
    python3 - "${SECTIONS_DIR}" "${out}" "${release}" "${variant}" "${machine}" "${TAG}" \
        "$(git -C "${ROOT_DIR}" rev-parse --short HEAD)" "$(date +%Y%m%d)" <<'PY'
import json
import os
import sys
import time

sections_dir, out, release, variant, machine, tag, commit, date = sys.argv[1:9]
merged = {
    "release": release,
    "variant": variant,
    "machine": machine,
    "tag": tag,
    "commit": commit,
    "date": date,
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
}
for name in ("sbom", "cve", "foss"):
    path = os.path.join(sections_dir, name + ".json")
    if not os.path.isfile(path):
        merged[name] = {"available": False, "reason": "未采集（--only 跳过了这一节）"}
        continue
    with open(path, encoding="utf-8") as handle:
        merged.update(json.load(handle))
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(merged, handle, ensure_ascii=False, sort_keys=True, indent=2)
    handle.write("\n")
print(out)
PY
}

do_status() {
    local art out
    art="$(artifact_dir)"
    out="${art}/compliance.json"
    printf 'release=%s variant=%s machine=%s\n' "${release}" "${variant}" "${machine}"
    printf 'compliance.json: %s\n' "$([[ -f "${out}" ]] && relpath "${out}" || printf '缺失')"
    if [[ -f "${out}" ]]; then
        python3 - "${out}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for name in ("sbom", "cve", "foss"):
    block = data.get(name, {})
    if not block.get("available"):
        print("%-5s unavailable: %s" % (name, block.get("reason", "")))
        continue
    if name == "sbom":
        print("sbom  %s %d 包 %d 文件 %.1f MB PURL %.0f%%"
              % (block["format"], block["packages"], block["files"],
                 block["bytes"] / 1048576, block["purl_ratio"] * 100))
    elif name == "cve":
        print("cve   %s %d 包 未修复 %d / 已修复 %d / 忽略 %d"
              % (block["source"], block["packages"], block["unpatched"],
                 block["patched"], block["ignored"]))
    else:
        print("foss  %d/%d 包 %d 文件 覆盖率 %.1f%%"
              % (block["scanned"], block["declared"], block["files_total"],
                 block["coverage"] * 100))
PY
    fi
    if [[ -d "${art}/foss" ]]; then
        printf 'foss 产物: %s（%s）\n' "$(relpath "${art}/foss")" \
            "$(du -sh -- "${art}/foss" 2>/dev/null | cut -f1)"
    fi
}

###############################################################################
# 入口
###############################################################################
command=""
if [[ "${1:-}" == "status" ]]; then
    command=status
    shift
fi

print_sbom=0
release=""
variant="general"
machine="qemux86-64"
only="all"
force=0
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die_usage "--release 缺少参数"
            release="$2"
            shift 2
            ;;
        --variant)
            (($# >= 2)) || die_usage "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die_usage "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        --only)
            (($# >= 2)) || die_usage "--only 缺少参数"
            only="$2"
            shift 2
            ;;
        --foss-limit)
            (($# >= 2)) || die_usage "--foss-limit 缺少参数"
            FOSS_LIMIT="$2"
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        --print-sbom)
            print_sbom=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die_usage "未知参数：$1" ;;
    esac
done

[[ -n "${release}" ]] || {
    usage >&2
    exit 2
}
case "${only}" in
    all | sbom | cve | foss) ;;
    *) die_usage "--only 只能是 sbom / cve / foss / all" ;;
esac
[[ "${FOSS_LIMIT}" =~ ^[0-9]+$ ]] || die_usage "--foss-limit 必须是非负整数"

resolve_all "${release}" "${variant}" "${machine}"
sfx="$(machine_suffix "${machine}")"
# resolve_all 只导出大写 IMAGE/MACHINE，脚本内部统一用小写变量。
image="${IMAGE}"
SECTIONS_DIR="$(artifact_dir)/compliance.d"

if ((print_sbom)); then
    sbom_file || die "找不到 ${release}/${variant} 的镜像级 SBOM；先跑 scripts/build.sh --release ${release} --variant ${variant} --spdx"
    exit 0
fi

if [[ "${command}" == "status" ]]; then
    do_status
    exit 0
fi

mkdir -p -- "${SECTIONS_DIR}"
if ((force)); then
    rm -rf -- "${SECTIONS_DIR:?}"
    mkdir -p -- "${SECTIONS_DIR}"
fi

case "${only}" in
    sbom) step_sbom ;;
    cve) step_cve ;;
    foss) step_foss ;;
    all)
        step_sbom
        step_cve
        step_foss
        ;;
esac

out="$(merge_sections "$(artifact_dir)/compliance.json")"
printf '\n合规证据：%s\n' "$(relpath "${out}")"
do_status
