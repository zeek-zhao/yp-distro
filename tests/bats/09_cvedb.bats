#!/usr/bin/env bats
# olbat/nvdcve → Yocto cve-check 库的离线构建链路（issue #48）。
# 全部用例只碰 tests/fixtures/nvd 里的 5 条样本，不联网、不依赖真实构建。

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    mkdir -p "${ROOT_DIR}/work"
    test_root="$(mktemp -d "${ROOT_DIR}/work/cvedb-test.XXXXXX")"
    converter="${ROOT_DIR}/scripts/lib/nvd-to-sqlite.py"
    fixtures="${ROOT_DIR}/tests/fixtures/nvd"
}

teardown() {
    if [[ -n "${test_root:-}" ]]; then
        rm -rf -- "${test_root}"
    fi
}

# cve-check 真正会读的列，各 release 不同（见 nvd-to-sqlite.py 的 SCHEMAS）。
nvd_columns() {
    python3 - "$1" <<'PY'
import sqlite3, sys
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
print(",".join(row[1] for row in conn.execute("PRAGMA table_info(NVD)")))
PY
}

scalar() {
    local db="$1" sql="$2"
    python3 - "$db" "$sql" <<'PY'
import sqlite3, sys
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
row = conn.execute(sys.argv[2]).fetchone()
print("" if row is None or row[0] is None else row[0])
PY
}

# bats test_tags=cvedb
@test "build 5.0 产出 cve-check 认的 8 列库，并丢弃 Rejected" {
    run python3 "${converter}" build --source "${fixtures}" --schema 5.0 \
        --output "${test_root}/nvdcve_2-2.db" \
        --meta "${test_root}/nvdcve_2-2.db.meta.json"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"rejected": 1'* ]]
    [[ "${output}" == *'"nvd_rows": 4'* ]]
    [ "$(nvd_columns "${test_root}/nvdcve_2-2.db")" = \
        "ID,SUMMARY,SCOREV2,SCOREV3,SCOREV4,MODIFIED,VECTOR,VECTORSTRING" ]
    # Rejected 的 CVE 在上游是「从库里删掉」，全量重建等价于不插入。
    [ "$(scalar "${test_root}/nvdcve_2-2.db" "select count(*) from NVD where ID='CVE-2023-0003'")" = "0" ]
    [ -f "${test_root}/nvdcve_2-2.db.meta.json" ]
}

# bats test_tags=cvedb
@test "build 3.1 产出 6 列库（没有 SCOREV4/VECTORSTRING）" {
    run python3 "${converter}" build --source "${fixtures}" --schema 3.1 \
        --output "${test_root}/nvdcve_2.db"
    [ "${status}" -eq 0 ]
    [ "$(nvd_columns "${test_root}/nvdcve_2.db")" = \
        "ID,SUMMARY,SCOREV2,SCOREV3,MODIFIED,VECTOR" ]
}

# bats test_tags=cvedb
@test "derive 从 8 列库投影出的 3.1 库与直接 build 等价" {
    python3 "${converter}" build --source "${fixtures}" --schema 5.0 \
        --output "${test_root}/full.db" >/dev/null
    python3 "${converter}" build --source "${fixtures}" --schema 3.1 \
        --output "${test_root}/direct.db" >/dev/null
    run python3 "${converter}" derive --from "${test_root}/full.db" \
        --schema 3.1 --output "${test_root}/derived.db"
    [ "${status}" -eq 0 ]

    dump_sql() {
        python3 - "$1" <<'PY'
import sqlite3, sys
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
for table in ("NVD", "PRODUCTS"):
    for row in conn.execute("select * from %s order by 1, 3" % table):
        print(table, row)
PY
    }
    [ "$(dump_sql "${test_root}/direct.db")" = "$(dump_sql "${test_root}/derived.db")" ]
}

# bats test_tags=cvedb
@test "PRODUCTS 表保住 cve-check 匹配所需的版本区间语义" {
    python3 "${converter}" build --source "${fixtures}" --schema 5.0 \
        --output "${test_root}/db.db" >/dev/null

    # 区间型
    [ "$(scalar "${test_root}/db.db" "select VERSION_START||' '||OPERATOR_START||' '||VERSION_END||' '||OPERATOR_END from PRODUCTS where ID='CVE-2021-0001'")" = "1.0 >= 2.0 <" ]
    # 精确版本
    [ "$(scalar "${test_root}/db.db" "select VERSION_START||OPERATOR_START from PRODUCTS where ID='CVE-2022-0002'")" = "3.1.4=" ]
    # update 段要拼进版本号（cpe:2.3:a:acme:tool:2.3:sp1 → 2.3_sp1）
    [ "$(scalar "${test_root}/db.db" "select VERSION_START from PRODUCTS where ID='CVE-2025-0005' and PRODUCT='tool'")" = "2.3_sp1" ]
    # 版本未知
    [ "$(scalar "${test_root}/db.db" "select VERSION_START from PRODUCTS where ID='CVE-2025-0005' and PRODUCT='helper'")" = "-" ]
}

# bats test_tags=cvedb
@test "node 里首条 cpeMatch 不是 vulnerable 时整条 node 不入 PRODUCTS（对齐上游 return）" {
    python3 "${converter}" build --source "${fixtures}" --schema 5.0 \
        --output "${test_root}/db.db" >/dev/null
    # CVE-2024-0004 的第二条 CPE 是 vulnerable=true，但上游 parse_node_and_insert
    # 遇到第一条 vulnerable=false 就 return，所以一条都不该有。
    [ "$(scalar "${test_root}/db.db" "select count(*) from PRODUCTS where ID='CVE-2024-0004'")" = "0" ]
    # CVE 本体仍在 NVD 表里（cve-check 还要用它判断“有没有 CVE”）。
    [ "$(scalar "${test_root}/db.db" "select SCOREV3 from NVD where ID='CVE-2024-0004'")" = "3.8" ]
}

# bats test_tags=cvedb
@test "verify 拒绝列结构不匹配的库" {
    python3 "${converter}" build --source "${fixtures}" --schema 3.1 \
        --output "${test_root}/six.db" >/dev/null
    run python3 "${converter}" verify --db "${test_root}/six.db" --schema 5.0
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"NVD 列不符"* ]]
}

# bats test_tags=cvedb
@test "verify 拒绝空库" {
    python3 - "${test_root}/empty.db" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE META (YEAR INTEGER UNIQUE, DATE TEXT)")
conn.execute("CREATE TABLE NVD (ID TEXT UNIQUE, SUMMARY TEXT, SCOREV2 TEXT, SCOREV3 TEXT, SCOREV4 TEXT, MODIFIED INTEGER, VECTOR TEXT, VECTORSTRING TEXT)")
conn.execute("CREATE TABLE PRODUCTS (ID TEXT, VENDOR TEXT, PRODUCT TEXT, VERSION_START TEXT, OPERATOR_START TEXT, VERSION_END TEXT, OPERATOR_END TEXT)")
conn.commit()
PY
    run python3 "${converter}" verify --db "${test_root}/empty.db" --schema 5.0
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"库是空的"* ]]
}

# bats test_tags=cvedb
@test "cve-db.sh 的 status 明确指出 wrynose 不适用" {
    run bash "${ROOT_DIR}/scripts/cve-db.sh" status
    [ "${status}" -eq 0 ]
    [[ "${output}" == *wrynose* ]]
    [[ "${output}" == *"sbom-cve-check"* ]]
}

# bats test_tags=cvedb
@test "cve-db.sh 拒绝 wrynose 建库" {
    run bash "${ROOT_DIR}/scripts/cve-db.sh" build --release wrynose
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"不支持的 release"* ]]
}

# bats test_tags=cvedb
@test "kas 基线把 CVE 库固定成离线模式" {
    # CVE_DB_UPDATE_INTERVAL=-1 让 cve-update-nvd2-native 永不联网：
    # 库由 scripts/cve-db.sh 预置。去掉这行就会退回“首次建库 4 小时”（#48）。
    grep -Eq '^[[:space:]]*CVE_DB_UPDATE_INTERVAL = "-1"' "${ROOT_DIR}/kas/base.yml"
}
