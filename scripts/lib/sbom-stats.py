#!/usr/bin/env python3
"""把一份 SPDX 文档汇总成可比较的统计量。

为什么要单独一个脚本：四版本产出两种格式，
  3.1 / 4.0 / 5.0  SPDX 2.2   （顶层 packages / files / externalRefs）
  6.0              SPDX 3.0.1 （@graph 里按 type 分元素）
字段名完全不同，直接比较没有意义。这里只抽「同义不同名」的几项，
并把两种格式的语义差异交给报告层的「格式差异」节说明。

用法：sbom-stats.py <spdx.json>
输出：JSON（stdout）
"""

import collections
import json
import sys


def _ratio(part, total):
    if not total:
        return 0.0
    return round(part / total, 4)


def stats_2_2(data):
    packages = data.get("packages", [])
    purl = 0
    for package in packages:
        for reference in package.get("externalRefs", []) or []:
            if reference.get("referenceType") == "purl" and reference.get("referenceLocator"):
                purl += 1
                break
    licenses = collections.Counter(
        (package.get("licenseDeclared") or "NOASSERTION") for package in packages
    )
    return {
        "format": "SPDX-2.2",
        "spec_version": data.get("spdxVersion", "SPDX-2.2"),
        "document": data.get("name", ""),
        "namespace": data.get("documentNamespace", ""),
        "packages": len(packages),
        "files": len(data.get("files", []) or []),
        "relationships": len(data.get("relationships", []) or []),
        "purl_nonempty": purl,
        "purl_ratio": _ratio(purl, len(packages)),
        "licenses": dict(licenses.most_common(10)),
        "vex": None,
    }


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
        "packages": len(packages),
        "files": types.get("software_File", 0),
        "relationships": types.get("Relationship", 0)
        + types.get("LifecycleScopedRelationship", 0),
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
    if len(sys.argv) != 2:
        sys.stderr.write("用法：sbom-stats.py <spdx.json>\n")
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
    if "@graph" in data:
        result = stats_3_0(data.get("@graph") or [], data)
    elif "spdxVersion" in data:
        result = stats_2_2(data)
    else:
        sys.stderr.write("无法识别的 SPDX 文档（既没有 @graph 也没有 spdxVersion）\n")
        return 1
    json.dump(result, sys.stdout, ensure_ascii=False, sort_keys=True, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
