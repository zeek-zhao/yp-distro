#!/usr/bin/env bats

# bats test_tags=report

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    # shellcheck source=../../scripts/lib/artifacts.sh
    source "${ROOT_DIR}/scripts/lib/artifacts.sh"
}

@test "report script help exits successfully" {
    run "${ROOT_DIR}/scripts/report.sh" --help
    [ "${status}" -eq 0 ]
}

# bats test_tags=report
@test "report CLI accepts positional and --release forms equivalently" {
    run "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant general --render-only
    [ "${status}" -eq 0 ]
    option_archive="${output##*Archive: }"

    run "${ROOT_DIR}/scripts/report.sh" wrynose --variant general --render-only
    [ "${status}" -eq 0 ]
    positional_archive="${output##*Archive: }"
    [ "${option_archive}" = "${positional_archive}" ]
}

# bats test_tags=report
@test "artifact primary prefers ext4 and list excludes manifests" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy"
    mkdir -p "${deploy_dir}"
    touch "${deploy_dir}/core-image-qemux86-64.rootfs.ext4"
    touch "${deploy_dir}/core-image-qemux86-64.rootfs.tar.bz2"
    touch "${deploy_dir}/core-image-qemux86-64.rootfs.manifest"

    run artifact_primary "${deploy_dir}" core-image qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == /* ]]
    [[ "${output}" == *".rootfs.ext4" ]]
    run artifact_list "${deploy_dir}" core-image qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == /* ]]
    [[ "${output}" == *".rootfs.ext4"* ]]
    [[ "${output}" == *".rootfs.tar.bz2"* ]]
    [[ "${output}" != *".manifest" ]]
}

# bats test_tags=report
@test "artifact primary prefers zstd ext4 and list keeps zstd tarballs" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-zst"
    mkdir -p "${deploy_dir}"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.tar.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.manifest"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst" ]]

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst"* ]]
    [[ "${output}" == *".rootfs.tar.zst"* ]]
    [[ "${output}" != *".manifest" ]]
}

# bats test_tags=report
@test "artifact primary fails when no image exists" {
    mkdir -p "${BATS_TEST_TMPDIR}/empty"
    run artifact_primary "${BATS_TEST_TMPDIR}/empty" core-image qemux86-64
    [ "${status}" -ne 0 ]
    run artifact_list "${BATS_TEST_TMPDIR}/missing" core-image qemux86-64
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

# bats test_tags=report
@test "artifact sha256 matches a known digest" {
    printf 'hello' >"${BATS_TEST_TMPDIR}/hello"
    run artifact_sha256 "${BATS_TEST_TMPDIR}/hello"
    [ "${status}" -eq 0 ]
    [ "${output}" = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" ]
}

# bats test_tags=report
@test "artifact bytes follows symlinks in deploy dir" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-link"
    mkdir -p "${deploy_dir}"
    head -c 4096 /dev/zero >"${deploy_dir}/core-image-minimal-qemux86-64.rootfs-1.ext4.zst"
    ln -s core-image-minimal-qemux86-64.rootfs-1.ext4.zst \
        "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    run artifact_bytes "${output}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "4096" ]
}

# bats test_tags=report
@test "artifact list excludes qemuboot.conf" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-qb"
    mkdir -p "${deploy_dir}"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.qemuboot.conf"

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst"* ]]
    [[ "${output}" != *".qemuboot.conf"* ]]
}

# bats test_tags=report
@test "render-only report includes configured degraded aspects" {
    local degraded_file="${BATS_TEST_TMPDIR}/degraded.txt"
    cp "${ROOT_DIR}/config/degraded.txt" "${degraded_file}"
    run env YP_DEGRADED_FILE="${degraded_file}" \
        "${ROOT_DIR}/scripts/report.sh" --release wrynose \
        --variant general --render-only
    [ "${status}" -eq 0 ]
    archive_path="${ROOT_DIR}/${output##*Archive: }"
    grep -Fq '## 降级清单' "${archive_path}"
    grep -Fq 'spdx-format' "${archive_path}"
}

# bats test_tags=report
@test "artifact helpers accept pre-5.0 naming without rootfs segment" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-v4"
    mkdir -p "${deploy_dir}"
    printf 'x' >"${deploy_dir}/core-image-minimal-qemux86-64.ext4"
    printf 'y' >"${deploy_dir}/core-image-minimal-qemux86-64.tar.bz2"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.manifest"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.qemuboot.conf"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.testdata.json"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"core-image-minimal-qemux86-64.ext4" ]]

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".ext4"* ]]
    [[ "${output}" == *".tar.bz2"* ]]
    [[ "${output}" != *".manifest"* ]]
    [[ "${output}" != *".qemuboot.conf"* ]]
    [[ "${output}" != *".testdata.json"* ]]
}

# bats test_tags=report
@test "artifact helpers fall back to timestamped aliases and do not double count" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-ts"
    mkdir -p "${deploy_dir}"
    printf 'x' >"${deploy_dir}/core-image-minimal-qemux86-64-20260101010101.rootfs.ext4"
    printf 'y' >"${deploy_dir}/core-image-minimal-qemux86-64-20260101010101.rootfs.tar.bz2"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4" ]]

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [ "$(printf '%s\n' "${output}" | wc -l)" -eq 2 ]
}

# bats test_tags=report
@test "artifact list prefers short names when both naming styles coexist" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-both"
    mkdir -p "${deploy_dir}"
    printf 'x' >"${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4"
    printf 'x' >"${deploy_dir}/core-image-minimal-qemux86-64-20260101010101.rootfs.ext4"

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [ "$(printf '%s\n' "${output}" | wc -l)" -eq 1 ]
    [[ "${output}" == *"core-image-minimal-qemux86-64.rootfs.ext4" ]]
}

# bats test_tags=report
@test "report archive name carries the variant, general stays unsuffixed" {
    # #22 要在同一 release 下同时归档 general 与 custom，文件名必须能区分，
    # 否则后生成的会把前一个覆盖掉。
    run "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant custom --render-only
    [ "${status}" -eq 0 ]
    local custom_archive="${ROOT_DIR}/${output##*Archive: }"
    [[ "${custom_archive}" == *-custom-render.md ]]
    [[ -f "${custom_archive}" ]]
    rm -f -- "${custom_archive}"

    run "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant general --render-only
    [ "${status}" -eq 0 ]
    local general_archive="${ROOT_DIR}/${output##*Archive: }"
    [[ "${general_archive}" == *-render.md ]]
    [[ "${general_archive}" != *-general-* ]]
    rm -f -- "${general_archive}"
}

# bats test_tags=report
@test "checksum file name follows the archive so old reports stay consistent" {
    # #41：校验文件曾固定叫 artifacts.sha256，同一 release 每跑一次报告就重写，
    # 旧归档报告指向的 commit 于是和文件头对不上。现在名字带 date+commit，
    # 每次真构建各留一份，谁也不会覆盖谁。
    # 这里只断言命名规则：报告正文那行要真有产物才输出，CI 无构建产物时不存在。
    grep -qF 'checksum_name="artifacts-${date_stamp}-${commit}"' \
        "${ROOT_DIR}/scripts/report.sh"
    grep -qF 'checksum_name+="-${variant}"' "${ROOT_DIR}/scripts/report.sh"
    # 正文引用的必须是这个名字，不能写死
    grep -qF '全部产物 sha256: 见 `%s.sha256`' "${ROOT_DIR}/scripts/report.sh"
    grep -qF '"${checksum_name}"' "${ROOT_DIR}/scripts/report.sh"
    # 不许退回固定名
    run grep -qE '^checksum_name="artifacts"$' "${ROOT_DIR}/scripts/report.sh"
    [ "${status}" -eq 1 ]
}

# bats test_tags=report
@test "report archive name carries the machine for non-default machines" {
    # #27：同一 release 会同时存在 x86_64 与 arm64 报告，文件名必须能区分，
    # 否则后生成的会把前一个盖掉。
    run "${ROOT_DIR}/scripts/report.sh" --release wrynose --machine qemuarm64 --render-only
    [ "${status}" -eq 0 ]
    local arm_archive="${ROOT_DIR}/${output##*Archive: }"
    [[ "${arm_archive}" == *-qemuarm64-render.md ]]
    [ -f "${arm_archive}" ]
    grep -qF 'Machine: `qemuarm64`' "${arm_archive}"
    rm -f -- "${arm_archive}"

    # 默认 machine 的归档名保持原样，不能出现 -qemux86-64
    run "${ROOT_DIR}/scripts/report.sh" --release wrynose --render-only
    [ "${status}" -eq 0 ]
    local default_archive="${ROOT_DIR}/${output##*Archive: }"
    [[ "${default_archive}" != *qemux86-64* ]]
    rm -f -- "${default_archive}"
}
