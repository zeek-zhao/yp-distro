#!/usr/bin/env bash

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/log.sh
source "${ROOT_DIR}/scripts/lib/log.sh"

_load_config() {
    local kind="$1" name="$2" file

    [[ "${name}" =~ ^[[:alnum:]_-]+$ ]] || die "无效的 ${kind} 名称：${name}"
    file="${ROOT_DIR}/config/${kind}/${name}.env"
    if [[ "${kind}" == release ]]; then
        file="${ROOT_DIR}/config/${name}.env"
        unset POKY_REPO POKY_TAG EXPECT_SHA
        unset OE_CORE_REPO OE_CORE_TAG BITBAKE_REPO BITBAKE_TAG
        unset META_YOCTO_REPO META_YOCTO_TAG
    fi
    [[ -f "${file}" ]] || die "${kind} 配置不存在：${file}"
    # shellcheck source=/dev/null
    source "${file}"
}

load_release() {
    [[ $# -eq 1 ]] || die "用法：load_release <name>"
    _load_config release "$1"
}

load_variant() {
    [[ $# -eq 1 ]] || die "用法：load_variant <name>"
    _load_config variants "$1"
}

load_machine() {
    [[ $# -eq 1 ]] || die "用法：load_machine <name>"
    _load_config machines "$1"
}

resolve_all() {
    [[ $# -eq 3 ]] || die "用法：resolve_all <release> <variant> <machine>"

    load_release "$1"
    load_variant "$2"
    load_machine "$3"

    case "${REPO_MODE:-}" in
        poky) TAG="${POKY_TAG:-}" ;;
        split) TAG="${OE_CORE_TAG:-}" ;;
        *) die "无效的 REPO_MODE：${REPO_MODE:-未设置}" ;;
    esac
    [[ -n "${TAG}" ]] || die "release 配置缺少对应的 tag"

    export RELEASE REPO_MODE TAG VARIANT DISTRO IMAGE MACHINE
}

work_dir() {
    [[ $# -ge 1 && $# -le 2 ]] || die "用法：work_dir <kind> [release]"

    local kind="$1" release="${2:-${RELEASE:-}}" path="${ROOT_DIR}/work"
    if [[ -n "${release}" && ! "${release}" =~ ^[[:alnum:]_-]+$ ]]; then
        die "无效的 release 名称：${release}"
    fi
    case "${kind}" in
        src | build | artifacts | lock)
            path+="/${kind}"
            if [[ -n "${release}" ]]; then
                path+="/${release}"
            fi
            ;;
        downloads | sstate) path+="/${kind}" ;;
        *) die "无效的 work_dir 类型：${kind}" ;;
    esac
    printf '%s\n' "${path}"
}

check_disk_watermark() {
    [[ $# -le 1 ]] || die "用法：check_disk_watermark [pct=85]"

    local threshold="${1:-85}" path df_output df_line filesystem percent
    local -a df_fields
    [[ "${threshold}" =~ ^[0-9]+$ ]] || die "磁盘水位必须是 0 到 100 的整数：${threshold}"
    threshold=$((10#${threshold}))
    ((threshold <= 100)) || die "磁盘水位必须是 0 到 100 的整数：${threshold}"

    path="${ROOT_DIR}/work"
    [[ -d "${path}" ]] || path="${ROOT_DIR}"
    df_output="$(df -P "${path}")" || {
        log_error "无法检查磁盘水位：${path}"
        return 1
    }
    df_line="${df_output##*$'\n'}"
    read -r -a df_fields <<<"${df_line}"
    ((${#df_fields[@]} >= 5)) || {
        log_error "无法解析磁盘信息：${df_line}"
        return 1
    }
    filesystem="${df_fields[0]}"
    percent="${df_fields[4]}"
    percent="${percent%\%}"
    [[ "${percent}" =~ ^[0-9]+$ ]] || {
        log_error "无法解析磁盘使用率：${df_line}"
        return 1
    }

    printf 'Disk usage: %s%% (threshold: %s%%, filesystem: %s)\n' \
        "${percent}" "${threshold}" "${filesystem}"
    if ((10#${percent} > threshold)); then
        log_warn "磁盘使用率超过 ${threshold}%；请清理 work/ 下不再需要的构建、下载或 sstate 数据（C23）"
        return 1
    fi
}
