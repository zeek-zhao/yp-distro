#!/usr/bin/env bash
# =============================================================================
# scripts/wf3.sh — WF3（远程 AI CLI）开发方式的运行框架
#
# 分工：WorkBuddy 写任务卡（tasks/<ID>.md）→ 本脚本在 tmux 里唤起容器内的
# GitHub Copilot CLI 执行 → 人工可随时 attach 干预 → WorkBuddy 验收并提交。
#
# 用法：
#   scripts/wf3.sh start <TASK-ID>     起 tmux 会话，copilot 交互式执行任务卡
#   scripts/wf3.sh run <TASK-ID>       非交互一次性执行（日志落 logs/，适合 CI）
#   scripts/wf3.sh list                列出所有 wf3 会话
#   scripts/wf3.sh attach <TASK-ID>    接入会话（人工干预/观察）
#   scripts/wf3.sh log <TASK-ID>       跟踪会话输出日志
#   scripts/wf3.sh stop <TASK-ID>      结束会话
#   scripts/wf3.sh clean               清理所有已结束的 wf3 会话
#
# 约定：
#   - 会话名 wf3-<TASK-ID>，日志 logs/wf3-<TASK-ID>.log
#   - 任务卡放 tasks/<TASK-ID>.md，模板见 tasks/_TEMPLATE.md
#   - 只清理 wf3- 前缀的会话，不碰机器上其他人的 tmux
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="${ROOT_DIR}/tasks"
LOG_DIR="${ROOT_DIR}/logs"
PREFIX="wf3-"

# copilot 参数，可用环境变量覆盖
COPILOT_MODEL="${WF3_MODEL:-auto}"
COPILOT_EXTRA="${WF3_COPILOT_ARGS:-}"

log() { printf '[wf3] %s\n' "$*"; }
die() {
    printf '[wf3] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法：
  scripts/wf3.sh start <TASK-ID>     起 tmux 会话，copilot 交互式执行任务卡
  scripts/wf3.sh run <TASK-ID>       非交互一次性执行（日志落 logs/）
  scripts/wf3.sh list                列出所有 wf3 会话
  scripts/wf3.sh attach <TASK-ID>    接入会话
  scripts/wf3.sh log <TASK-ID>       跟踪输出日志
  scripts/wf3.sh stop <TASK-ID>      结束会话
  scripts/wf3.sh clean               清理已结束的 wf3 会话

任务卡：tasks/<TASK-ID>.md（模板 tasks/_TEMPLATE.md）
环境变量：WF3_MODEL（默认 auto）、WF3_COPILOT_ARGS（追加给 copilot 的参数）
EOF
}

session_name() { printf '%s%s' "${PREFIX}" "$1"; }

require_tmux() {
    command -v tmux >/dev/null 2>&1 || die "未安装 tmux"
}

require_task() {
    local id="$1" card="${TASK_DIR}/$1.md"
    [[ -n "${id}" ]] || die "缺少 TASK-ID"
    [[ -f "${card}" ]] || die "任务卡不存在：${card}（模板见 tasks/_TEMPLATE.md）"
}

session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

###############################################################################
# 动作
###############################################################################
do_start() {
    local id="$1" sess
    sess="$(session_name "${id}")"
    require_tmux
    require_task "${id}"
    mkdir -p "${LOG_DIR}"

    if session_exists "${sess}"; then
        die "会话已存在：${sess}（先 scripts/wf3.sh stop ${id}）"
    fi

    # copilot 交互模式；--trust-folder 免去每次的目录信任确认
    # 外层 sleep 让 pane 在 copilot 退出后仍保留，便于事后查看输出
    local inner
    inner="cd '${ROOT_DIR}' && bash scripts/dev.sh copilot --model '${COPILOT_MODEL}' --trust-folder ${COPILOT_EXTRA} -i \"\$(cat '${TASK_DIR}/${id}.md')\"; echo; echo '[wf3] copilot 已退出，pane 保留供查看；Ctrl-b d 脱离，scripts/wf3.sh stop ${id} 结束'; sleep 86400"

    tmux new-session -d -s "${sess}" -x 200 -y 50 -c "${ROOT_DIR}" "${inner}"
    tmux set-option -t "${sess}" remain-on-exit on >/dev/null
    tmux pipe-pane -t "${sess}" -o "cat >> '${LOG_DIR}/wf3-${id}.log'"

    log "已启动 ${sess}"
    log "  任务卡：tasks/${id}.md"
    log "  日志  ：logs/wf3-${id}.log"
    log "  接入  ：scripts/wf3.sh attach ${id}"
}

do_run() {
    local id="$1"
    require_task "${id}"
    mkdir -p "${LOG_DIR}"
    log "非交互执行 tasks/${id}.md → logs/wf3-${id}.log"
    # shellcheck disable=SC2086  # COPILOT_EXTRA 需按空格分词
    bash "${ROOT_DIR}/scripts/dev.sh" copilot \
        --model "${COPILOT_MODEL}" \
        --trust-folder ${COPILOT_EXTRA} \
        -p "$(cat "${TASK_DIR}/${id}.md")" 2>&1 | tee -a "${LOG_DIR}/wf3-${id}.log"
}

do_list() {
    require_tmux
    local out
    out="$(tmux ls 2>/dev/null | grep "^${PREFIX}" || true)"
    if [[ -z "${out}" ]]; then
        log "无 wf3 会话"
        return 0
    fi
    printf '%s\n' "${out}"
}

do_attach() {
    local sess
    sess="$(session_name "$1")"
    require_tmux
    session_exists "${sess}" || die "会话不存在：${sess}"
    log "接入 ${sess}（脱离：Ctrl-b d）"
    exec tmux attach -t "${sess}"
}

do_log() {
    local f="${LOG_DIR}/wf3-$1.log"
    [[ -f "${f}" ]] || die "日志不存在：${f}"
    tail -n 100 -f "${f}"
}

do_stop() {
    local sess
    sess="$(session_name "$1")"
    require_tmux
    session_exists "${sess}" || die "会话不存在：${sess}"
    tmux kill-session -t "${sess}"
    log "已结束 ${sess}"
}

do_clean() {
    require_tmux
    local n=0
    while read -r sess _; do
        [[ -n "${sess:-}" ]] || continue
        tmux kill-session -t "${sess}" 2>/dev/null && n=$((n + 1))
    done < <(tmux ls 2>/dev/null | grep "^${PREFIX}" || true)
    log "清理了 ${n} 个会话"
}

###############################################################################
# 主流程
###############################################################################
case "${1:-}" in
    start)
        do_start "${2:-}"
        ;;
    run)
        do_run "${2:-}"
        ;;
    list | ls)
        do_list
        ;;
    attach)
        do_attach "${2:-}"
        ;;
    log)
        do_log "${2:-}"
        ;;
    stop)
        do_stop "${2:-}"
        ;;
    clean)
        do_clean
        ;;
    -h | --help | help | "")
        usage
        ;;
    *)
        die "未知子命令：$1（--help 查看用法）"
        ;;
esac
