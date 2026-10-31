#!/usr/bin/env bash
# =============================================================================
# scripts/scancode.sh — 按需准备 ScanCode CLI（不烤进镜像）
#
# 背景（C26 / #28）：C26 原写「镜像内置 ScanCode CLI」，但实测四个镜像里
# `which scancode` 全是 MISSING；而真烤进去的代价是每个镜像 +0.8~1 GB
# （standalone 包 configure 之后：py3.8 790 MB、py3.10/3.12 950 MB），
# 四个镜像等于体积翻倍。改为按需下载到 work/tools/，容器内以
# /work/work/tools/... 挂载使用，镜像体积不变。
#
# 为什么不用 native recipe：scancode 是 Python 应用而非 C 工具，依赖树上百个包
# 且版本互相钉死，typecode / intbitset 还是编译扩展。这里用上游按 Python 版本
# 预构建的 standalone 包，`./configure` 全程离线（依赖 wheel 都在 bundle 的
# thirdparty/ 目录里，实测 9~10 秒）。
#
# 版本按镜像的系统 python 选，四个 release 用三个包：
#   dunfell   3.1.33  ubuntu:20.04  py3.8   32.0.6   （32.5.0 要求 >=3.10）
#   kirkstone 4.0.35  ubuntu:22.04  py3.10  32.5.0
#   scarthgap 5.0.20  ubuntu:24.04  py3.12  32.5.0
#   wrynose   6.0.4   ubuntu:24.04  py3.12  32.5.0   （与 scarthgap 共用一份）
#
# 注意：32.5.0 的 py3.10 与 py3.12 是**两个不同的包**，而包内顶层目录同名
# （scancode-toolkit-v32.5.0），所以解压后必须立刻按「版本-py」改名，否则两者
# 会互相覆盖。
#
# 用法：
#   scripts/scancode.sh sync [--release <r>|all]   下载 + 解压 + ./configure
#   scripts/scancode.sh status                     查看各 release 的就绪状态
#   scripts/scancode.sh path --release <r>         打印容器内可执行路径
#
# 环境变量：
#   YP_SCANCODE_BASE_URL  资产基地址，默认 GitHub Release
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

BASE_URL="${YP_SCANCODE_BASE_URL:-https://github.com/aboutcode-org/scancode-toolkit/releases/download}"
BUNDLE_DIR="${ROOT_DIR}/work/tools/bundles"
TOOLS_DIR="${ROOT_DIR}/work/tools"
ALL_RELEASES=(dunfell kirkstone scarthgap wrynose)

usage() {
    cat <<'EOF'
用法：
  scripts/scancode.sh sync   [--release <r>|all] [--force]
  scripts/scancode.sh status
  scripts/scancode.sh path   --release <r>
EOF
}

die_usage() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

# 各 release 的 scancode 版本与包内 python 版本（依据见文件头）。
release_version() {
    case "$1" in
        dunfell) printf '32.0.6' ;;
        kirkstone | scarthgap | wrynose) printf '32.5.0' ;;
        *) return 1 ;;
    esac
}

release_python() {
    case "$1" in
        dunfell) printf '3.8' ;;
        kirkstone) printf '3.10' ;;
        scarthgap | wrynose) printf '3.12' ;;
        *) return 1 ;;
    esac
}

asset_name() {
    printf 'scancode-toolkit-v%s_py%s-linux.tar.gz' \
        "$(release_version "$1")" "$(release_python "$1")"
}

bundle_path() {
    printf '%s/%s' "${BUNDLE_DIR}" "$(asset_name "$1")"
}

# 解压目录名按「版本 + py」而不是按 release：scarthgap 与 wrynose 共用一份，
# kirkstone 与它们同版本号但 py 不同，必须靠 py 后缀区分。
install_name() {
    printf 'scancode-v%s-py%s' \
        "$(release_version "$1")" "$(release_python "$1")"
}

install_dir() {
    printf '%s/%s' "${TOOLS_DIR}" "$(install_name "$1")"
}

container_bin() {
    printf '/work/work/tools/%s/scancode' "$(install_name "$1")"
}

ready() {
    local dir
    dir="$(install_dir "$1")"
    [[ -x "${dir}/scancode" && -d "${dir}/venv" ]]
}

download_bundle() {
    local release="$1" url dest base
    url="${BASE_URL}/v$(release_version "${release}")/$(asset_name "${release}")"
    dest="$(bundle_path "${release}")"
    [[ -f "${dest}" ]] && return 0
    mkdir -p -- "${BUNDLE_DIR}"
    base="$(basename -- "${dest}")"
    log_info "下载 ${base}（约 140~220 MB，只需一次）"
    curl -fL --retry 3 --retry-delay 5 -o "${dest}.part" "${url}"
    mv -- "${dest}.part" "${dest}"
    (cd -- "${BUNDLE_DIR}" && sha256sum -- "${base}" >"${base}.sha256")
}

# ./configure 必须在「与镜像同 python 版本」的容器里跑：venv 里的编译扩展
# （typecode / intbitset）按解释器版本绑定，换版本就废。
configure_bundle() {
    local release="$1" asset top name cmd
    ready "${release}" && {
        log_info "$(install_name "${release}") 已就绪，跳过"
        return 0
    }
    mkdir -p -- "${TOOLS_DIR}"
    asset="$(asset_name "${release}")"
    # 包内顶层目录只带版本号，不带 _py<X>-linux 后缀（实测 v32.0.6 与 v32.5.0 都如此）。
    top="scancode-toolkit-v$(release_version "${release}")"
    name="$(install_name "${release}")"
    log_info "解压并在 ${release} 容器内 configure（离线，约 10 秒）"
    cmd="rm -rf /work/work/tools/${top} /work/work/tools/${name}"
    cmd+=" && tar -xzf /work/work/tools/bundles/${asset} -C /work/work/tools"
    cmd+=" && mv /work/work/tools/${top} /work/work/tools/${name}"
    cmd+=" && cd /work/work/tools/${name} && ./configure --quiet"
    cmd+=" && test -x /work/work/tools/${name}/scancode"
    cmd+=" && test -d /work/work/tools/${name}/venv"
    ./project.sh shell --release "${release}" --variant general -- bash -lc "${cmd}"
}

do_sync() {
    local target="$1" release
    local -a targets=()
    if [[ "${target}" == "all" ]]; then
        targets=("${ALL_RELEASES[@]}")
    else
        targets=("${target}")
    fi
    for release in "${targets[@]}"; do
        [[ -n "$(release_version "${release}" 2>/dev/null)" ]] ||
            die "不支持的 release：${release}（支持 ${ALL_RELEASES[*]}）"
        download_bundle "${release}"
        configure_bundle "${release}"
    done
    do_status
}

do_status() {
    local release asset dir state
    printf '%-11s %-7s %-7s %-9s %s\n' RELEASE VERSION PYTHON STATE PATH
    for release in "${ALL_RELEASES[@]}"; do
        asset="$(asset_name "${release}")"
        dir="$(install_dir "${release}")"
        if ready "${release}"; then
            state=ready
        elif [[ -f "${BUNDLE_DIR}/${asset}" ]]; then
            state=bundle
        else
            state=missing
        fi
        printf '%-11s %-7s %-7s %-9s %s\n' \
            "${release}" "$(release_version "${release}")" "py$(release_python "${release}")" \
            "${state}" "$(container_bin "${release}")"
    done
    printf '\n缓存位置：%s\n' "${BUNDLE_DIR#"${ROOT_DIR}/"}"
    printf '就绪判定：解压目录内同时有 scancode 与 venv/（configure 完成的标志）\n'
    if [[ -d "${TOOLS_DIR}" ]]; then
        printf '磁盘占用：%s\n' "$(du -sh -- "${TOOLS_DIR}" 2>/dev/null | cut -f1)"
    fi
}

command="${1:-}"
[[ $# -gt 0 ]] && shift
target="all"
force=0
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die_usage "--release 缺少参数"
            target="$2"
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        -h | --help | help)
            usage
            exit 0
            ;;
        *) die_usage "未知参数：$1" ;;
    esac
done

case "${command}" in
    sync)
        if ((force)); then
            rm -rf -- "${TOOLS_DIR}/scancode-v"[0-9]*
        fi
        do_sync "${target}"
        ;;
    status) do_status ;;
    path)
        [[ "${target}" != "all" ]] || die_usage "path 需要 --release <r>"
        [[ -n "$(release_version "${target}" 2>/dev/null)" ]] ||
            die "不支持的 release：${target}"
        container_bin "${target}"
        ;;
    '' | -h | --help | help) usage ;;
    *) die "未知命令：${command}" ;;
esac
