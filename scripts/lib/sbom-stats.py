#!/usr/bin/env python3
"""统计一份 SPDX 文档的形态与规模，供合规报告使用。

用法：
    sbom-stats.py <spdx.json> [--spdx-dir <deploy/spdx/<ver>>]

四版 Yocto 的镜像级 SBOM 有三种形态，统计口径必须分开，否则会出现
「3.1 的 SBOM 只有 1 个包」这种看上去像坏了的结论：

  spdx2-index  3.1 / 4.0 / 5.0。镜像文档本身只有 1 个 image 包，组件清单
               以 externalDocumentRefs + CONTAINS 关系指向 deploy/spdx/<ver>/
               下一堆 per-recipe 文档。必须跟随引用聚合，否则包数为 1。
  spdx2-full   2.2 但自包含（未见实例，留作兼容）。
  spdx3        6.0。单个 @graph 里既有包也有文件，自包含。

传了 --spdx-dir 才会做聚合；不传时只报形态与引用数（聚合要读上千份文档）。
"""

import collections
import glob
import json
import os
import sys

DOCREF_PREFIX = "DocumentRef-"


def _ratio(part, total):
    if not total:
        return 0.0
    return round(part / total, 4)


def _purl_count(packages):
    purl = 0
    for package in packages:
        for reference in package.get("externalRefs", []) or []:
            if reference.get("referenceType") == "purl" and reference.get("referenceLocator"):
                purl += 1
                break
    return purl


def _license_counter(packages):
    return collections.Counter(
        (package.get("licenseDeclared") or "NOASSERTION") for package in packages
    )


def contained_documents(data):
    """镜像通过 CONTAINS 关系直接引用的外部文档 id（形如 DocumentRef-<name>）。"""
    ids = set()
    for relation in data.get("relationships", []) or []:
        if relation.get("relationshipType") != "CONTAINS":
            continue
        target = relation.get("relatedSpdxElement") or ""
        if not target.startswith(DOCREF_PREFIX):
            continue
        ids.add(target.split(":", 1)[0])
    return sorted(ids)


def aggregate_2_2(data, ref_ids, spdx_dir):
    """把被引用的 per-recipe 文档聚起来，得到镜像内组件的合计口径。

    对位不能靠文件名：同一 recipe 在目录里会有 `<pkg>`、`<pkg>-dev`、`<pkg>-dbg`、
    `<pkg>-doc` 等多份文档，按前缀猜会挑错对象（实测 5.0 有 12 个名字猜不中）。
    这里用 externalDocumentRefs 里的 `spdxDocument`（= 目标文档的 documentNamespace，
    带 UUID）做精确对位，文件名只用来缩小候选集。
    """
    namespace_of = {}
    for entry in data.get("externalDocumentRefs", []) or []:
        namespace_of[entry.get("externalDocumentId")] = entry.get("spdxDocument")

    index = collections.defaultdict(list)
    for path in glob.glob(os.path.join(spdx_dir, "**", "*.spdx.json"), recursive=True):
        index[os.path.basename(path)[: -len(".spdx.json")]].append(path)
    keys = sorted(index)

    packages_total = 0
    files_total = 0
    purl_total = 0
    licenses = collections.Counter()
    used = 0
    by_name = 0
    missing = []
    for ref_id in ref_ids:
        name = ref_id[len(DOCREF_PREFIX):]
        wanted = namespace_of.get(ref_id)
        matches = [k for k in keys if k == name or k.startswith(name + "-")]
        picked = None
        for key in matches:
            for path in index[key]:
                if not wanted:
                    continue
                try:
                    with open(path, encoding="utf-8") as handle:
                        doc = json.load(handle)
                except (OSError, ValueError):
                    continue
                if doc.get("documentNamespace") == wanted:
                    picked = doc
                    break
            if picked:
                break
        if picked is None and name in index:
            try:
                with open(sorted(index[name])[0], encoding="utf-8") as handle:
                    picked = json.load(handle)
                by_name += 1
            except (OSError, ValueError):
                picked = None
        if picked is None:
            missing.append(name)
            continue
        used += 1
        packages = picked.get("packages", []) or []
        packages_total += len(packages)
        files_total += len(picked.get("files", []) or [])
        purl_total += _purl_count(packages)
        licenses.update(_license_counter(packages))

    return {
        "documents": used,
        "resolved_by_name": by_name,
        "missing": missing[:20],
        "missing_count": len(missing),
        "packages": packages_total,
        "files": files_total,
        "purl_nonempty": purl_total,
        "purl_ratio": _ratio(purl_total, packages_total),
        "licenses": dict(licenses.most_common(10)),
    }


def stats_2_2(data, spdx_dir=None):
    packages = data.get("packages", []) or []
    external = data.get("externalDocumentRefs", []) or []
    ref_ids = contained_documents(data)
    is_index = bool(external) and len(packages) <= 1
    purl = _purl_count(packages)
    result = {
        "format": "SPDX-2.2",
        "spec_version": data.get("spdxVersion", "SPDX-2.2"),
        "document": data.get("name", ""),
        "namespace": data.get("documentNamespace", ""),
        "kind": "spdx2-index" if is_index else "spdx2-full",
        "packages": len(packages),
        "files": len(data.get("files", []) or []),
        "relationships": len(data.get("relationships", []) or []),
        "external_documents": len(external),
        "components": len(ref_ids) if is_index else len(packages),
        "purl_nonempty": purl,
        "purl_ratio": _ratio(purl, len(packages)),
        "licenses": dict(_license_counter(packages).most_common(10)),
        "vex": None,
    }
    if is_index and spdx_dir:
        result["aggregate"] = aggregate_2_2(data, ref_ids, spdx_dir)
        agg = result["aggregate"]
        # 聚合口径才是 CRA 意义上的镜像组件面，顶层字段跟着换成聚合值，
        # 免得调用方各自再判一次 kind。
        result["purl_nonempty"] = agg["purl_nonempty"]
        result["purl_ratio"] = agg["purl_ratio"]
    return result


def stats_3_0(graph, data):
    types = collections.Counter(element.get("type") for element in graph)
    packages = [e for e in graph if e.get("type") == "software_Package"]
    purl = sum(1 for p in packages if p.get("software_packageUrl"))
    licenses = collections.Counter(
        e.get("simplelicensing_licenseExpression")
        for e in graph
        if e.get("type") == "simplelicensing_LicenseExpression"
        and e.get("simplelicensing_licenseExpression")
    )
    spec = ""
    for element in graph:
        if element.get("type") == "CreationInfo" and element.get("specVersion"):
            spec = element["specVersion"]
            break
    sbom = next((e for e in graph if e.get("type") == "software_Sbom"), {})
    return {
        "format": "SPDX-" + (spec or "3.0.1"),
        "spec_version": spec,
        "document": sbom.get("name", ""),
        "namespace": data.get("@context", ""),
        "kind": "spdx3",
        "packages": len(packages),
        "files": types.get("software_File", 0),
        "relationships": types.get("Relationship", 0)
        + types.get("LifecycleScopedRelationship", 0),
        "external_documents": 0,
        "components": len(packages),
        "purl_nonempty": purl,
        "purl_ratio": _ratio(purl, len(packages)),
        "licenses": dict(licenses.most_common(10)),
        # VEX 三件（只有 5.0/6.0 有 vex.bbclass；6.0 用 SPDX 3.0 的关系元素承载）
        "vex": {
            "fixed": types.get("security_VexFixedVulnAssessmentRelationship", 0),
            "not_affected": types.get("security_VexNotAffectedVulnAssessmentRelationship", 0),
            "known_affected": types.get("security_VexAffectedVulnAssessmentRelationship", 0),
            "vulnerability": types.get("security_Vulnerability", 0),
        },
    }


def main():
    args = sys.argv[1:]
    spdx_dir = None
    if "--spdx-dir" in args:
        position = args.index("--spdx-dir")
        if position + 1 >= len(args):
            sys.stderr.write("--spdx-dir 缺少参数\n")
            return 2
        spdx_dir = args[position + 1]
        del args[position:position + 2]
    if len(args) != 1:
        sys.stderr.write("用法：sbom-stats.py <spdx.json> [--spdx-dir <dir>]\n")
        return 2
    with open(args[0], encoding="utf-8") as handle:
        data = json.load(handle)
    if "@graph" in data:
        result = stats_3_0(data.get("@graph") or [], data)
    elif "spdxVersion" in data:
        result = stats_2_2(data, spdx_dir)
    else:
        sys.stderr.write("无法识别的 SPDX 文档（既没有 @graph 也没有 spdxVersion）\n")
        return 1
    json.dump(result, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
