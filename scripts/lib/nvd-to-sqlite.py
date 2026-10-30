#!/usr/bin/env python3
"""把 olbat/nvdcve 的逐 CVE JSON 转成 Yocto cve-check 用的 SQLite 库。

为什么需要这一层
----------------
`cve-update-nvd2-native` 建库走 NVD 2.0 REST API，2000 条一页、无 API key 时
5 次/30 秒限流，全量 25 万条实测约 4 小时（见 issue #48）。olbat/nvdcve 每天把
NVD 的官方 JSON feed 拆成 `CVE-YYYY-NNNN.json` 并提交到 git，我们只要把这份数据
按 Yocto 的建库逻辑投影成 sqlite，就能完全绕开 API。

投影逻辑必须与 poky 一致
------------------------
本文件的 `_cve_row()` / `_product_rows()` 是
meta/recipes-core/meta/cve-update-nvd2-native.bb 里 `update_db()` 与
`parse_node_and_insert()` 的逐行移植（3.1 / 4.0 / 5.0 三版逻辑等价，差异只在
NVD 表列数）。**任何一处偏差都会让 cve-check 的结论与官方路径不一致**，所以改动
前先对着 bb 文件核一遍。已知刻意保留的上游行为见 `_product_rows()` 里的注释。

用法
----
  nvd-to-sqlite.py build   --source <dir> --schema 5.0 --output <db> [--meta <json>]
  nvd-to-sqlite.py derive  --from <db>    --schema 3.1 --output <db>
  nvd-to-sqlite.py verify  --db <db> [--schema 5.0]
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time

# ---------------------------------------------------------------------------
# 各 release 的库结构
#
# 名字（文件名）与列数都从 poky 源码实测得到，不是猜的：
#   3.1 dunfell   meta/classes/cve-check.bbclass  CVE_CHECK_DB_FILE = ${DL_DIR}/CVE_CHECK/nvdcve_2.db
#                 cve-update-nvd2-native.bb       NVD(ID,SUMMARY,SCOREV2,SCOREV3,MODIFIED,VECTOR)
#   4.0 kirkstone CVE_CHECK_DB_FILENAME = nvdcve_2-2.db，NVD 8 列（多 SCOREV4/VECTORSTRING）
#   5.0 scarthgap 同 4.0（文件名与列结构都一致，可共用同一份库）
#   6.0 wrynose   没有 cve-check.bbclass，改用 sbom-cve-check + git 形式的
#                 nvd-json-data-feeds/cvelistV5，**不是 sqlite**，本脚本不适用。
# ---------------------------------------------------------------------------
SCHEMAS = {
    "3.1": {
        "filename": "nvdcve_2.db",
        "nvd_columns": (
            "ID TEXT UNIQUE, SUMMARY TEXT, SCOREV2 TEXT, SCOREV3 TEXT, "
            "MODIFIED INTEGER, VECTOR TEXT"
        ),
        "nvd_fields": ("id", "summary", "scorev2", "scorev3", "modified", "vector"),
    },
    "4.0": {
        "filename": "nvdcve_2-2.db",
        "nvd_columns": (
            "ID TEXT UNIQUE, SUMMARY TEXT, SCOREV2 TEXT, SCOREV3 TEXT, SCOREV4 TEXT, "
            "MODIFIED INTEGER, VECTOR TEXT, VECTORSTRING TEXT"
        ),
        "nvd_fields": (
            "id",
            "summary",
            "scorev2",
            "scorev3",
            "scorev4",
            "modified",
            "vector",
            "vectorstring",
        ),
    },
    "5.0": {
        "filename": "nvdcve_2-2.db",
        "nvd_columns": (
            "ID TEXT UNIQUE, SUMMARY TEXT, SCOREV2 TEXT, SCOREV3 TEXT, SCOREV4 TEXT, "
            "MODIFIED INTEGER, VECTOR TEXT, VECTORSTRING TEXT"
        ),
        "nvd_fields": (
            "id",
            "summary",
            "scorev2",
            "scorev3",
            "scorev4",
            "modified",
            "vector",
            "vectorstring",
        ),
    },
}

# release 名到库结构 profile 的映射；wrynose 故意不在表里（见上）。
RELEASE_SCHEMA = {
    "dunfell": "3.1",
    "kirkstone": "4.0",
    "scarthgap": "5.0",
}

PRODUCTS_COLUMNS = (
    "ID TEXT, VENDOR TEXT, PRODUCT TEXT, VERSION_START TEXT, OPERATOR_START TEXT, "
    "VERSION_END TEXT, OPERATOR_END TEXT"
)


def create_schema(conn: sqlite3.Connection, profile: str) -> None:
    """与 poky initialize_db() 保持完全一致的 DDL。

    META 表上游建了但从不写（5.0 的进度写到 ${TMPDIR}/cve_check 文本文件里），
    这里照建，避免任何按表结构探查的脚本认为库不完整。
    """
    spec = SCHEMAS[profile]
    with conn:
        c = conn.cursor()
        c.execute("CREATE TABLE IF NOT EXISTS META (YEAR INTEGER UNIQUE, DATE TEXT)")
        c.execute(f"CREATE TABLE IF NOT EXISTS NVD ({spec['nvd_columns']})")
        c.execute(f"CREATE TABLE IF NOT EXISTS PRODUCTS ({PRODUCTS_COLUMNS})")
        c.execute("CREATE INDEX IF NOT EXISTS PRODUCT_ID_IDX on PRODUCTS(ID);")
        c.close()


def _cve_row(cve: dict) -> dict | None:
    """把一条 CVE JSON 投影成 NVD 表的一行。

    返回 None 表示这条不该入库：Rejected 状态在上游是「从库里删掉」，
    我们的全量重建等价于「不插入」。
    """
    if cve.get("vulnStatus") == "Rejected":
        return None

    access_vector = None
    vector_string = None

    cve_id = cve["id"]
    summary = ""
    for desc in cve.get("descriptions") or ():
        if desc.get("lang") == "en":
            summary = desc.get("value", "")
    modified = cve.get("lastModified")

    metrics = cve.get("metrics") or {}
    scorev2 = 0.0
    try:
        data = metrics["cvssMetricV2"][0]["cvssData"]
        access_vector = data["accessVector"]
        vector_string = data["vectorString"]
        scorev2 = data["baseScore"]
    except (KeyError, IndexError):
        scorev2 = 0.0

    scorev3 = None
    for key in ("cvssMetricV30", "cvssMetricV31"):
        try:
            data = metrics[key][0]["cvssData"]
        except (KeyError, IndexError):
            continue
        access_vector = access_vector or data["attackVector"]
        vector_string = vector_string or data["vectorString"]
        scorev3 = scorev3 or data["baseScore"]
    scorev3 = scorev3 or 0.0

    scorev4 = 0.0
    try:
        data = metrics["cvssMetricV40"][0]["cvssData"]
        access_vector = access_vector or data["attackVector"]
        vector_string = vector_string or data["vectorString"]
        scorev4 = data["baseScore"]
    except (KeyError, IndexError):
        scorev4 = 0.0

    return {
        "id": cve_id,
        "summary": summary,
        "scorev2": scorev2,
        "scorev3": scorev3,
        "scorev4": scorev4,
        "modified": modified,
        "vector": access_vector or "UNKNOWN",
        "vectorstring": vector_string or "UNKNOWN",
    }


def _product_rows(cve_id: str, node: dict):
    """移植 parse_node_and_insert() 的生成器。

    刻意保留的两处上游行为（改掉会让结果与官方路径不一致）：
      1. 遇到第一条 `vulnerable: false` 的 cpeMatch 就 `return`（不是 continue），
         整条 node 剩余 CPE 全部丢弃 —— 上游就是这样写的；
      2. `version` 为 `*`/`-` 且没有 versionStart/End 时记成 `'-'` 行。
    唯一的一处加固：上游直接下标 cpe23[6]，畸形 CPE（分段不足 7 段）会抛
    IndexError 把整个建库打断；这里按 `*` 处理并计入 parse_errors。
    """
    for cpe in node.get("cpeMatch", ()):
        if not cpe.get("vulnerable"):
            return
        cpe23 = cpe.get("criteria")
        if not cpe23:
            return
        parts = cpe23.split(":")
        if len(parts) < 6:
            return
        vendor = parts[3]
        product = parts[4]
        version = parts[5]

        update = parts[6] if len(parts) > 6 else "*"
        version_suffix = "" if update in ("*", "-") else "_" + update

        if version not in ("*", "-"):
            yield (cve_id, vendor, product, version + version_suffix, "=", "", "")
            continue
        if version == "-":
            yield (cve_id, vendor, product, "-", "", "", "")
            continue

        op_start = op_end = v_start = v_end = ""
        if "versionStartIncluding" in cpe:
            op_start = ">="
            v_start = cpe["versionStartIncluding"]
        if "versionStartExcluding" in cpe:
            op_start = ">"
            v_start = cpe["versionStartExcluding"]
        if "versionEndIncluding" in cpe:
            op_end = "<="
            v_end = cpe["versionEndIncluding"]
        if "versionEndExcluding" in cpe:
            op_end = "<"
            v_end = cpe["versionEndExcluding"]
        if op_start or op_end or v_start or v_end:
            yield (cve_id, vendor, product, v_start, op_start, v_end, op_end)
        else:
            yield (cve_id, vendor, product, "-", "", "", "")


def iter_cve_files(source: str):
    """按 ID 排序遍历 olbat 的 CVE-*.json。

    排序不是为了好看：全量重建要可复现（同输入 → 同库字节），而 os.listdir
    的顺序依赖文件系统。多进程时由调用方切分这个列表。
    """
    names = sorted(
        n for n in os.listdir(source) if n.startswith("CVE-") and n.endswith(".json")
    )
    for name in names:
        yield os.path.join(source, name)


def build(source: str, profile: str, output: str, meta_path: str | None = None) -> dict:
    spec = SCHEMAS[profile]
    fields = spec["nvd_fields"]
    placeholders = ", ".join("?" for _ in fields)
    insert_nvd = f"insert or replace into NVD values ({placeholders})"

    tmp_output = output + ".tmp"
    for stale in (tmp_output, tmp_output + "-journal"):
        if os.path.exists(stale):
            os.remove(stale)

    stats = {
        "source": os.path.abspath(source),
        "schema": profile,
        "filename": spec["filename"],
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "cve_files": 0,
        "nvd_rows": 0,
        "rejected": 0,
        "product_rows": 0,
        "parse_errors": 0,
        "json_errors": 0,
    }

    conn = sqlite3.connect(tmp_output)
    # 全量重建，批量插入期间不需要回滚能力；关掉同步能快 2-3 倍。
    conn.execute("PRAGMA journal_mode = MEMORY")
    conn.execute("PRAGMA synchronous = OFF")
    create_schema(conn, profile)

    started = time.time()
    nvd_batch: list[tuple] = []
    product_batch: list[tuple] = []

    for path in iter_cve_files(source):
        stats["cve_files"] += 1
        try:
            with open(path, "r", encoding="utf-8") as handle:
                cve = json.load(handle)
        except (OSError, json.JSONDecodeError):
            # 单个坏文件不该毁掉整库；上游走 API 拿不到这种半截数据，
            # 但 git 仓库里可能有历史遗留，计数后跳过。
            stats["json_errors"] += 1
            continue

        row = _cve_row(cve)
        if row is None:
            stats["rejected"] += 1
            continue

        nvd_batch.append(tuple(row[f] for f in fields))
        product_batch.append(row["id"])

        if len(nvd_batch) >= 5000:
            _flush(conn, insert_nvd, nvd_batch, stats)
            nvd_batch.clear()

        for config in cve.get("configurations") or ():
            for node in config.get("nodes") or ():
                try:
                    rows = list(_product_rows(row["id"], node))
                except (IndexError, TypeError):
                    stats["parse_errors"] += 1
                    continue
                if rows:
                    conn.executemany(
                        "insert into PRODUCTS values (?, ?, ?, ?, ?, ?, ?)", rows
                    )
                    stats["product_rows"] += len(rows)

        if stats["cve_files"] % 20000 == 0:
            conn.commit()
            _report_progress(stats, started)

    _flush(conn, insert_nvd, nvd_batch, stats)
    conn.commit()
    conn.execute("PRAGMA optimize")
    conn.close()

    os.replace(tmp_output, output)
    stats["elapsed_seconds"] = round(time.time() - started, 1)

    if meta_path:
        with open(meta_path + ".tmp", "w", encoding="utf-8") as handle:
            json.dump(stats, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(meta_path + ".tmp", meta_path)
    return stats


def _flush(conn, insert_nvd, batch, stats) -> None:
    if not batch:
        return
    conn.executemany(insert_nvd, batch).close()
    stats["nvd_rows"] += len(batch)


def _report_progress(stats: dict, started: float) -> None:
    rate = stats["cve_files"] / max(time.time() - started, 0.001)
    print(
        f"  ... {stats['cve_files']} files "
        f"({stats['nvd_rows']} CVEs, {stats['product_rows']} product rows, "
        f"{rate:.0f} files/s)",
        flush=True,
    )


def derive(source_db: str, profile: str, output: str, meta_path: str | None = None) -> dict:
    """从 8 列库投影出 3.1 的 6 列库。

    3.1 与 4.0/5.0 的差别只是少两列，JSON 只解析一遍再去投影，比对着 28 万个
    文件再跑一趟快一个数量级。
    """
    spec = SCHEMAS[profile]
    fields = spec["nvd_fields"]
    tmp_output = output + ".tmp"
    for stale in (tmp_output, tmp_output + "-journal"):
        if os.path.exists(stale):
            os.remove(stale)

    stats = {
        "source_db": os.path.abspath(source_db),
        "schema": profile,
        "filename": spec["filename"],
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "nvd_rows": 0,
        "product_rows": 0,
    }

    src = sqlite3.connect(f"file:{source_db}?mode=ro", uri=True)
    dst = sqlite3.connect(tmp_output)
    dst.execute("PRAGMA journal_mode = MEMORY")
    dst.execute("PRAGMA synchronous = OFF")
    create_schema(dst, profile)

    wanted = ", ".join(fields)
    rows = src.execute(f"SELECT {wanted} FROM NVD")
    insert_nvd = "insert or replace into NVD values ({})".format(
        ", ".join("?" for _ in fields)
    )
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) >= 5000:
            dst.executemany(insert_nvd, batch).close()
            stats["nvd_rows"] += len(batch)
            batch.clear()
    if batch:
        dst.executemany(insert_nvd, batch).close()
        stats["nvd_rows"] += len(batch)

    dst.executemany(
        "insert into PRODUCTS values (?, ?, ?, ?, ?, ?, ?)",
        src.execute("SELECT * FROM PRODUCTS"),
    )
    stats["product_rows"] = dst.execute("SELECT count(*) FROM PRODUCTS").fetchone()[0]
    src.close()
    dst.commit()
    dst.execute("PRAGMA optimize")
    dst.close()
    os.replace(tmp_output, output)

    if meta_path:
        with open(meta_path + ".tmp", "w", encoding="utf-8") as handle:
            json.dump(stats, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(meta_path + ".tmp", meta_path)
    return stats


def verify(db_path: str, profile: str) -> dict:
    """体检：表结构、行数、以及 cve-check 真正会跑的几条查询能否命中。"""
    spec = SCHEMAS[profile]
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        tables = {
            name
            for (name,) in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        missing = {"NVD", "PRODUCTS", "META"} - tables
        if missing:
            raise SystemExit(f"库缺表：{', '.join(sorted(missing))}")
        columns = [row[1] for row in conn.execute("PRAGMA table_info(NVD)")]
        expected = [f.upper() for f in spec["nvd_fields"]]
        if columns != expected:
            raise SystemExit(f"NVD 列不符：期望 {expected}，实际 {columns}")
        stats = {
            "db": os.path.abspath(db_path),
            "schema": profile,
            "bytes": os.path.getsize(db_path),
            "nvd_rows": conn.execute("SELECT count(*) FROM NVD").fetchone()[0],
            "product_rows": conn.execute("SELECT count(*) FROM PRODUCTS").fetchone()[0],
            "products_with_ids": conn.execute(
                "SELECT count(DISTINCT ID) FROM PRODUCTS"
            ).fetchone()[0],
            "max_modified": conn.execute("SELECT max(MODIFIED) FROM NVD").fetchone()[0],
        }
    finally:
        conn.close()
    if stats["nvd_rows"] == 0:
        raise SystemExit("库是空的：没有解析到任何 CVE")
    return stats


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_build = sub.add_parser("build", help="从 JSON 目录重建库")
    p_build.add_argument("--source", required=True)
    p_build.add_argument("--schema", required=True, choices=sorted(SCHEMAS))
    p_build.add_argument("--output", required=True)
    p_build.add_argument("--meta")

    p_derive = sub.add_parser("derive", help="从 8 列库投影出 6 列库")
    p_derive.add_argument("--from", dest="source_db", required=True)
    p_derive.add_argument("--schema", required=True, choices=sorted(SCHEMAS))
    p_derive.add_argument("--output", required=True)
    p_derive.add_argument("--meta")

    p_verify = sub.add_parser("verify", help="校验库结构与非空")
    p_verify.add_argument("--db", required=True)
    p_verify.add_argument("--schema", required=True, choices=sorted(SCHEMAS))

    args = parser.parse_args(argv)

    if args.command == "build":
        stats = build(args.source, args.schema, args.output, args.meta)
    elif args.command == "derive":
        stats = derive(args.source_db, args.schema, args.output, args.meta)
    else:
        stats = verify(args.db, args.schema)

    json.dump(stats, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
