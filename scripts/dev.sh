#!/usr/bin/env bash
# =============================================================================
# scripts/dev.sh — yocto-dev 容器唯一入口
#
# 开发环境全部在容器内：宿主机（215）只提供 docker 与 git，不装 bats /
# 静态检查工具（shellcheck / shfmt）、gh、node 也都装在这里，宿主机保持干净。
# 所有 lint、BATS、review、AI CLI 都跑在容器里。
#
# 用法：
#   scripts/dev.sh --build            构建/更新镜像（按当前用户 UID/GID）
#   scripts/dev.sh --check            打印容器内工具版本表（含挂载的宿主 docker）
#   scripts/dev.sh                    进入交互 shell
#   scripts/dev.sh <cmd> [args...]    在容器内执行命令（如 make lint）
#
# 环境变量：
#   YOCTO_DEV_IMAGE   镜像名，默认 yocto-dev:local
#   YOCTO_DEV_PULL    非空时 --build 前先 --pull 拉 base
#   GH_TOKEN          可选，透传给容器内的 gh / copilot
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${YOCTO_DEV_IMAGE:-yocto-dev:local}"
DOCKERFILE="${ROOT_DIR}/docker/dev/Dockerfile"
BUILD_CTX="$(dirname "${DOCKERFILE}")"

log() { printf '[dev] %s\n' "$*"; }
die() {
    printf '[dev] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法：
  scripts/dev.sh --build            构建/更新镜像（按当前用户 UID/GID）
  scripts/dev.sh --check            打印容器内工具版本表（含挂载的宿主 docker）
  scripts/dev.sh                    进入交互 shell
  scripts/dev.sh <cmd> [args...]    在容器内执行命令（如 make lint）

环境变量：
  YOCTO_DEV_IMAGE   镜像名，默认 yocto-dev:local
  YOCTO_DEV_PULL    非空时 --build 前先 --pull 拉 base
  GH_TOKEN          可选，透传给容器内的 gh / copilot
EOF
}

image_exists() {
    docker image inspect "${IMAGE}" >/dev/null 2>&1
}

###############################################################################
# 容器内直通
#
# WF3 的 copilot 会话本身就跑在本镜像里；它若再调 scripts/dev.sh，宿主 docker
# 会把容器内路径（/work）当成宿主路径去挂载，结果挂成空目录、命令全部失败。
# 检测到已在 dev 容器内时直接本地执行，不再套一层 docker run。
#
# 这也是任务卡验收命令能两端通用的原因：宿主侧 `dev.sh shellcheck ...` 进容器，
# 容器侧同一条命令直接跑，行为一致。
###############################################################################
in_dev_container() {
    [[ -f /.dockerenv ]] || return 1
    [[ -d /work ]] || return 1
    case "${PWD}" in
        /work | /work/*) return 0 ;;
        *) return 1 ;;
    esac
}

###############################################################################
# docker run 公共参数
###############################################################################
build_run_args() {
    RUN_ARGS=(
        --rm
        -v "${ROOT_DIR}:/work"
        -e "WB_HOST_REPO_DIR=${ROOT_DIR}"
        -w /work
    )

    # ── docker socket：容器内可 build/pull（L2 演练）──────────────────────
    if [[ -S /var/run/docker.sock ]]; then
        RUN_ARGS+=(
            -v /var/run/docker.sock:/var/run/docker.sock
            --group-add "$(stat -c '%g' /var/run/docker.sock)"
        )
    else
        log "警告：/var/run/docker.sock 不存在，容器内无法使用 docker"
    fi

    # ── docker CLI：挂载宿主二进制（宿主为纯 libc 依赖，可直接跑）─────────
    local host_docker=""
    host_docker="$(command -v docker 2>/dev/null || true)"
    if [[ -n "${host_docker}" ]]; then
        RUN_ARGS+=(-v "${host_docker}:/usr/local/bin/docker:ro")
        RUN_ARGS+=(-e "WB_HOST_DOCKER_BIN=${host_docker}")
        local plugin_dir
        for plugin_dir in /usr/libexec/docker/cli-plugins /usr/lib/docker/cli-plugins; do
            if [[ -d "${plugin_dir}" ]]; then
                RUN_ARGS+=(-v "${plugin_dir}:/usr/local/lib/docker/cli-plugins:ro")
                RUN_ARGS+=(-e "WB_HOST_DOCKER_PLUGIN_DIR=${plugin_dir}")
                break
            fi
        done
    else
        log "警告：宿主未找到 docker CLI，容器内无 docker 命令"
    fi

    # ── 仓库级 SSH 私钥：容器内路径是 /work/.ssh/id_rsa，与宿主绝对路径不同，
    #    用 GIT_SSH_COMMAND 覆盖（优先级高于 git config core.sshCommand）────
    if [[ -f "${ROOT_DIR}/.ssh/id_rsa" ]]; then
        RUN_ARGS+=(
            -e "GIT_SSH_COMMAND=ssh -i /work/.ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        )
    fi

    # ── 持久 HOME：copilot / gh 的登录凭证要跨容器存活 ────────────────────
    # 用仓库内目录而非 docker volume，属主天然与宿主 UID 一致，无需 chown。
    # 认证只需做一次，凭证落在 .devhome/.copilot（或 .config/gh），进 .gitignore。
    local devhome="${ROOT_DIR}/.devhome"
    mkdir -p "${devhome}"
    RUN_ARGS+=(-v "${devhome}:/home/$(id -un)")
    # 注意：函数末尾不能用 `[[ ... ]] && cmd` 形式，set -e 下条件为假会让整个脚本退出
    if [[ -n "${GH_TOKEN:-}" ]]; then
        RUN_ARGS+=(-e "GH_TOKEN=${GH_TOKEN}")
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        RUN_ARGS+=(-e "GITHUB_TOKEN=${GITHUB_TOKEN}")
    fi
    return 0
}

###############################################################################
# 动作
###############################################################################
do_build() {
    [[ -f "${DOCKERFILE}" ]] || die "Dockerfile 不存在：${DOCKERFILE}"
    log "构建 ${IMAGE}（UID=$(id -u) GID=$(id -g) USER=$(id -un)）"
    docker build \
        ${YOCTO_DEV_PULL:+--pull} \
        -f "${DOCKERFILE}" \
        --build-arg "DEV_UID=$(id -u)" \
        --build-arg "DEV_GID=$(id -g)" \
        --build-arg "DEV_USER=$(id -un)" \
        -t "${IMAGE}" \
        "${BUILD_CTX}"
    log "构建完成：${IMAGE}"
}

do_check() {
    image_exists || die "镜像 ${IMAGE} 不存在，先跑 scripts/dev.sh --build"
    echo "=== 镜像内工具 ==="
    docker run --rm "${RUN_ARGS[@]}" "${IMAGE}" cat /etc/yocto-dev-versions
    echo "=== 运行时挂载的宿主 docker ==="
    docker run --rm "${RUN_ARGS[@]}" "${IMAGE}" bash -lc \
        'docker --version 2>/dev/null || echo "docker: 未挂载"'
    docker run --rm "${RUN_ARGS[@]}" "${IMAGE}" bash -lc \
        'docker buildx version 2>/dev/null || echo "buildx: 未挂载"'
    echo "=== 挂载点 ==="
    printf '  repo  : %s -> /work\n' "${ROOT_DIR}"
    if [[ -S /var/run/docker.sock ]]; then
        printf '  socket: /var/run/docker.sock (gid %s)\n' "$(stat -c '%g' /var/run/docker.sock)"
    fi
    return 0
}

###############################################################################
# 主流程
###############################################################################
# 已在 dev 容器内（如 WF3 的 copilot 会话）：直接本地执行，见 in_dev_container 注释
# 必须放在 build_run_args 之前：容器内无需构建 docker 参数，否则会打出
# "docker.sock 不存在 / 未找到 docker CLI" 这类与实际情况无关的警告
if in_dev_container; then
    case "${1:-}" in
        -h | --help | help)
            usage
            exit 0
            ;;
        --build | --check)
            printf 'dev.sh: 已在 dev 容器内，%s 只能在宿主机执行\n' "${1}" >&2
            exit 2
            ;;
        "")
            printf 'dev.sh: 已在 dev 容器内，直接使用 bash 即可\n' >&2
            exit 0
            ;;
        *)
            exec "$@"
            ;;
    esac
fi

build_run_args

case "${1:-}" in
    -h | --help | help)
        usage
        ;;
    --build)
        do_build
        do_check
        ;;
    --check)
        do_check
        ;;
    "")
        image_exists || {
            log "镜像不存在，自动构建"
            do_build
        }
        tty_flag=()
        [[ -t 0 && -t 1 ]] && tty_flag=(-it)
        log "进入容器（镜像 ${IMAGE}，仓库 ${ROOT_DIR}）"
        exec docker run "${RUN_ARGS[@]}" "${tty_flag[@]}" "${IMAGE}" bash
        ;;
    *)
        image_exists || {
            log "镜像不存在，自动构建"
            do_build
        }
        # 交互式命令（如 copilot login）需要 TTY，tmux pane 里同样满足 -t 0/-t 1
        tty_flag=()
        [[ -t 0 && -t 1 ]] && tty_flag=(-it)
        exec docker run "${RUN_ARGS[@]}" "${tty_flag[@]}" "${IMAGE}" "$@"
        ;;
esac
