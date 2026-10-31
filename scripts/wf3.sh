#!/usr/bin/env bash
# =============================================================================
# scripts/wf3.sh — WF3（远程 AI CLI）开发方式的运行框架
#
# 分工：WorkBuddy 写任务卡（tasks/<ID>.md）→ 本脚本在 tmux 里唤起容器内的
# GitHub Copilot CLI 执行 → 人工可随时 attach 干预 → WorkBuddy 验收并提交。
#
# 用法：
#   scripts/wf3.sh start <TASK-ID>     起 tmux 会话，copilot -p 执行任务卡后退出
#   scripts/wf3.sh chat <TASK-ID>      起 tmux 会话，copilot -i 执行任务卡后停留可对话
#   scripts/wf3.sh run <TASK-ID>       前台非交互执行（日志落 logs/，适合 CI）
#   scripts/wf3.sh list                列出所有 wf3 会话
#   scripts/wf3.sh attach <TASK-ID>    接入会话（人工干预/观察）
#   scripts/wf3.sh log <TASK-ID>       跟踪会话输出日志
#   scripts/wf3.sh stop <TASK-ID>      结束会话
#   scripts/wf3.sh clean               清理所有已结束的 wf3 会话
#   scripts/wf3.sh tokens [参数...]    token / AI credit 台账与报表（透传给 wf3-tokens.sh）
#
# 约定：
#   - 会话名 wf3-<TASK-ID>，日志 logs/wf3-<TASK-ID>.log
#   - 任务卡放 tasks/<TASK-ID>.md，模板见 tasks/_TEMPLATE.md
#   - 只清理 wf3- 前缀的会话，不碰机器上其他人的 tmux
#   - start 用 -p（跑完退出，rc 即结果，便于 WorkBuddy 按验收标准判定）
#   - chat 用 -i（跑完任务卡后保持会话，可 attach 继续对话纠正）
#   - 两者都传 --allow-all-tools：容器内需要自动执行 shellcheck/bats/git，
#     无人值守时不能停在工具确认上；容器与仓库是隔离环境，风险可控
#
# AI 凭证与用量：
#   - copilot 一律经 scripts/copilot-wrap.sh 启动。wrapper 会 unset
#     GH_TOKEN / GITHUB_TOKEN / COPILOT_GITHUB_TOKEN，强制走 ~/.copilot 的
#     OAuth 登录态；否则 dev.sh 为 gh 透传的 PAT 会被 copilot 静默优先采用。
#   - 登录态缺失时 wrapper 直接退出码 3 并打印手动授权命令，不会挂住会话。
#     人工授权（脚本不代确认）：scripts/dev.sh copilot login --device-code
#   - 每次任务用 --usage-output-file 落 logs/usage-<TASK-ID>.json，
#     退出后自动调 wf3-tokens.sh ingest 追加 logs/token-usage.tsv（幂等）。
#     看报表：scripts/wf3.sh tokens
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_DIR="${ROOT_DIR}/tasks"
LOG_DIR="${ROOT_DIR}/logs"
PREFIX="wf3-"

# 容器内挂载点恒为 /work（dev.sh 的 -v ROOT_DIR:/work -w /work）：
# wrapper 与 usage 文件都用容器内绝对路径，避免依赖 copilot 进程的 cwd
CT_WRAP="/work/scripts/copilot-wrap.sh"
ct_usage_file() { printf '/work/logs/usage-%s.json' "$1"; }

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
  scripts/wf3.sh start <TASK-ID>     起 tmux 会话，copilot -p 执行任务卡后退出
  scripts/wf3.sh chat <TASK-ID>      起 tmux 会话，copilot -i 执行任务卡后停留可对话
  scripts/wf3.sh run <TASK-ID>       前台非交互执行（日志落 logs/）
  scripts/wf3.sh list                列出所有 wf3 会话
  scripts/wf3.sh attach <TASK-ID>    接入会话
  scripts/wf3.sh log <TASK-ID>       跟踪输出日志
  scripts/wf3.sh stop <TASK-ID>      结束会话
  scripts/wf3.sh clean               清理已结束的 wf3 会话
  scripts/wf3.sh tokens [参数...]    token / AI credit 台账与报表
                                     （--task ID / --issue N / --last N / --json）

任务卡：tasks/<TASK-ID>.md（模板 tasks/_TEMPLATE.md）
环境变量：WF3_MODEL（默认 auto）、WF3_COPILOT_ARGS（追加给 copilot 的参数）

AI 凭证：copilot 一律走 OAuth（~/.copilot）。登录态缺失时给出授权命令：
  scripts/dev.sh copilot login --device-code
用量台账：logs/token-usage.tsv；报表 scripts/wf3.sh tokens
EOF
}

session_name() { printf '%s%s' "${PREFIX}" "$1"; }

require_tmux() {
    command -v tmux >/dev/null 2>&1 || die "未安装 tmux"
}

# resolve_task <TASK-ID> — 输出任务卡绝对路径
# 同时支持 tasks/<ID>.md 与 tasks/<ID>-<slug>.md（模板示例即后者）
# 匹配到多个时报错，避免 AI 读错卡
resolve_task() {
    local id="$1" f hits=()
    [[ -n "${id}" ]] || die "缺少 TASK-ID"
    for f in "${TASK_DIR}/${id}.md" "${TASK_DIR}/${id}"-*.md; do
        [[ -f "${f}" ]] && hits+=("${f}")
    done
    ((${#hits[@]} > 0)) || die "任务卡不存在：${TASK_DIR}/${id}.md（模板见 tasks/_TEMPLATE.md）"
    ((${#hits[@]} == 1)) || die "任务卡匹配到多个，请用具名 ID：${hits[*]}"
    printf '%s\n' "${hits[0]}"
}

require_task() { resolve_task "$1" >/dev/null; }

session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

###############################################################################
# 动作
###############################################################################
# spawn_session <TASK-ID> <run|chat>
#   run  → copilot -p：执行完任务卡即退出，退出码即结果（WorkBuddy 验收用）
#   chat → copilot -i：执行完任务卡后保持会话，可 attach 继续对话纠正
spawn_session() {
    local id="$1" mode="$2" sess inner flag card
    sess="$(session_name "${id}")"
    require_tmux
    card="$(resolve_task "${id}")"
    mkdir -p "${LOG_DIR}"

    if session_exists "${sess}"; then
        die "会话已存在：${sess}（先 scripts/wf3.sh stop ${id}）"
    fi

    case "${mode}" in
        run) flag="-p" ;;
        chat) flag="-i" ;;
        *) die "未知模式：${mode}" ;;
    esac

    # --trust-folder 免目录信任确认；--allow-all-tools 让容器内的 shellcheck /
    # bats / git 无需人工批准（无人值守时不能停在工具确认上）
    # 经 copilot-wrap.sh 启动：清掉 PAT 类变量，强制走 OAuth 登录态
    # --usage-output-file 落用量 JSON，退出后 ingest 进台账（幂等）
    # 外层 sleep 让 pane 在 copilot 退出后仍保留，便于事后查看输出
    inner="cd '${ROOT_DIR}' && bash scripts/dev.sh bash '${CT_WRAP}' --model '${COPILOT_MODEL}' --trust-folder --allow-all-tools --usage-output-file '$(ct_usage_file "${id}")' ${COPILOT_EXTRA} ${flag} \"\$(cat '${card}')\"; rc=\$?; bash scripts/wf3-tokens.sh ingest '${id}' \"\$rc\"; bash scripts/wf3-tokens.sh publish; echo; echo \"[wf3] copilot 退出，rc=\${rc}\"; echo '[wf3] 日志 logs/wf3-${id}.log；用量 scripts/wf3.sh tokens --task ${id}；结束会话 scripts/wf3.sh stop ${id}'; sleep 86400"

    tmux new-session -d -s "${sess}" -x 200 -y 50 -c "${ROOT_DIR}" "${inner}"
    tmux set-option -t "${sess}" remain-on-exit on >/dev/null
    tmux pipe-pane -t "${sess}" -o "cat >> '${LOG_DIR}/wf3-${id}.log'"

    log "已启动 ${sess}（模式 ${mode}）"
    log "  任务卡：${card#"${ROOT_DIR}"/}"
    log "  日志  ：logs/wf3-${id}.log"
    log "  接入  ：scripts/wf3.sh attach ${id}"
}

do_start() { spawn_session "$1" run; }

do_chat() { spawn_session "$1" chat; }

do_run() {
    local id="$1" card rc
    card="$(resolve_task "${id}")"
    mkdir -p "${LOG_DIR}"
    log "前台非交互执行 ${card#"${ROOT_DIR}"/} → logs/wf3-${id}.log"
    set +e
    # shellcheck disable=SC2086  # COPILOT_EXTRA 需按空格分词
    bash "${ROOT_DIR}/scripts/dev.sh" bash "${CT_WRAP}" \
        --model "${COPILOT_MODEL}" \
        --trust-folder \
        --allow-all-tools \
        --usage-output-file "$(ct_usage_file "${id}")" ${COPILOT_EXTRA} \
        -p "$(cat "${card}")" 2>&1 | tee -a "${LOG_DIR}/wf3-${id}.log"
    rc="${PIPESTATUS[0]}"
    set -e
    bash "${ROOT_DIR}/scripts/wf3-tokens.sh" ingest "${id}" "${rc}" || true
    # 顺手刷新仓库里的台账与看板：metrics/token-usage.tsv + docs/tokens.html
    # 只写文件、不提交 —— 提交时机由人决定，避免每个任务一条 commit 噪音
    bash "${ROOT_DIR}/scripts/wf3-tokens.sh" publish || true
    return "${rc}"
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
    chat)
        do_chat "${2:-}"
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
    tokens)
        shift
        exec bash "${ROOT_DIR}/scripts/wf3-tokens.sh" "$@"
        ;;
    -h | --help | help | "")
        usage
        ;;
    *)
        die "未知子命令：$1（--help 查看用法）"
        ;;
esac
