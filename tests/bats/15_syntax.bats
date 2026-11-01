#!/usr/bin/env bats

setup() {
    ROOT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    MATRIX="${ROOT_DIR}/docs/syntax-matrix.md"
}

# bats test_tags=syntax
@test "syntax matrix has at least ten six-column data rows for all releases" {
    [ -f "${MATRIX}" ]
    run python3 - "${MATRIX}" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
table = []
for line in lines:
    if line.startswith("|"):
        table.append(line)
    elif table:
        break

assert table, "matrix table is missing"
header = table[0]
for release in ("dunfell", "kirkstone", "scarthgap", "wrynose"):
    assert release in header, f"missing release column: {release}"

data_rows = []
for line in table[1:]:
    cells = [cell.strip() for cell in line.strip("|").split("|")]
    if all(cell and set(cell) <= {"-", ":"} for cell in cells):
        continue
    assert len(cells) == 6, f"expected six columns in row: {line}"
    data_rows.append(cells)

assert len(data_rows) >= 10, f"expected at least ten data rows, got {len(data_rows)}"
PY
    [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
}

# bats test_tags=syntax
@test "wrynose YP init row specifies systemd" {
    run python3 - "${MATRIX}" <<'PY'
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("|"):
        cells = [cell.strip() for cell in line.strip().split("|")[1:-1]]
        if cells and cells[0] == "默认 init（YP 实际）":
            assert "systemd" in cells[4], f"wrynose column is not systemd: {cells[4]}"
            break
else:
    raise AssertionError("matrix row 默认 init（YP 实际） is missing")
PY
    [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
}

# bats test_tags=syntax
@test "demo recipes go through YP_SRC_DIR for their source root" {
    local recipes_dir="${ROOT_DIR}/layers/meta-yp/recipes-demo"
    # #64~#70 尚未合并时目录不存在；合并后此检查会自动生效。
    [ -d "${recipes_dir}" ] || return 0

    # 断言的是 ${YP_SRC_DIR} 而不是 ${UNPACKDIR}：后者 6.0 才引入，
    # 3.1~5.0 上写它 S 就停在字面量（解析不报错，do_unpack 才炸）。
    # YP_SRC_DIR 在 yp-service.bbclass 里定义为 `${UNPACKDIR} or ${WORKDIR}`，
    # 是四版唯一正确的入口。
    local recipe
    for recipe in "${recipes_dir}"/*/*.bb; do
        [ -f "${recipe}" ] || continue
        run python3 - "${recipe}" <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
assignments = [line for line in lines if re.match(r"^\s*S\s*=", line)]
expected = re.compile(r'^\s*S\s*=\s*"\$\{YP_SRC_DIR\}"\s*$')
assert assignments and all(expected.match(line) for line in assignments), (
    f"{sys.argv[1]} must set every S assignment to ${{YP_SRC_DIR}}; "
    f"found: {assignments}"
)
PY
        [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
    done
}

# bats test_tags=syntax
@test "YP source directory retains the pre-UNPACKDIR fallback" {
    local bbclass="${ROOT_DIR}/layers/meta-yp/classes/yp-service.bbclass"
    [ -f "${bbclass}" ]
    run grep -Fq "d.getVar('UNPACKDIR') or d.getVar('WORKDIR')" "${bbclass}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=syntax
@test "YP distro selects systemd" {
    run grep -q '^INIT_MANAGER = "systemd"$' "${ROOT_DIR}/layers/meta-yp/conf/distro/yp.conf"
    [ "${status}" -eq 0 ]
}
