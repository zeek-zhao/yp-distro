#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'EOF'
Usage:
  scripts/container.sh --release <release> [--variant <variant>] [--machine <machine>] [--check | --dry-run] [-- <cmd>...]

Options:
  --release <release>  Required Yocto release
  --variant <variant>  Build variant (default: general)
  --machine <machine>  Target machine (default: qemux86-64)
  --check              Run preflight checks without starting a container
  --dry-run            Print the docker run command without executing it
  -h, --help           Show this help
EOF
}

image_name() {
    printf 'ghcr.io/zeek-zhao/yp-distro/%s' "$1"
}

release=""
variant=general
machine=qemux86-64
mode=run
command_args=()
while (($# > 0)); do
    case "$1" in
        --release)
            (($# >= 2)) || die "--release 缺少参数"
            release="$2"
            shift 2
            ;;
        --variant)
            (($# >= 2)) || die "--variant 缺少参数"
            variant="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        --check | --dry-run)
            [[ "${mode}" == run ]] || die "--check 与 --dry-run 只能选一个"
            mode="${1#--}"
            shift
            ;;
        --)
            shift
            command_args=("$@")
            break
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "未知参数：$1"
            ;;
    esac
done

[[ -n "${release}" ]] || die "--release 必填"

resolve_all "${release}" "${variant}" "${machine}"
HOST_REPO_DIR="${WB_HOST_REPO_DIR:-${ROOT_DIR}}"
[[ "${HOST_REPO_DIR}" == /* ]] || die "WB_HOST_REPO_DIR 必须是绝对路径：${HOST_REPO_DIR}"
[[ -d "${ROOT_DIR}" ]] || die "仓库目录不存在：${ROOT_DIR}"
if [[ -n "${WB_HOST_REPO_DIR:-}" ]]; then
    log_info "嵌套模式：挂载源用宿主路径 ${HOST_REPO_DIR}"
fi

host_uid="$(id -u)"
host_gid="$(id -g)"
((host_uid != 0)) || die "禁止以 root 用户启动构建容器"

local_image="$(image_name "${release}"):local"
latest_image="$(image_name "${release}"):latest"
if docker image inspect "${local_image}" >/dev/null 2>&1; then
    resolved_image="${local_image}"
    pull_image=0
elif docker image inspect "${latest_image}" >/dev/null 2>&1; then
    resolved_image="${latest_image}"
    pull_image=1
else
    die "镜像不存在：${local_image} 或 ${latest_image}；请先运行 scripts/image.sh build ${release}"
fi

disk_output=""
if ! disk_output="$(check_disk_watermark "${WATERMARK_PCT:-85}")"; then
    printf '%s\n' "${disk_output}"
    die "磁盘水位检查失败；请清理 work/ 或调整 WATERMARK_PCT"
fi

dl_dir=/work/work/downloads
sstate_dir=/work/work/sstate
home_dir="/work/work/home/${release}"
passwd_file="${ROOT_DIR}/work/home/.passwd"

# KVM 加速探测：宿主 jenkins 不在 kvm 组，所以宿主直跑 QEMU 拿不到 /dev/kvm，
# 容器内必须用 --device + --group-add 才拿得到。拿不到不阻断构建（降级 TCG），
# 但状态必须显式传给容器与报告 —— 否则以后有人拿 TCG 的启动时间跟 KVM 的比较。
kvm_device="${YP_KVM_DEVICE:-/dev/kvm}"
kvm_status="ok"
kvm_reason=""
kvm_gid=""
if [[ ! -e "${kvm_device}" ]]; then
    kvm_status="unavailable"
    kvm_reason="宿主无 ${kvm_device}"
else
    kvm_gid="$(stat -c '%g' "${kvm_device}" 2>/dev/null || true)"
    if [[ -z "${kvm_gid}" ]]; then
        kvm_status="unavailable"
        kvm_reason="${kvm_device} 属组未知"
    fi
fi

if [[ "${mode}" == check ]]; then
    printf 'RELEASE=%s\nVARIANT=%s\nMACHINE=%s\nDISTRO=%s\nIMAGE=%s\nTAG=%s\n' \
        "${release}" "${variant}" "${machine}" "${DISTRO}" "${IMAGE}" "${TAG}"
    printf 'Resolved image: %s\nHost uid/gid: %s:%s\nDL_DIR=%s\nSSTATE_DIR=%s\n' \
        "${resolved_image}" "${host_uid}" "${host_gid}" "${dl_dir}" "${sstate_dir}"
    printf '%s\n' "${disk_output}"
    printf 'KVM=%s%s\n' "${kvm_status}" "${kvm_reason:+ (${kvm_reason})}"
    exit 0
fi

run_args=(
    run
    --rm
    --name "yocto-${RELEASE}-${VARIANT}"
    --label "yocto.release=${RELEASE}"
    --label "yocto.variant=${VARIANT}"
    --label "yocto.machine=${MACHINE}"
    --user "${host_uid}:${host_gid}"
    --workdir /work
    -v "${HOST_REPO_DIR}:/work"
    -v "${HOST_REPO_DIR}/work/home/.passwd:/etc/passwd:ro"
    -e "HOME=${home_dir}"
    # 这两个变量是给人工排查看的契约声明；真值由 kas/base.yml 决定，
    # bitbake 不从环境导入它们。
    -e "DL_DIR=${dl_dir}"
    -e "SSTATE_DIR=${sstate_dir}"
)

if [[ "${kvm_status}" == ok ]]; then
    run_args+=(--device "${kvm_device}" --group-add "${kvm_gid}")
fi
# 无论有没有 KVM 都要传：容器内的 qemu.sh 与报告靠它决定写 kvm 还是 tcg 口径。
run_args+=(-e "YP_KVM=${kvm_status}")

if [[ -S /var/run/docker.sock ]]; then
    run_args+=(
        -v /var/run/docker.sock:/var/run/docker.sock
        --group-add "$(stat -c '%g' /var/run/docker.sock)"
    )
fi

# 嵌套模式只使用显式透传的宿主路径，不探测容器内的 CLI 或插件目录。
host_docker="${WB_HOST_DOCKER_BIN:-}"
if [[ -z "${host_docker}" && -z "${WB_HOST_REPO_DIR:-}" ]]; then
    host_docker="$(command -v docker 2>/dev/null || true)"
fi
if [[ -n "${host_docker}" ]]; then
    run_args+=(-v "${host_docker}:/usr/local/bin/docker:ro")
fi

plugin_dir="${WB_HOST_DOCKER_PLUGIN_DIR:-}"
if [[ -z "${plugin_dir}" && -z "${WB_HOST_REPO_DIR:-}" ]]; then
    for candidate in /usr/libexec/docker/cli-plugins /usr/lib/docker/cli-plugins; do
        if [[ -d "${candidate}" ]]; then
            plugin_dir="${candidate}"
            break
        fi
    done
fi
if [[ -n "${plugin_dir}" ]]; then
    run_args+=(-v "${plugin_dir}:/usr/local/lib/docker/cli-plugins:ro")
fi

if [[ -n "${WB_HOST_REPO_DIR:-}" && -z "${host_docker}" ]]; then
    log_info "嵌套模式且未透传宿主 docker 路径，跳过 CLI 挂载"
fi

if [[ "${mode}" == dry-run ]]; then
    printf 'docker'
    printf ' %q' "${run_args[@]}" "${resolved_image}"
    if ((${#command_args[@]} > 0)); then
        printf ' %q' "${command_args[@]}"
    else
        printf ' %q' bash
    fi
    printf '\n'
    exit 0
fi

mkdir -p \
    "$(work_dir src)" \
    "$(work_dir build "${release}")/${variant}" \
    "$(work_dir artifacts "${release}")/${variant}" \
    "$(work_dir downloads)" \
    "$(work_dir sstate)" \
    "${ROOT_DIR}/work/home/${release}"

if ((pull_image)); then
    docker pull "${resolved_image}"
fi

passwd_base="$(mktemp "${passwd_file}.XXXXXX")"
trap 'rm -f -- "${passwd_base}" "${passwd_base}.mapped"' EXIT
docker run --rm "${resolved_image}" cat /etc/passwd >"${passwd_base}"
# Remove UID aliases as well so getpwuid always resolves to builder.
awk -F: -v uid="${host_uid}" -v gid="${host_gid}" -v home="${home_dir}" '
    $1 != "builder" && $3 != uid { print }
    END { printf "builder:x:%s:%s:builder:%s:/bin/bash\n", uid, gid, home }
' "${passwd_base}" >"${passwd_base}.mapped"
chmod 644 "${passwd_base}.mapped"
mv -- "${passwd_base}.mapped" "${passwd_file}"
rm -f -- "${passwd_base}"
trap - EXIT

tty_args=()
if [[ -t 0 && -t 1 ]]; then
    tty_args=(-it)
fi
if ((${#command_args[@]} > 0)); then
    exec docker "${run_args[@]}" "${tty_args[@]}" "${resolved_image}" "${command_args[@]}"
fi
exec docker "${run_args[@]}" "${tty_args[@]}" "${resolved_image}" bash
