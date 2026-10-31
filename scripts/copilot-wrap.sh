#!/usr/bin/env bash
# =============================================================================
# scripts/copilot-wrap.sh — 容器内 copilot 启动包装（保证走 OAuth）
#
# 唯一目的：让 copilot 使用 OAuth 登录态（~/.copilot/config.json 里的 gho_ token），
# 不被 PAT 类环境变量静默覆盖。
#
# 为什么需要这一层：
#   copilot login 的凭证优先级是
#       COPILOT_GITHUB_TOKEN > GH_TOKEN > GITHUB_TOKEN > OAuth 登录态
#   只要容器环境里存在任何一个 PAT，copilot 就直接用它，**不报错、不提示**。
#   表面上"能跑"，实际上 OAuth 被绕过了。而 scripts/dev.sh 为了容器内的 gh CLI
#   会透传 GH_TOKEN / GITHUB_TOKEN，所以 copilot 必须在自己的进程里先 unset。
#
# 为什么在进程内 unset 而不是"不传"：
#   docker run -e 传进去的变量对所有进程可见，dev.sh 无法只对 copilot 隐藏。
#   在本进程 unset 后 exec，既不影响 gh（它是另一个进程），也确实让 copilot 看不到。
#
# 副作用（有意为之）：copilot 派生的所有 shell 工具子进程同样看不到这三个变量，
#   因此 AI 执行 `env` / `set` 之类命令时不会把 PAT 打印进 logs/wf3-*.log。
#
# 用法：由 scripts/wf3.sh 调用，不直接使用
#   bash scripts/dev.sh bash scripts/copilot-wrap.sh -p "<任务卡内容>" ...
# =============================================================================
set -u

unset GH_TOKEN GITHUB_TOKEN COPILOT_GITHUB_TOKEN

# 登录态缺失时给出明确的手动授权指引，不要让 copilot 自己弹交互提示
# （wf3 跑在 tmux 里，交互提示会一直挂着不退出，看起来像卡死）
if [[ ! -s "${HOME}/.copilot/config.json" ]] \
   || ! grep -qs '"authTokens"' "${HOME}/.copilot/config.json"; then
    cat >&2 <<'EOF'
[copilot-wrap] 未检测到 OAuth 登录态（~/.copilot/config.json 无 authTokens）。

  需要人工授权（脚本不会代替你确认）：

      scripts/dev.sh copilot login --device-code

  copilot 会打印一次性设备码，浏览器打开 https://github.com/login/device
  输入后确认即可。凭证写入 .devhome/.copilot/config.json 持久化，
  之后所有 wf3 任务复用。
EOF
    exit 3
fi

exec copilot "$@"
