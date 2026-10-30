#!/usr/bin/env bash
# =============================================================================
# scripts/sdk.sh — 产出并验证 SDK / eSDK（issue #25）
#
# 需求 §7.3：SDK 与 eSDK 必须成功，不允许降级，dunfell 也不例外。
# 本脚本做三件事，缺一不可：
#   1. 在 release 容器里跑 bitbake -c populate_sdk 与 -c populate_sdk_ext；
#   2. 把两个安装包真装一遍（-y -d <tmp>），source 环境脚本后验 gcc / devtool
#      —— 「产物存在」不等于「装了能用」，这一步才是验收；
#   3. 把体积、SHA-256、gcc 版本、devtool 结果写成
#      work/artifacts/<release>/<variant>/sdk.json，供 scripts/report.sh --sdk
#      渲染归档（report 不构建，只读这份 json）。
#
# 用法：
#   scripts/sdk.sh --release <r> --variant general|custom [--machine <m>]
#                  [--image-mode release|dev] [--dry-run]
#   scripts/sdk.sh --release <r> --variant <v> --verify-only   只重跑安装验证
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
用法：
  scripts/sdk.sh --release R --variant general|custom [--machine M]
                 [--image-mode release|dev] [--dry-run] [--verify-only]
EOF
}

invalid_args() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

release=""
variant=""
machine=qemux86-64
image_mode=release
dry_run=0
verify_only=0
while (($# > 0)); do
    case "$1" in
        --release | --variant | --machine | --image-mode)
            (($# >= 2)) || invalid_args "$1 缺少参数"
            case "$1" in
                --release) release="$2" ;;
                --variant) variant="$2" ;;
                --machine) machine="$2" ;;
                --image-mode) image_mode="$2" ;;
            esac
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --verify-only)
            verify_only=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) invalid_args "未知参数：$1" ;;
    esac
done

[[ -n "${release}" ]] || invalid_args "必须指定 --release"
[[ -f "${ROOT_DIR}/config/${release}.env" ]] ||
    invalid_args "release 配置不存在：${release}"
case "${variant}" in
    general | custom) ;;
    *) invalid_args "--variant 必须是 general|custom" ;;
esac
case "${image_mode}" in
    release | dev) ;;
    *) invalid_args "--image-mode 必须是 release|dev" ;;
esac
[[ -f "${ROOT_DIR}/config/machines/${machine}.env" ]] ||
    invalid_args "machine 配置不存在：config/machines/${machine}.env"

resolve_all "${release}" "${variant}" "${machine}"
machine_sfx="$(machine_suffix "${machine}")"

kas_work_dir="${ROOT_DIR}/work/kas-${release}-${variant}${machine_sfx}"
deploy_sdk="${kas_work_dir}/build/tmp/deploy/sdk"
log_file="${ROOT_DIR}/work/logs/sdk-${release}-${variant}${machine_sfx}.log"
meta_file="${log_file%.log}.meta"
artifact_dir="${ROOT_DIR}/work/artifacts/${release}/${variant}${machine_sfx}"
json_file="${artifact_dir}/sdk.json"

# 构建命令必须走 kas shell：release 容器里 bitbake 不在 PATH 上，
# 环境是 kas 依据 target 配置现搭的（与 scripts/build.sh 同一条路子）。
# 镜像名在这里就展开成字面量：kas -c 走的是 /bin/sh -c，bitbake 的 ${IMAGE}
# 在那个 shell 里根本不存在，留着只会被展开成空串。
kas_configs="/work/kas/targets/${release}-${variant}.yml"
[[ "${machine}" == "qemux86-64" ]] ||
    kas_configs+=":/work/kas/machines/${machine}.yml"
kas_work_dir_container="/work/work/kas-${release}-${variant}${machine_sfx}"
sdk_bb_cmd="bitbake -c populate_sdk ${IMAGE} && bitbake -c populate_sdk_ext ${IMAGE}"
build_command="mkdir -p ${kas_work_dir_container} /work/work/downloads /work/work/sstate"
build_command+=" && KAS_CLONE_DEPTH=1 KAS_WORK_DIR=${kas_work_dir_container}"
build_command+=" kas shell ${kas_configs} -c '${sdk_bb_cmd}'"

if ((dry_run)); then
    printf 'kas_work_dir=%s\n' "${kas_work_dir}"
    printf 'deploy_sdk=%s\n' "${deploy_sdk}"
    printf 'log=%s\n' "${log_file}"
    printf 'json=%s\n' "${json_file}"
    printf './project.sh shell --release %s --variant %s --machine %s -- bash -lc %s\n' \
        "${release}" "${variant}" "${machine}" "'${build_command}'"
    exit 0
fi

mkdir -p "${ROOT_DIR}/work/logs" "${artifact_dir}"

###############################################################################
# 1. 构建
###############################################################################
if ((verify_only == 0)); then
    if [[ "${image_mode}" == "release" ]]; then
        command_args=(./project.sh shell --release "${release}" --variant "${variant}"
            --machine "${machine}" -- bash -lc)
    else
        command_args=(bash scripts/dev.sh bash -lc)
    fi
    cd -- "${ROOT_DIR}"
    # 与 build.sh 共用一把锁：SDK 也是 bitbake，不能和镜像构建抢 TMPDIR。
    lock_file="${ROOT_DIR}/work/build.lock"
    exec 9>"${lock_file}"
    flock -n 9 || {
        printf 'ERROR: 另一个构建正在运行（锁：%s）；本工程规定串行构建\n' "${lock_file}" >&2
        exit 3
    }

    start_seconds="$(date +%s)"
    printf 'SDK build start: %s\n' "$(date --iso-8601=seconds)" | tee "${log_file}"
    build_status=0
    "${command_args[@]}" "${build_command}" 2>&1 | tee -a "${log_file}" || build_status=$?
    end_seconds="$(date +%s)"
    printf '%s\n' "$((end_seconds - start_seconds))" >"${meta_file}"
    printf 'SDK build end: %s (exit %s)\n' "$(date --iso-8601=seconds)" "${build_status}" |
        tee -a "${log_file}"
    ((build_status == 0)) || {
        printf 'ERROR: SDK 构建失败（exit %s）；日志：%s\n' "${build_status}" "${log_file}" >&2
        exit "${build_status}"
    }
fi

###############################################################################
# 2. 安装 + 验证（在同一个 release 容器里做：SDK 的宿主工具链版本与它自己的
#    构建容器一致，换到别的宿主验没有意义）
###############################################################################
[[ -d "${deploy_sdk}" ]] || {
    printf 'ERROR: 没有 SDK 产物目录：%s\n' "${deploy_sdk}" >&2
    exit 1
}

sdk_installer="$(find "${deploy_sdk}" -maxdepth 1 -name "*${IMAGE}*${machine}-toolchain-*.sh" \
    ! -name '*-toolchain-ext-*' | LC_ALL=C sort | tail -n 1)"
esdk_installer="$(find "${deploy_sdk}" -maxdepth 1 -name "*${IMAGE}*${machine}-toolchain-ext-*.sh" |
    LC_ALL=C sort | tail -n 1)"
[[ -n "${sdk_installer}" ]] || {
    printf 'ERROR: 找不到 SDK 安装包（%s/*%s*%s-toolchain-*.sh）\n' \
        "${deploy_sdk}" "${IMAGE}" "${machine}" >&2
    exit 1
}
[[ -n "${esdk_installer}" ]] || {
    printf 'ERROR: 找不到 eSDK 安装包（%s/*%s*%s-toolchain-ext-*.sh）\n' \
        "${deploy_sdk}" "${IMAGE}" "${machine}" >&2
    exit 1
}

verify_script="$(mktemp "${ROOT_DIR}/work/logs/.sdk-verify.XXXXXX.sh")"
cleanup() { rm -f -- "${verify_script}"; }
trap cleanup EXIT

cat >"${verify_script}" <<'VERIFY'
set -uo pipefail
sdk_installer="$1"
esdk_installer="$2"
out_json="$3"
work_dir="$(mktemp -d /tmp/sdk-verify.XXXXXX)"
sdk_dir="${work_dir}/sdk"
esdk_dir="${work_dir}/esdk"

result="{}"

install_sdk() {
    # 非交互安装到指定目录；-y 接受许可、-d 指定目录。
    bash "${sdk_installer}" -y -d "${sdk_dir}" >"${work_dir}/sdk-install.log" 2>&1
}

check_sdk() {
    local setup
    setup="$(find "${sdk_dir}" -maxdepth 1 -name 'environment-setup-*' ! -name '*-ext-*' |
        head -n 1)"
    [[ -n "${setup}" ]] || {
        printf 'no environment-setup script\n'
        return 1
    }
    # shellcheck disable=SC1090
    ( set +u; . "${setup}" >/dev/null 2>&1
      # SDK 里裸 gcc 不一定在 PATH 上：交叉编译器是 <triple>-gcc，$CC 指向它。
      if command -v gcc >/dev/null 2>&1; then
          gcc -dumpversion 2>/dev/null
      elif [[ -n "${CC:-}" ]]; then
          # shellcheck disable=SC2086
          ${CC} -dumpversion 2>/dev/null
      fi )
}

check_esdk() {
    local setup
    setup="$(find "${esdk_dir}" -maxdepth 1 -name 'environment-setup-*' | head -n 1)"
    [[ -n "${setup}" ]] || {
        printf 'no environment-setup script\n'
        return 1
    }
    ( set +u; . "${setup}" >/dev/null 2>&1
      devtool --help >/dev/null 2>&1 && printf 'ok' || printf 'missing' )
}

sdk_install_ok=false
sdk_gcc=""
if install_sdk; then sdk_install_ok=true; fi
sdk_gcc="$(check_sdk || true)"

esdk_install_ok=false
esdk_devtool=""
if bash "${esdk_installer}" -y -d "${esdk_dir}" >"${work_dir}/esdk-install.log" 2>&1; then
    esdk_install_ok=true
fi
esdk_devtool="$(check_esdk || true)"

python3 - "${out_json}" "${sdk_install_ok}" "${sdk_gcc}" \
    "${esdk_install_ok}" "${esdk_devtool}" <<'PY'
import json, sys
path, sdk_ok, sdk_gcc, esdk_ok, esdk_devtool = sys.argv[1:6]
data = {
    "sdk_install_ok": sdk_ok == "true",
    "sdk_gcc": sdk_gcc.strip(),
    "esdk_install_ok": esdk_ok == "true",
    "esdk_devtool": esdk_devtool.strip(),
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, sort_keys=True)
PY

rm -rf -- "${work_dir}"
VERIFY

printf '安装验证中（SDK + eSDK 各解包一份到 /tmp）…\n'
verify_json="${artifact_dir}/.verify.json"
if [[ "${image_mode}" == "release" ]]; then
    ./project.sh shell --release "${release}" --variant "${variant}" --machine "${machine}" \
        -- bash -lc "bash /work/${verify_script#"${ROOT_DIR}/"} \
            '/work/${sdk_installer#"${ROOT_DIR}/"}' '/work/${esdk_installer#"${ROOT_DIR}/"}' \
            '/work/${verify_json#"${ROOT_DIR}/"}'"
else
    bash scripts/dev.sh bash -lc "bash /work/${verify_script#"${ROOT_DIR}/"} \
        '/work/${sdk_installer#"${ROOT_DIR}/"}' '/work/${esdk_installer#"${ROOT_DIR}/"}' \
        '/work/${verify_json#"${ROOT_DIR}/"}'"
fi

###############################################################################
# 3. 汇总成 sdk.json
###############################################################################
python3 - "${json_file}" "${release}" "${variant}" "${machine}" "${TAG}" \
    "${ROOT_DIR}" "${sdk_installer}" "${esdk_installer}" "${verify_json}" \
    "${meta_file}" "$(git -C "${ROOT_DIR}" rev-parse --short HEAD)" \
    "$(date +%Y%m%d)" <<'PY'
import hashlib
import json
import os
import sys

(
    json_path,
    release,
    variant,
    machine,
    tag,
    root,
    sdk_installer,
    esdk_installer,
    verify_json,
    meta_file,
    commit,
    date_stamp,
) = sys.argv[1:13]


def describe(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "file": os.path.basename(path),
        "relative": os.path.relpath(path, root),
        "bytes": os.path.getsize(path),
        "sha256": digest.hexdigest(),
    }


verified = {}
if os.path.exists(verify_json):
    with open(verify_json, encoding="utf-8") as handle:
        verified = json.load(handle)
    os.remove(verify_json)

build_seconds = None
if os.path.exists(meta_file):
    raw = open(meta_file, encoding="utf-8").read().strip()
    if raw.isdigit():
        build_seconds = int(raw)

sdk = describe(sdk_installer)
sdk["installed"] = bool(verified.get("sdk_install_ok"))
sdk["gcc"] = verified.get("sdk_gcc") or "n/a"
esdk = describe(esdk_installer)
esdk["installed"] = bool(verified.get("esdk_install_ok"))
esdk["devtool"] = verified.get("esdk_devtool") or "n/a"

data = {
    "release": release,
    "variant": variant,
    "machine": machine,
    "tag": tag,
    "commit": commit,
    "date": date_stamp,
    "build_seconds": build_seconds,
    "sdk": sdk,
    "esdk": esdk,
}
with open(json_path + ".tmp", "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(json_path + ".tmp", json_path)

ok = sdk["installed"] and esdk["installed"] and esdk["devtool"] == "ok"
print("SDK  : %s (%d B, sha256 %s…)" % (sdk["file"], sdk["bytes"], sdk["sha256"][:12]))
print("       installed=%s gcc=%s" % (sdk["installed"], sdk["gcc"]))
print("eSDK : %s (%d B, sha256 %s…)" % (esdk["file"], esdk["bytes"], esdk["sha256"][:12]))
print("       installed=%s devtool=%s" % (esdk["installed"], esdk["devtool"]))
print("JSON : %s" % os.path.relpath(json_path, root))
sys.exit(0 if ok else 1)
PY
