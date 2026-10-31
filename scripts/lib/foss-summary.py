#!/usr/bin/env python3
"""把一批 ScanCode 结果汇总成 foss-summary.json。

输入：
  argv[1]  结果目录（每个包一个 <pkg>.json / .csv / .spdx [/ .html]）
  argv[2]  输入清单 TSV（第一列包名，第二列源码包相对路径）
  argv[3]  输出文件
  argv[4]  声明的总包数（镜像内软件包数，用于算覆盖率）
  argv[5]  本次上限（0 = 不限）

输出口径：
  licenses  按 license_expression 计「检出次数」，不是按文件数加权；
  clarity   license_clarity_score.score（0~100，ScanCode 自带的许可清晰度）；

单个包扫描失败（没有 .json）不会让整份汇总失败，只记在 failed 里，
覆盖率照实算 —— 报告层要能看到缺口，不能把失败当成功。
"""

import collections
import json
import os
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def package_entry(name, archive, result_path):
    data = load(result_path)
    detections = data.get("license_detections") or []
    expressions = collections.Counter(
        item.get("license_expression") for item in detections if item.get("license_expression")
    )
    clarity = data.get("summary", {}).get("license_clarity_score", {}).get("score")
    return {
        "package": name,
        "archive": archive,
        "files": len(data.get("files") or []),
        "licenses": dict(expressions.most_common(8)),
        "clarity": clarity,
        "result": os.path.basename(result_path),
    }


def main():
    if len(sys.argv) != 6:
        sys.stderr.write(
            "用法：foss-summary.py <result_dir> <input.tsv> <out.json> <declared> <limit>\n"
        )
        return 2
    result_dir, input_tsv, out_path, declared, limit = sys.argv[1:6]
    entries = []
    failures = []
    with open(input_tsv, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            name, _, archive = line.partition("\t")
            result_path = os.path.join(result_dir, name + ".json")
            if not os.path.isfile(result_path):
                failures.append(name)
                continue
            try:
                entries.append(package_entry(name, archive, result_path))
            except (ValueError, OSError):
                failures.append(name)

    licenses = collections.Counter()
    for entry in entries:
        for expression, count in entry["licenses"].items():
            licenses[expression] += count

    files_total = sum(entry["files"] for entry in entries)
    declared_n = int(declared) if declared.isdigit() else 0
    summary = {
        "declared": declared_n,
        "selected": len(entries) + len(failures),
        "scanned": len(entries),
        "failed": failures,
        "limit": int(limit) if limit.isdigit() else 0,
        "coverage": round(len(entries) / declared_n, 4) if declared_n else 0.0,
        "files_total": files_total,
        "licenses": dict(licenses.most_common(15)),
        "packages": sorted(entries, key=lambda item: item["package"]),
    }
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, sort_keys=True, indent=2)
        handle.write("\n")
    print(
        "%d/%d 包已扫描，%d 个文件，%d 种许可证表达式"
        % (summary["scanned"], summary["declared"], files_total, len(licenses))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
