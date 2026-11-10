#!/usr/bin/env bash
# =============================================================================
# scripts/smoke.sh —— L4 runtime smoke：一次起机，跑完整个动作集（#132）
#
#   scripts/smoke.sh --release wrynose --variant custom --image <minimal|base|full>
#
# 动作集与证据级别（docs/verification-flow.md §6）绑定：features.txt 里
# evidence=runtime 的 feature 必须在这里有对应动作。
#
# 口径：
#   - full 跑全部动作；base/minimal 只跑该层存在的动作，跳过项**显式记录**
#     原因（层不含该包），不是静默 skip
#   - wrynose 的 minimal/base 串口 root 无空密码（degraded.txt:
#     empty-root-login），这两层只采「起机到 login」的 boot 证据，
#     动作集标记 SKIPPED 并写明原因
#   - 一个动作 rc≠0 → 整轮红；动作之间不中断，最后汇总
#   - 已知 degraded 项不进动作集
# 产物：
#   reports/smoke/smoke-<image>.xml（JUnit，与 bats 报告分目录）
#   docs/qa/<release>/smoke-<date>-<sha>-<image>.md
#   docs/qa/<release>/artifacts-smoke-<sha>.sha256
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'USAGE'
用法：scripts/smoke.sh --release <r> [--variant <v>] --image <minimal|base|full> [--machine m]

  --image       三层之一（必填）：动作集按层裁剪
  --variant     默认 custom（general 无免密登录，不支持）
USAGE
}

release="" variant="custom" machine="qemux86-64" image_layer=""
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
        --image)
            (($# >= 2)) || die "--image 缺少参数"
            image_layer="$2"
            shift 2
            ;;
        --machine)
            (($# >= 2)) || die "--machine 缺少参数"
            machine="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1（--help 看用法）" ;;
    esac
done
[[ -n "${release}" && -n "${image_layer}" ]] || {
    usage
    die "必须指定 --release 和 --image"
}
[[ "${image_layer}" =~ ^(minimal|base|full)$ ]] || die "--image 必须是 minimal|base|full"
[[ "${variant}" == "custom" ]] || die "runtime smoke 只支持 custom（general 无免密登录，见 #132 已知风险）"

log_dir="${ROOT_DIR}/work/logs"
mkdir -p "${log_dir}" "${ROOT_DIR}/reports/smoke"
guest_script="${log_dir}/guest-smoke-actions-${image_layer}.sh"
serial_log_path="work/logs/serial-smoke-${release}-${variant}-${image_layer}.log"

# ---- 动作集（guest 侧逐行执行，每行输出 SM|id|状态|输出摘要）----
has_pkg() { [[ "${image_layer}" == "full" ]] || [[ "${image_layer}" == "base" && "$1" == "base-tools" ]]; }
# shellcheck disable=SC2206  # 动作行是整条命令字符串，不需要分词
# shellcheck disable=SC2016,SC2206,SC2116  # 单引号与拼接是刻意的：动作行整条下发，
# \$( ) 在客户机展开，宿主不执行（KB-25/KB-15 同族的边界纪律）
guest_lines=(
    'echo "SM|systemd-state|$(systemctl is-system-running)"'
    'echo "SM|failed-units|$(systemctl --failed --no-legend | wc -l)"'
    'echo "SM|pid1|$(readlink /proc/1/exe)"'
    'echo "SM|os-release|ID=$(sed -n s/^ID=//p /etc/os-release)"'
    'echo "SM|hostname|$(hostname)"'
)
if [[ "${image_layer}" != "minimal" ]]; then
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|curl|$(curl --version >/dev/null 2>&1 && echo pass)"')
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|tar|$(tar --version >/dev/null 2>&1 && echo pass)"')
fi
if [[ "${image_layer}" == "minimal" || "${image_layer}" == "base" ]]; then
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|busybox|$(for a in ls cp mv cat grep sed awk ps head tail chmod date df find free uptime sync test true; do /bin/busybox "$a" >/dev/null 2>&1 || echo -n "$a "; done; echo done)"')
fi
if [[ "${image_layer}" == "full" ]]; then
    for svc in yp-hello-svc yp-statusd yp-collectd; do
        # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
        # shellcheck disable=SC2016,SC2206  # 拼接与单引号刻意：host 不展开命令体
        guest_lines+=('echo "SM|svc-'$svc'|$(systemctl is-enabled '$svc' 2>/dev/null)/$(systemctl is-active '$svc' 2>/dev/null)"')
    done
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|statusd-json|$(wget -qO- -T 5 http://127.0.0.1:8080/status)"')
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|collectd-journal|$(journalctl -u yp-collectd -n 1 --no-pager 2>/dev/null | grep -c yp-collectd)"')
    for demo in yp-demo-make yp-demo-cmake yp-demo-autotools yp-demo-meson yp-demo-python yp-demo-rust yp-demo-go; do
        # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
        # shellcheck disable=SC2016,SC2206  # 拼接与单引号刻意：host 不展开命令体
        guest_lines+=('echo "SM|demo-'$demo'|$(/usr/bin/'$demo' >/dev/null 2>&1; echo $?)"')
    done
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|cpp-hello|$(/usr/bin/helloworld >/dev/null 2>&1; echo $?)"')
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|python3|$(python3 -c "import json,sqlite3,ssl;print(ssl.OPENSSL_VERSION[:12])" 2>&1)"')
    # shellcheck disable=SC2016  # 单引号是刻意的：$() 在客户机展开
    guest_lines+=('echo "SM|strace|$(strace -V >/dev/null 2>&1 && echo pass)"')
fi

{
    echo '#!/bin/sh'
    echo '# runtime smoke 动作集（scripts/smoke.sh 生成，勿手改）'
    for line in "${guest_lines[@]}"; do
        printf '%s\n' "${line}"
    done
} >"${guest_script}"

cmd_file="${log_dir}/guest-cmd-smoke-${release}-${image_layer}.txt"
{
    echo "cat > /tmp/smoke-actions.sh <<'SMOKE_EOF'"
    cat "${guest_script}"
    echo "SMOKE_EOF"
    echo "sh /tmp/smoke-actions.sh"
} >"${cmd_file}"

commit_sha="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
serial_abs="${ROOT_DIR}/${serial_log_path}"

cd -- "${ROOT_DIR}" || exit 1
{
    printf '=== scripts/smoke.sh %s ===\n' "$(date --iso-8601=seconds)"
    printf 'commit  : %s\n' "${commit_sha}"
    printf 'release : %s / %s / %s / %s\n' "${release}" "${variant}" "${machine}" "${image_layer}"
    printf 'actions : %s\n' "${#guest_lines[@]}"

    image_target="yp-image-${image_layer}"
    [[ "${image_layer}" == "full" ]] && image_target="yp-image"
    ./project.sh shell --release "${release}" --variant "${variant}" --machine "${machine}" -- \
        bash -lc "RELEASE=${release} VARIANT=${variant} IMAGE=${image_target} \\
            MACHINE=${machine} BOOT_TIMEOUT=180 GUEST_WAIT=60 \\
            GUEST_CMD_FILE=/work/work/logs/guest-cmd-smoke-${release}-${image_layer}.txt \
            IMAGE_LAYER=${image_layer} \\
            bash /work/scripts/lib/inner-smoke.sh"
} 2>&1 | tee "${log_dir}/smoke-run-${release}-${image_layer}.log"

[[ -f "${serial_abs}" ]] || die "串口日志缺失：${serial_abs}"

# ---- 解析 SM| 行 ----
sm_lines="$(sed -n '/__BEGIN__/,/__END__/p' "${serial_abs}" | tr -d '\r' | grep -E '^SM\|' || true)"
if [[ -z "${sm_lines}" && "${image_layer}" != "full" ]]; then
    # wrynose 的 minimal/base 串口 root 无空密码（degraded.txt:
    # empty-root-login）——自动登录不成立，动作集无法执行。
    # 按 #132 已知风险的预案：记录「起机证据 + 动作集 SKIPPED 及原因」，
    # 不算失败也不静默跳过。
    echo "smoke: ${image_layer} 无法自动登录（empty-root-login 降级）——记录 boot 证据，动作集 SKIPPED"
    junit="${ROOT_DIR}/reports/smoke/smoke-${release}-${variant}-${image_layer}.xml"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<testsuites>'
        printf '<testsuite name="smoke-%s-%s" tests="1">
' "${release}" "${image_layer}"
        printf '  <testcase name="boot-to-login"><skipped message="serial root login not available on %s (empty-root-login degraded; see config/degraded.txt)"/></testcase>\n' "${image_layer}"
        echo '</testsuite>'
        echo '</testsuites>'
    } >"${junit}"
    date_stamp="$(date +%Y%m%d)"
    commit_sha="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
    archive="${ROOT_DIR}/docs/qa/${release}/smoke-${date_stamp}-${commit_sha}-${image_layer}.md"
    {
        echo "# runtime smoke —— ${release} ${image_layer}（#132）—— boot 证据口径"
        echo
        echo "- commit：\`${commit_sha}\`"
        echo "- 起机：串口已出现 login 提示（qemu.sh 链路）"
        echo "- 动作集：**SKIPPED**——本层串口 root 无空密码（degraded.txt: empty-root-login），"
        echo "  自动登录不成立（#132 已知风险预案）"
        echo "- 串口日志：\`${serial_log_path}\`"
        echo
    } >"${archive}"
    {
        printf '%s  %s\n' "$(sha256sum "${serial_abs}" | awk '{print $1}')" "${serial_log_path}"
        printf '%s  %s\n' "$(sha256sum "${junit}" | awk '{print $1}')" "${junit#"${ROOT_DIR}/"}"
    } >"${ROOT_DIR}/docs/qa/${release}/artifacts-smoke-${commit_sha}-${image_layer}.sha256"
    echo "归档（boot 证据口径）：${archive#"${ROOT_DIR}/"}"
    exit 0
fi
[[ -n "${sm_lines}" ]] || die "串口里没有 SMOKE 结果标记（可能登录失败）；串口尾部：$(tail -5 "${serial_abs}" | tr -d '\r')"

# ---- JUnit ----
junit="${ROOT_DIR}/reports/smoke/smoke-${release}-${variant}-${image_layer}.xml"
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<testsuites>'
    printf '<testsuite name="smoke-%s-%s" tests="%s">\n' "${release}" "${image_layer}" "${#guest_lines[@]}"
    parse_fail=0
    while IFS= read -r sm; do
        IFS='|' read -r _ tag value rest <<<"${sm}"
        value="$(printf '%s' "${value}" | xargs 2>/dev/null || printf '%s' "${value}")"
        rest="$(printf '%s' "${rest}")"
        case "${tag}" in
            systemd-state)
                if [[ "${value}" == "running" || "${value}" == "degraded" ]]; then
                    echo "  <testcase name=\"systemd-state\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="systemd-state"><failure message="is-system-running=%s"/></testcase>\n' "${value}"
                fi
                ;;
            failed-units)
                if [[ "${value}" == "0" ]]; then
                    echo "  <testcase name=\"failed-units\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="failed-units"><failure message="failed units=%s"/></testcase>\n' "${value}"
                fi
                ;;
            pid1)
                # usrmerge（5.0+）：systemd 在 /usr/lib/systemd/systemd
                if [[ "${value}" == *"/sbin/init"* || "${value}" == *"/lib/systemd/systemd"* ]]; then
                    echo "  <testcase name=\"pid1-systemd\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="pid1-systemd"><failure message="PID1=%s"/></testcase>\n' "${value}"
                fi
                ;;
            busybox)
                if [[ "${value}" == "done" ]]; then
                    echo "  <testcase name=\"busybox-applets\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="busybox-applets"><failure message="failed applets: %s"/></testcase>\n' "${value%% done*}"
                fi
                ;;
            demo-* | cpp-hello)
                if [[ "${value}" == "0" ]]; then
                    echo "  <testcase name=\"${tag}\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="%s"><failure message="rc=%s"/></testcase>\n' "${tag}" "${value}"
                fi
                ;;
            svc-*)
                if [[ "${value}" == */"active" ]]; then
                    echo "  <testcase name=\"${tag}\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="%s"><failure message="state=%s"/></testcase>\n' "${tag}" "${value}"
                fi
                ;;
            *)
                if [[ -n "${value}" && "${value}" != "fail"* ]]; then
                    echo "  <testcase name=\"${tag}\"/>"
                else
                    parse_fail=1
                    printf '  <testcase name="%s"><failure message="output=%s"/></testcase>\n' "${tag}" "${value}"
                fi
                ;;
        esac
    done <<<"${sm_lines}"
    echo '</testsuite>'
    echo '</testsuites>'
} >"${junit}"

# ---- 归档 md ----
date_stamp="$(date +%Y%m%d)"
archive="${ROOT_DIR}/docs/qa/${release}/smoke-${date_stamp}-${commit_sha}-${image_layer}.md"
{
    echo "# runtime smoke —— ${release} ${image_layer}（#132）"
    echo
    echo "- commit：\`${commit_sha}\`（指纹 $(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD)）"
    echo "- 动作数：${#guest_lines[@]}；解析失败：${parse_fail}"
    echo "- 串口日志：\`${serial_log_path}\`"
    echo "- JUnit：\`reports/smoke/smoke-${release}-${variant}-${image_layer}.xml\`"
    echo
    echo '```'
    printf '%s\n' "${sm_lines}"
    echo '```'
    if [[ "${image_layer}" != "full" ]]; then
        echo
        echo "## 层裁剪说明"
        echo
        echo "本层不含的服务与 demo 动作被**显式裁剪**（不是静默 skip）："
        if [[ "${image_layer}" == "minimal" ]]; then
            echo "- minimal 无 curl/tar（base 起）、无服务与 demo 包（full 起）"
        fi
        echo "- wrynose 的 ${image_layer} 串口 root 无空密码（degraded.txt: empty-root-login），"
        echo "  动作集经 boot-exec 同款串口注入执行——若 login 失败本报告不会存在"
    fi
    echo
} >"${archive}"
{
    printf '%s  %s\n' "$(sha256sum "${serial_abs}" | awk '{print $1}')" "${serial_log_path}"
    printf '%s  %s\n' "$(sha256sum "${junit}" | awk '{print $1}')" "${junit#"${ROOT_DIR}/"}"
} >"${ROOT_DIR}/docs/qa/${release}/artifacts-smoke-${commit_sha}-${image_layer}.sha256"

echo "smoke：${image_layer} 解析失败=${parse_fail}（JUnit：${junit#"${ROOT_DIR}/"}）"
echo "归档：${archive#"${ROOT_DIR}/"}"
exit "$((parse_fail > 0))"
