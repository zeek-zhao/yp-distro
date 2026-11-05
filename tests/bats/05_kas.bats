#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    KAS_DIR="${ROOT_DIR}/kas"
    VERIFY_SCRIPT="${ROOT_DIR}/scripts/kas-verify.py"
}

# bats test_tags=kas
@test "kas configuration contains the complete release and variant matrix" {
    local yml_count target_count release variant
    yml_count="$(find "${KAS_DIR}" -name '*.yml' ! -name '*.lock.yml' | wc -l)"
    target_count="$(find "${KAS_DIR}/targets" -name '*.yml' ! -name '*.lock.yml' | wc -l)"
    # 23 = 1 base + 4 release + 2 variant + 2 machine（x86-64 / arm64）+ 8 target
    #      + 6 feature（cve/spdx/uboot 为构建开关；rootfs-squashfs/rootfs-cpio 为
    #        #74 实验开关；dm-verity-security 为 #117 路线一集成）
    [ "${yml_count}" -eq 23 ]
    [ "${target_count}" -eq 8 ]
    for release in dunfell kirkstone scarthgap wrynose; do
        for variant in general custom; do
            [ -f "${KAS_DIR}/targets/${release}-${variant}.yml" ]
        done
    done
}

# bats test_tags=kas
@test "builtin validator checks all eight targets" {
    run python3 "${VERIFY_SCRIPT}" --engine builtin
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"8 targets OK"* ]]
}

# bats test_tags=kas
@test "validator rejects release tags that drift from config" {
    local test_root
    test_root="${BATS_TEST_TMPDIR}/kas-root"
    mkdir -p "${test_root}"
    cp -R "${KAS_DIR}" "${test_root}/kas"
    cp -R "${ROOT_DIR}/config" "${test_root}/config"
    # 漂移注入必须版本无关：真实 tag 会随点版本跟进变动（#115 首演踩过
    # 硬编码 5.0.20 的 sed 在 5.0.21 后落空）。把 scarthgap 的 tag 换成
    # 一个必然与 config 不一致的假版本。
    sed -i 's|tag: yocto-[0-9.]*$|tag: yocto-9.9.drift|' \
        "${test_root}/kas/releases/scarthgap.yml"
    run python3 "${VERIFY_SCRIPT}" --engine builtin --root "${test_root}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"FAIL"* ]]
}

# bats test_tags=kas
@test "every kas YAML declares header version 14" {
    run python3 -c '
from pathlib import Path
import sys
import yaml
root = Path(sys.argv[1])
files = [p for p in sorted((root / "kas").rglob("*.yml"))
         if not p.name.endswith(".lock.yml")]
assert len(files) == 23, len(files)
for path in files:
    assert yaml.safe_load(path.read_text())["header"]["version"] == 14, path
' "${ROOT_DIR}"
    [ "${status}" -eq 0 ]
}

# bats test_tags=kas
@test "base configuration does not define repositories" {
    run grep -q '^repos:' "${KAS_DIR}/base.yml"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "wrynose declares split repositories without poky" {
    local repo
    run grep -q '^  poky:' "${KAS_DIR}/releases/wrynose.yml"
    [ "${status}" -eq 1 ]
    for repo in openembedded-core bitbake meta-yocto; do
        grep -q "${repo}:" "${KAS_DIR}/releases/wrynose.yml"
    done
}

# bats test_tags=kas
@test "custom variant uses the agreed YP variable name" {
    grep -q 'YP_VARIANT = "custom"' "${KAS_DIR}/variants/custom.yml"
    run grep -c 'ZEEK_VARIANT' "${KAS_DIR}/variants/custom.yml"
    [ "${status}" -eq 1 ]
    [ "${output}" = "0" ]
}

# bats test_tags=kas
@test "custom variant references meta-yp as a local repository" {
    # 不能有 url 或任何版本引用，否则 kas 会 clone 私有仓库
    run grep -E '^[[:space:]]+(url|commit|tag|branch|refspec|path):' \
        "${KAS_DIR}/variants/custom.yml"
    [ "${status}" -eq 1 ]
    grep -q '^      layers/meta-yp:$' "${KAS_DIR}/variants/custom.yml"
}

# bats test_tags=kas
@test "wrynose keeps bitbake out of BBLAYERS" {
    # 缺省 layers 时 kas 用 {'': None}，会把 bitbake/ 当 layer，解析必失败
    run grep -A3 '^  bitbake:' "${KAS_DIR}/releases/wrynose.yml"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"layers: {}"* ]]
}

# bats test_tags=kas
@test "release-specific knobs match each Yocto version" {
    grep -q 'CONF_VERSION = "1"' "${KAS_DIR}/releases/dunfell.yml"
    grep -q 'CONF_VERSION ??= "2"' "${KAS_DIR}/base.yml"
    # UNPACKDIR 只有 6.0（wrynose）才有；5.0 覆盖它会让 S 停在字面量，
    # 真构建时 do_unpack 直接 fatal（bitbake -n 看不出来）。
    grep -qE '^[[:space:]]*YP_SRC_DIR = "\$\{UNPACKDIR\}"' \
        "${KAS_DIR}/releases/wrynose.yml"
    for release in dunfell kirkstone scarthgap; do
        # 只看赋值行：scarthgap 的注释里会提到 YP_SRC_DIR（说明为什么不能覆盖）
        run grep -qE '^[[:space:]]*YP_SRC_DIR[[:space:]]*=' \
            "${KAS_DIR}/releases/${release}.yml"
        [ "${status}" -eq 1 ]
    done
    grep -q 'YP_CVE_CLASS = "sbom-cve-check"' "${KAS_DIR}/releases/wrynose.yml"
    # 开关值随 P2 进度变（当前 "0"：NVD 全量建库约 4 小时），只校验取值合法
    grep -Eq 'YP_CVE_ENABLE = "[01]"' "${KAS_DIR}/variants/custom.yml"
    run grep -q 'INHERIT += "cve-check"' "${KAS_DIR}/variants/custom.yml"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "distro layer inherits the CVE class only when the variant asks for it" {
    # 不能就近 inherit 到 yp-image：cve-update-nvd2-native.bb 自带 SkipRecipe 守卫，
    # 类没进全局 INHERIT 就会在解析期报 "Nothing PROVIDES 'cve-update-nvd2-native'"。
    grep -q "bb.utils.contains('YP_CVE_ENABLE', '1', d.getVar('YP_CVE_CLASS')" \
        "${ROOT_DIR}/layers/meta-yp/conf/distro/yp.conf"
    run grep -q "bb.utils.contains('YP_CVE_ENABLE'" \
        "${ROOT_DIR}/layers/meta-yp/recipes-core/images/yp-image.bb"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "dev Dockerfile installs kas and records its fingerprint" {
    grep -Fq 'kas==${KAS_VERSION}' "${ROOT_DIR}/docker/dev/Dockerfile"
    grep -Fq "printf 'kas=%s" "${ROOT_DIR}/docker/dev/Dockerfile"
}

# bats test_tags=kas
@test "kas command is wired through Makefile and project CLI" {
    grep -Eq '^PROJECT_TARGETS = .*([[:space:]]|^)kas([[:space:]]|$)' "${ROOT_DIR}/Makefile"
    grep -q 'kas ' "${ROOT_DIR}/project.sh"
    grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas | ok$' \
        "${ROOT_DIR}/config/features.txt"
}

# bats test_tags=kas
@test "kas feature and BATS tag registration match" {
    grep -q '^# bats test_tags=kas$' "${BATS_TEST_DIRNAME}/05_kas.bats"
    grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas | ok$' \
        "${ROOT_DIR}/config/features.txt"
}

# bats test_tags=kas
@test "build env bounds the parallelism by min(cores, 20)" {
    grep -Eq '^    BB_NUMBER_THREADS = "\$\{@min\(oe\.utils\.cpu_count\(\), 20\)\}"$' \
        "${KAS_DIR}/base.yml"
    grep -Eq '^    PARALLEL_MAKE = "-j \$\{@min\(oe\.utils\.cpu_count\(\), 20\)\}"$' \
        "${KAS_DIR}/base.yml"
    # bitbake.conf 里这两个变量本身就是 ?=，且比 local.conf 先解析，
    # 在这里再写 ?= 等于没写 —— 不报错、只是自动并行度失效。
    run grep -E '^    (BB_NUMBER_THREADS|PARALLEL_MAKE) \?=' "${KAS_DIR}/base.yml"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "disk monitor keeps both STOPTASKS and ABORT tiers" {
    local line
    line="$(grep '^    BB_DISKMON_DIRS = ' "${KAS_DIR}/base.yml")"
    [ -n "${line}" ]
    [[ "${line}" == *"STOPTASKS,\${TMPDIR}"* ]]
    [[ "${line}" == *"STOPTASKS,\${DL_DIR}"* ]]
    [[ "${line}" == *"STOPTASKS,\${SSTATE_DIR}"* ]]
    [[ "${line}" == *"ABORT,\${TMPDIR}"* ]]
    [[ "${line}" == *"ABORT,\${SSTATE_DIR}"* ]]
    # HALT 是 4.0+ 才有的动作，3.1 见到会直接报错退出
    [[ "${line}" != *"HALT,"* ]]
}

# bats test_tags=kas
@test "buildhistory writes one repository per release and variant" {
    grep -q '^    INHERIT += "buildhistory"$' "${KAS_DIR}/base.yml"
    grep -qF 'BUILDHISTORY_DIR = "${TOPDIR}/../../buildhistory/${YP_RELEASE_NAME}-${YP_VARIANT}"' \
        "${KAS_DIR}/base.yml"
    grep -q '^    BUILDHISTORY_COMMIT = "1"$' "${KAS_DIR}/base.yml"
    grep -q '^    BUILDHISTORY_COMMIT_AUTHOR = ' "${KAS_DIR}/base.yml"
    # general 靠默认值，custom 必须显式覆盖；两边都漏就会写进同一目录互相覆盖
    grep -q '^    YP_VARIANT ??= "general"$' "${KAS_DIR}/base.yml"
    grep -q '^    YP_VARIANT = "custom"$' "${KAS_DIR}/variants/custom.yml"
    run grep -q 'YP_VARIANT' "${KAS_DIR}/variants/general.yml"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "mirror tarballs are generated for git sources" {
    grep -q '^    BB_GENERATE_MIRROR_TARBALLS = "1"$' "${KAS_DIR}/base.yml"
    # 只允许在 base 段统一打开，任何 release 单独覆盖都会让那一版断网不可重建
    run grep -rq 'BB_GENERATE_MIRROR_TARBALLS' "${KAS_DIR}/releases"
    [ "${status}" -eq 1 ]
}

# bats test_tags=kas
@test "machine dimension keeps config and kas machine files in pairs" {
    # #27：machine 是双轨表达 —— env 给脚本（工作区/产物/报告命名），
    # yml 给 bitbake（顶层 machine:）。缺一侧或值不一致，构建会落到错误的
    # 机器上，所以两侧必须成对。
    [ -f "${ROOT_DIR}/config/machines/qemuarm64.env" ]
    [ -f "${KAS_DIR}/machines/qemuarm64.yml" ]
    grep -qx 'MACHINE=qemuarm64' "${ROOT_DIR}/config/machines/qemuarm64.env"
    grep -qx 'machine: qemuarm64' "${KAS_DIR}/machines/qemuarm64.yml"
    # 默认 machine 不能从任一侧消失
    [ -f "${ROOT_DIR}/config/machines/qemux86-64.env" ]
    [ -f "${KAS_DIR}/machines/qemux86-64.yml" ]
    run python3 "${VERIFY_SCRIPT}" --engine builtin
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"8 targets OK"* ]]
}

# bats test_tags=kas
@test "machine suffix only appears for non-default machines" {
    # 默认 machine 必须保持无后缀：既有 8 组合的工作区、产物目录、归档名
    # 全依赖这一点，一旦加后缀，历史报告里的路径就全部失效。
    run machine_suffix qemux86-64
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]

    run machine_suffix qemuarm64
    [ "${status}" -eq 0 ]
    [ "${output}" = "-qemuarm64" ]
}

# bats test_tags=kas
@test "kas targets never hardcode a non-default machine" {
    # 非默认 machine 靠 kas 叠加（target.yml:machine.yml）接入；一旦有人把
    # arm64 写进 8 份 target，machine 维度就会开始各处漂移。
    run grep -l 'kas/machines/qemuarm64.yml' "${KAS_DIR}"/targets/*.yml
    [ "${status}" -eq 1 ]
    grep -q 'kas/machines/qemux86-64.yml' "${KAS_DIR}/targets/wrynose-general.yml"
    grep -qF 'kas_configs+=":/work/kas/machines/${machine}.yml"' \
        "${ROOT_DIR}/scripts/build.sh"
}
