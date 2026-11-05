# shellcheck shell=bash
# =============================================================================
# scripts/lib/boot-marks.sh —— 串口流打点：从 runqemu 的输出流里认里程碑
#
# 被 scripts/lib/inner-boot-time.sh source；14_boottime.bats 也直接 source
# 它做管道回放测试，所以这里只能定义函数，不得有顶层副作用。
#
# 调用方约定：
#   MARKS —— 打点索引文件路径；调用方负责 rm -f "${MARKS}" "${MARKS}".*
#
# 为什么不 tail -F 读日志文件：
#   1) getty 的 `... login: ` 提示末尾不带换行，按行读会一直等行尾，
#      等到 qemu 被 kill 才随最后一块输出吐出来，那时 login 早已过去；
#   2) tail 写管道走 stdio 全缓冲，容器里又没有 stdbuf，实时性没有保证。
# 改为直接消费 runqemu 的 stdout 管道：管道无缓冲，read -n 1 逐字符即可实时。
# =============================================================================

monitor_stream() {
    local buf="" ch now
    while IFS= read -r -n 1 ch; do
        buf+="${ch}"
        if [[ "${buf}" == *"[    0.000000]"* && ! -f "${MARKS}.kernel" ]]; then
            now="$(date +%s%3N)"
            echo "kernel ${now}" >>"${MARKS}"
            : >"${MARKS}.kernel"
        fi
        if [[ "${buf}" == *"Starting kernel"* && ! -f "${MARKS}.loader" ]]; then
            now="$(date +%s%3N)"
            echo "loader ${now}" >>"${MARKS}"
            : >"${MARKS}.loader"
        fi
        if [[ "${buf}" == *"U-Boot 20"* && ! -f "${MARKS}.uboot" ]]; then
            now="$(date +%s%3N)"
            echo "uboot ${now}" >>"${MARKS}"
            : >"${MARKS}.uboot"
        fi
        if [[ "${buf}" == *"login:"* && ! -f "${MARKS}.login" ]]; then
            now="$(date +%s%3N)"
            echo "login ${now}" >>"${MARKS}"
            : >"${MARKS}.login"
        fi
        # 只保留尾部：最长模式不到 20 字符，缓冲没必要越积越大
        ((${#buf} > 2048)) && buf="${buf: -64}"
    done
}

# 打点读取。MARKS 还没写出来时 awk 会报错退出非零 —— 调用方在 set -e 下用
# 命令替换取值，非零返回会把整条测量链在「读结果」这一步静默打断（#110），
# 所以这里必须吞掉错误、返回空串，由调用方对空值做「缺打点 = 失败」的判定。
mark() {
    awk -v k="$1" '$1 == k { print $2; exit }' "${MARKS}" 2>/dev/null || true
}
