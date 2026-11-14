#!/usr/bin/env bash
# =============================================================================
# scripts/ci/check-doc-links.sh — 文档引用存在性校验
#
# 文档管理审查（D2/D4）的 CI 化。三类引用必须真实存在，防死链防幻觉路径：
#   1. Markdown 内联链接 [text](path) —— 相对路径按所在文件解析
#   2. 反引号内的仓库路径（docs|config|scripts|layers|kas|tests|docker 开头）
#   3. 其中 docs/qa/ 归档路径单独打 [qa] 标签便于定位
#
# 显式跳过（写在这里而不是放开关，避免配置漂移）：
#   - http/https/mailto/纯锚点链接
#   - 含通配符或模板占位符的路径（* ? { } < >）—— 那是「模式」不是「文件」
#   - docs/08-tasks/archive/ 下的任务卡 —— 冻结的历史快照，按定义记录当时状态，
#     其死引用只做审查登记（见文档管理审查 D4），不随代码演进修
#   - 可选允许清单 scripts/ci/secret-scan.allow（secret-scan.sh 自带缺省行为）
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."

fail=0

note() {
    printf '::error::%s\n' "$1"
    fail=1
}

# ---- 1) Markdown 内联链接 ----
while IFS= read -r -d '' f; do
    dir="$(dirname "${f#./}")"
    # ](target) 形态；target 里允许 #anchor。空 target / 纯锚点由 case 跳过
    while IFS= read -r t; do
        case "${t}" in
            ''|http://*|https://*|mailto:*|'#'*) continue ;;
        esac
        t="${t%%#*}"
        [ -n "${t}" ] || continue
        if [ ! -e "${dir}/${t}" ]; then
            note "[md-link] ${f}: 链接目标不存在 -> ${t}"
        fi
    done < <(grep -oE '\]\([^)]*\)' "${f}" 2>/dev/null \
             | sed -E 's/^\]\(//; s/\)$//' | sort -u)
done < <(find . -path ./.git -prune -o -path ./docs/08-tasks/archive -prune -o -name '*.md' -print0)

# ---- 2)+3) 反引号内的仓库路径 ----
# 只取路径字符集，遇到通配符/模板字符整条跳过（见文件头说明）
while IFS= read -r -d '' f; do
    while IFS= read -r t; do
        t="${t#\`}"; t="${t%\`}"
        case "${t}" in
            *[\*\?\{\}\<\>]*|*\$\(*) continue ;;
            # 可选允许清单：允许不存在（secret-scan.sh:24 自带 -f 判断）
            scripts/ci/secret-scan.allow) continue ;;
        esac
        # 去掉句尾跟的标点混入（grep 字符集已限制，这里兜底）
        if [ ! -e "${t}" ]; then
            case "${t}" in
                docs/qa/*) tag="[qa]" ;;
                *) tag="[repo-path]" ;;
            esac
            note "${tag} ${f}: 引用路径不存在 -> ${t}"
        fi
    done < <(grep -hoE '`(docs|config|scripts|layers|kas|tests|docker)/[A-Za-z0-9_./-]+`' "${f}" 2>/dev/null \
             | sort -u)
done < <(find . -path ./.git -prune -o -path ./docs/08-tasks/archive -prune -o \( -name '*.md' -o -name '*.sh' -o -name '*.yml' \) -print0)

if [ "${fail}" -ne 0 ]; then
    echo "文档引用校验未通过：见上方 ::error 行"
    exit 1
fi
echo "文档引用校验通过"
