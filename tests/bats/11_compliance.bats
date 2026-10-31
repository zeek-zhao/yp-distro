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
@test "report.sh --compliance 索引型 SBOM 用聚合口径而不是「1 包」" {
    local index_json="${test_root}/compliance-index.json"
    cat >"${index_json}" <<'JSON'
{
  "release": "kirkstone",
  "variant": "custom",
  "machine": "qemux86-64",
  "tag": "yocto-4.0.35",
  "commit": "abcdef1",
  "date": "20260101",
  "sbom": {
    "available": true,
    "format": "SPDX-2.2",
    "spec_version": "SPDX-2.2",
    "kind": "spdx2-index",
    "path": "work/artifacts/kirkstone/custom/sbom/yp-image-qemux86-64.spdx.json",
    "packaging": "single-json",
    "bytes": 153738,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "packages": 1,
    "files": 0,
    "external_documents": 334,
    "components": 167,
    "purl_nonempty": 0,
    "purl_ratio": 0.0,
    "licenses": {"NOASSERTION": 1},
    "vex": null,
    "aggregate": {
      "documents": 167,
      "resolved_by_name": 0,
      "missing": [],
      "missing_count": 0,
      "packages": 167,
      "files": 1204,
      "purl_nonempty": 0,
      "purl_ratio": 0.0,
      "licenses": {"GPL-2.0-only": 40, "MIT": 12}
    }
  },
  "cve": {"available": true, "source": "cve-check", "packages": 65,
          "unpatched": 2862, "patched": 11097, "ignored": 2737, "db": "sqlite"},
  "foss": {"available": true, "declared": 167, "selected": 10, "scanned": 9,
           "limit": 10, "coverage": 0.0539, "files_total": 20000,
           "artifacts": "work/artifacts/kirkstone/custom/foss",
           "tool": "scancode-toolkit", "source": "work/downloads",
           "packages": []}
}
JSON
    run env YP_COMPLIANCE_JSON="${index_json}" YP_COMPLIANCE_ARCHIVE="${compliance_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release kirkstone --variant custom --compliance
    [ "${status}" -eq 0 ]
    report_output="${output}"
    run grep -F '索引型' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '镜像组件（CONTAINS 对位）' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '聚合包元素' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    # 分母必须是聚合包数，不能是文档里的 1
    run grep -F '0.0%（0/167）' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    # 摘要行同样不能只剩「1 包」
    [[ "${report_output}" != *"SPDX-2.2 1 包"* ]]
    [[ "${report_output}" == *"索引型 167 组件"* ]]
}

# bats test_tags=compliance
@test "report.sh --compliance 索引型对位不全时判 FAIL" {
    local index_json="${test_root}/compliance-index-miss.json"
    cat >"${index_json}" <<'JSON'
{
  "release": "scarthgap",
  "variant": "custom",
  "machine": "qemux86-64",
  "tag": "yocto-5.0.20",
  "commit": "abcdef1",
  "date": "20260101",
  "sbom": {
    "available": true,
    "format": "SPDX-2.2",
    "kind": "spdx2-index",
    "path": "work/artifacts/scarthgap/custom/sbom/yp-image.spdx.json",
    "packaging": "tar.zst",
    "bytes": 171488,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "packages": 1,
    "files": 0,
    "external_documents": 366,
    "components": 183,
    "purl_nonempty": 0,
    "purl_ratio": 0.0,
    "licenses": {"NOASSERTION": 1},
    "vex": null,
    "aggregate": {"documents": 171, "resolved_by_name": 0, "missing": ["base-files"],
                  "missing_count": 12, "packages": 171, "files": 900,
                  "purl_nonempty": 0, "purl_ratio": 0.0, "licenses": {}}
  },
  "cve": {"available": true, "source": "cve-check", "packages": 70,
          "unpatched": 1, "patched": 2, "ignored": 3, "db": "sqlite"},
  "foss": {"available": true, "declared": 183, "selected": 10, "scanned": 10,
           "limit": 10, "coverage": 0.0546, "files_total": 28000,
           "artifacts": "work/artifacts/scarthgap/custom/foss",
           "tool": "scancode-toolkit", "source": "work/downloads", "packages": []}
}
JSON
    run env YP_COMPLIANCE_JSON="${index_json}" YP_COMPLIANCE_ARCHIVE="${compliance_archive}" \
        bash "${ROOT_DIR}/scripts/report.sh" --release scarthgap --variant custom --compliance
    [ "${status}" -ne 0 ]
    run grep -F '**FAIL' "${compliance_archive}"
    [ "${status}" -eq 0 ]
    run grep -F '缺 12 份' "${compliance_archive}"
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
@test "sbom-stats.py 认索引型文档并按 documentNamespace 对位聚合" {
    # 3.1/4.0/5.0 的镜像文档只有 1 个 image 包，组件靠 externalDocumentRefs 指出去。
    # 这里故意放一份 zlib-dbg（文件名前缀能猜中但命名空间对不上）来锁死「不能按
    # 文件名猜」这条：猜的话会把 zlib 记成已解析，实际它没有对应文档。
    local dir="${test_root}/spdx/qemux86-64/packages" index="${test_root}/index.spdx.json"
    mkdir -p "${dir}"
    cat >"${dir}/acl.spdx.json" <<'JSON'
{
  "spdxVersion": "SPDX-2.2",
  "name": "acl",
  "documentNamespace": "http://spdx.org/spdxdoc/acl-1111",
  "packages": [
    {"name": "acl", "licenseDeclared": "GPL-2.0-or-later",
     "externalRefs": [{"referenceType": "purl", "referenceLocator": "pkg:generic/acl@2.3.1"}]}
  ],
  "files": [{}, {}]
}
JSON
    cat >"${dir}/zlib-dbg.spdx.json" <<'JSON'
{
  "spdxVersion": "SPDX-2.2",
  "name": "zlib-dbg",
  "documentNamespace": "http://spdx.org/spdxdoc/zlib-dbg-9999",
  "packages": [{"name": "zlib-dbg", "licenseDeclared": "Zlib"}],
  "files": []
}
JSON
    cat >"${index}" <<'JSON'
{
  "spdxVersion": "SPDX-2.2",
  "name": "yp-image-qemux86-64-20260101",
  "packages": [{"name": "yp-image"}],
  "externalDocumentRefs": [
    {"externalDocumentId": "DocumentRef-acl", "spdxDocument": "http://spdx.org/spdxdoc/acl-1111"},
    {"externalDocumentId": "DocumentRef-zlib", "spdxDocument": "http://spdx.org/spdxdoc/zlib-2222"}
  ],
  "relationships": [
    {"relationshipType": "CONTAINS",
     "relatedSpdxElement": "DocumentRef-acl:SPDXRef-Package-acl"},
    {"relationshipType": "CONTAINS",
     "relatedSpdxElement": "DocumentRef-zlib:SPDXRef-Package-zlib"},
    {"relationshipType": "GENERATED_FROM",
     "relatedSpdxElement": "DocumentRef-acl:SPDXRef-Package-acl"}
  ],
  "files": []
}
JSON
    run python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${index}" --spdx-dir "${test_root}/spdx"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"kind": "spdx2-index"'* ]]
    # 只数 CONTAINS，GENERATED_FROM 那种重复引用不算组件
    [[ "${output}" == *'"components": 2'* ]]
    [[ "${output}" == *'"external_documents": 2'* ]]
    [[ "${output}" == *'"documents": 1'* ]]
    [[ "${output}" == *'"packages": 1'* ]]
    [[ "${output}" == *'"missing_count": 1'* ]]
    [[ "${output}" == *'"zlib"'* ]]
    [[ "${output}" == *'"purl_ratio": 1.0'* ]]
}

# bats test_tags=compliance
@test "sbom-stats.py 不传 --spdx-dir 时索引型只报形态不聚合" {
    local index="${test_root}/index.spdx.json"
    cat >"${index}" <<'JSON'
{
  "spdxVersion": "SPDX-2.2",
  "name": "yp-image",
  "packages": [{"name": "yp-image"}],
  "externalDocumentRefs": [
    {"externalDocumentId": "DocumentRef-acl", "spdxDocument": "http://spdx.org/spdxdoc/acl-1111"}
  ],
  "relationships": [
    {"relationshipType": "CONTAINS", "relatedSpdxElement": "DocumentRef-acl:SPDXRef-Package-acl"}
  ]
}
JSON
    run python3 "${ROOT_DIR}/scripts/lib/sbom-stats.py" "${index}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *'"kind": "spdx2-index"'* ]]
    [[ "${output}" == *'"components": 1'* ]]
    [[ "${output}" != *'"aggregate"'* ]]
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
