#!/usr/bin/env bats
# 合规证据采集与归档（issue #26）。
# 只验证脚本契约、路径规则与渲染逻辑；真采集靠 scripts/compliance.sh 在 215 上跑
# （6.0 的 CVE 需要 4 GB 的 nvd-fkie 库，FOSS 需要 ScanCode 与容器）。

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    mkdir -p "${ROOT_DIR}/work"
    test_root="$(mktemp -d "${ROOT_DIR}/work/compliance-test.XXXXXX")"
    compliance_json="${test_root}/compliance.json"
    compliance_archive="${test_root}/compliance.md"
}

teardown() {
    if [[ -n "${test_root:-}" ]]; then
        rm -rf -- "${test_root}"
    fi
}

write_compliance_json() {
    local sbom="${1:-true}" cve="${2:-true}" foss="${3:-true}"
    cat >"${compliance_json}" <<JSON
{
  "release": "wrynose",
  "variant": "custom",
  "machine": "qemux86-64",
  "tag": "yocto-6.0.4",
  "commit": "abcdef1",
  "date": "20260101",
  "sbom": {
    "available": ${sbom},
    "format": "SPDX-3.0.1",
    "path": "work/kas-wrynose-custom/build/tmp/deploy/images/qemux86-64/yp-image-qemux86-64.rootfs.spdx.json",
    "packaging": "single-json",
    "bytes": 6737823,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "packages": 574,
    "files": 5123,
    "purl_nonempty": 500,
    "purl_ratio": 0.8711,
    "licenses": {"MIT": 12, "GPL-2.0-only": 40},
    "vex": {"fixed": 144, "not_affected": 58, "known_affected": 0, "vulnerability": 202}
  },
  "cve": {
    "available": ${cve},
    "source": "sbom-cve-check",
    "manifest": "work/artifacts/wrynose/custom/cve/yocto-cve-check-manifest.json",
    "packages": 102,
    "db": "nvd-json-data-feeds (nvd-fkie)",
    "db_revision": "e2b1ac0",
    "db_date": "2026-10-30T12:00:00+08:00",
    "unpatched": 318,
    "patched": 16968,
    "ignored": 41
  },
  "foss": {
    "available": ${foss},
    "declared": 183,
    "selected": 20,
    "scanned": 19,
    "failed": ["zlib"],
    "limit": 20,
    "coverage": 0.1038,
    "files_total": 4321,
    "licenses": {"MIT": 120, "GPL-2.0-only": 88},
    "artifacts": "work/artifacts/wrynose/custom/foss",
    "tool": "scancode-toolkit",
    "source": "work/downloads",
    "packages": [
      {"package": "acl", "archive": "work/downloads/acl-2.3.1.tar.gz",
       "files": 210, "clarity": 90, "licenses": {"GPL-2.0-or-later": 12}}
    ]
  }
}
JSON
}

# bats test_tags=compliance
@test "compliance.sh 校验必填参数与 --only 取值" {
    run bash "${ROOT_DIR}/scripts/compliance.sh"
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/compliance.sh" --release wrynose --only bogus
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"--only"* ]]
    run bash "${ROOT_DIR}/scripts/compliance.sh" --release wrynose --foss-limit abc
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/compliance.sh" --release nope
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"配置不存在"* ]]
}

# bats test_tags=compliance
@test "compliance.sh --print-sbom 缺产物时指向 --spdx 构建" {
    # 必须用隔离目录：215 上 work/ 里真有 wrynose 的 SBOM，直接用默认路径会命中
    run env YP_DEPLOY_DIR="${test_root}/no-deploy" YP_ARTIFACT_DIR="${test_root}/no-art" \
        bash "${ROOT_DIR}/scripts/compliance.sh" --print-sbom --release wrynose --variant custom
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"--spdx"* ]]
}

# bats test_tags=compliance
@test "compliance.sh status 在未采集时报缺失而不是失败" {
    run env YP_ARTIFACT_DIR="${test_root}/no-art" \
        bash "${ROOT_DIR}/scripts/compliance.sh" status --release wrynose --variant custom
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"compliance.json"* ]]
    [[ "${output}" == *"缺失"* ]]
}

# bats test_tags=compliance
@test "report.sh --compliance 缺 compliance.json 时给出可执行的下一步" {
    run env YP_COMPLIANCE_JSON="${test_root}/missing.json" \
        bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant custom --compliance
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"scripts/compliance.sh"* ]]
}

# bats test_tags=compliance
@test "report.sh --compliance 出五节归档并判 PASS" {
    write_compliance_json
    run env YP_COMPLIANCE_JSON="${compliance_json}" YP_COMPLIANCE_ARCHIVE="${compliance_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant custom --compliance
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"PASS"* ]]
    run grep -F '## SBOM' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '## CVE' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '## FOSS' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '## 格式差异' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '## 降级清单' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '**PASS' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    # 关键数字都要出现在归档里，否则等于只渲染了骨架
    run grep -F '318 / 16968 / 41' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '10.4%' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '87.1%' "${compliance_archive}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=compliance
@test "report.sh --compliance 对 6.0 写 sbom-cve-check 而不是“不适用”" {
    write_compliance_json
    run env YP_COMPLIANCE_JSON="${compliance_json}" YP_COMPLIANCE_ARCHIVE="${compliance_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant custom --compliance
    [ "${status}" -eq 0 ]
    run grep -F 'sbom-cve-check' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F -- '--offline-mode' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    # 6.0 不能再出现「不适用」这种 2026-10 之前的结论
    run grep -F '6.0 不适用' "${compliance_archive}"
    [ "${status}" -ne 0 ]
}

# bats test_tags=compliance
@test "report.sh --compliance 有节缺失时判 FAIL 并返回非零" {
    write_compliance_json true false true
    run env YP_COMPLIANCE_JSON="${compliance_json}" YP_COMPLIANCE_ARCHIVE="${compliance_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant custom --compliance
    [ "${status}" -ne 0 ]
    run grep -F '**FAIL' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '未产出' "${compliance_archive}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=compliance
@test "report.sh --compliance 拒绝 all" {
    run bash "${ROOT_DIR}/scripts/report.sh" --release all --compliance
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"--compliance 不支持 all"* ]]
}

# bats test_tags=compliance
@test "sbom-stats.py 同时认 SPDX 2.2 与 3.0.1" {
    local spdx22="${test_root}/doc22.spdx.json" spdx30="${test_root}/doc30.spdx.json"
    cat >"${spdx22}" <<'JSON'
{
  "spdxVersion": "SPDX-2.2",
  "name": "yp-image-qemux86-64.rootfs",
  "packages": [
    {"name": "acl", "licenseDeclared": "GPL-2.0-or-later",
     "externalRefs": [{"referenceType": "purl", "referenceLocator": "pkg:generic/acl@2.3.1"}]},
    {"name": "zlib", "licenseDeclared": "Zlib", "externalRefs": []}
  ],
  "files": [{}, {}, {}]
}
JSON
    cat >"${spdx30}" <<'JSON'
{
  "@context": "https://spdx.org/rdf/3.0.1/spdx-context.jsonld",
  "@graph": [
    {"type": "CreationInfo", "specVersion": "3.0.1"},
    {"type": "SpdxDocument", "spdxId": "doc"},
    {"type": "software_Sbom", "name": "yp-image"},
    {"type": "software_Package", "name": "acl", "software_packageUrl": "pkg:generic/acl@2.3.1"},
    {"type": "software_Package", "name": "zlib"},
    {"type": "software_File"}, {"type": "software_File"},
    {"type": "simplelicensing_LicenseExpression", "simplelicensing_licenseExpression": "MIT"},
    {"type": "security_VexFixedVulnAssessmentRelationship"},
    {"type": "security_Vulnerability"}
  ]
}
JSON
    run python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${spdx22}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"format": "SPDX-2.2"'* ]]
    [[ "${output}" == *'"packages": 2'* ]]
    [[ "${output}" == *'"files": 3'* ]]
    [[ "${output}" == *'"purl_ratio": 0.5'* ]]

    run python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${spdx30}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"format": "SPDX-3.0.1"'* ]]
    [[ "${output}" == *'"packages": 2'* ]]
    [[ "${output}" == *'"files": 2'* ]]
    [[ "${output}" == *'"fixed": 1'* ]]
}

# bats test_tags=compliance
@test "sbom-stats.py 对无法识别的文档返回非零" {
    local bogus="${test_root}/bogus.json"
    printf '{"name": "nothing"}\n' >"${bogus}"
    run python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${bogus}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"无法识别"* ]]
}

# bats test_tags=compliance
@test "foss-summary.py 按实际产出的 json 记账，失败包不进成功率" {
    local results="${test_root}/foss" input="${test_root}/input.tsv" out="${test_root}/summary.json"
    mkdir -p "${results}"
    printf 'acl\twork/downloads/acl-2.3.1.tar.gz\nzlib\twork/downloads/zlib-1.3.1.tar.gz\n' >"${input}"
    cat >"${results}/acl.json" <<'JSON'
{
  "files": [{}, {}],
  "license_detections": [{"license_expression": "GPL-2.0-or-later"}],
  "summary": {"license_clarity_score": {"score": 90}}
}
JSON
    run python3 "${ROOT_DIR}/scripts/lib/foss-summary.py" "${results}" "${input}" "${out}" 4 20
    [ "${status}" -eq 0 ]
    run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["scanned"]==1; assert d["selected"]==2; assert d["failed"]==["zlib"]; assert d["declared"]==4; assert d["coverage"]==0.25; print("ok")' "${out}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "ok" ]
}
