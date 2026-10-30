include cpp-hello.inc

# =============================================================================
# C26 / #28：`do_scancode` 是 **demo 形态** 的能力，不是交付能力。
#
# 三条理由（实测数据见 docs/scancode.md）：
#   1. scancode 是 Python 应用，做不成可行的 native recipe（依赖树上百、版本互钉、
#      typecode/intbitset 还是编译扩展），所以这里不能写 DEPENDS；
#   2. 每个 recipe 单开一次 scancode 的进程启动开销是 4~5 秒，镜像里 146 个
#      recipe 就是约 11 分钟纯启动时间；
#   3. 它扫的源码与「构建后批量扫一遍」完全等价，多花的钱换不到任何额外覆盖。
#
# 正式形态是构建后的批量扫描；这个任务只为演示 recipe 内扫描长什么样，
# 默认不动手，且不进任何镜像（04_layer.bats 有断言守着）。
#
# 演示怎么打开：local.conf（或 kas overlay 的 local_conf_header）里写
#   YP_SCANCODE_ENABLE    = "1"
#   YP_SCANCODE_BIN       = "<scripts/scancode.sh path --release <r> 的输出>"
#   YP_SCANCODE_PROCESSES = "4"
# 工具本身由 scripts/scancode.sh sync 准备到 work/tools/，不烤进镜像。
#
# 注意：这里刻意**不用** `do_scancode[noexec] = "${@...}"` 这种写法。实测在
# kas overlay 把 YP_SCANCODE_ENABLE 设成 "1" 之后，noexec 这个 varflag 仍然
# 被判成 1（任务照样以 noexec 跑完，什么都不做），换个写法排查成本不值当。
# 直接放在函数体里判断，语义一眼可读，三个版本行为也一致。
# =============================================================================

# 工具路径由外部给：不构建、不 DEPENDS、不装进镜像。
YP_SCANCODE_BIN ?= ""
# 必须显式传 --processes：scancode 不传时基本等于串行。实测同一份 busybox，
# 不传 570 秒、传 32 是 46 秒（差 12 倍）。默认 4，避免与 PARALLEL_MAKE 抢核。
YP_SCANCODE_PROCESSES ?= "4"

SCANCODE_REPORT_DIR = "${WORKDIR}/scancode"

do_scancode() {
    if [ "${YP_SCANCODE_ENABLE}" != "1" ]; then
        bbnote "YP_SCANCODE_ENABLE 未开启，跳过 do_scancode（demo 能力，默认不做，见 docs/scancode.md）"
        return 0
    fi
    if [ -z "${YP_SCANCODE_BIN}" ]; then
        bbfatal "YP_SCANCODE_BIN 未设置：先跑 scripts/scancode.sh sync --release <r>，再把 scripts/scancode.sh path --release <r> 的输出写进 YP_SCANCODE_BIN（见 docs/scancode.md）"
    fi
    if [ ! -x "${YP_SCANCODE_BIN}" ]; then
        bbfatal "YP_SCANCODE_BIN 不可执行：${YP_SCANCODE_BIN}"
    fi
    install -d "${SCANCODE_REPORT_DIR}"
    ${YP_SCANCODE_BIN} -v \
        --processes "${YP_SCANCODE_PROCESSES}" \
        --license --license-clarity-score --license-score 70 --license-text \
        --copyright --package --info --consolidate --classify --summary --tallies \
        --url --email \
        --csv "${SCANCODE_REPORT_DIR}/scancode.csv" \
        --json-pp "${SCANCODE_REPORT_DIR}/scancode.json" \
        --spdx-tv "${SCANCODE_REPORT_DIR}/scancode.spdx" \
        --ignore "temp/*" --ignore "scancode/*" \
        "${S}"
    bbnote "ScanCode 报告：${SCANCODE_REPORT_DIR}"
}

# 放在 do_patch 之后：此时工作区里只有解包后的源码 + temp/，扫描结果不会被
# 编译中间产物和自己的输出目录污染（实测扫 do_compile 之后的目录会多出 19 MB）。
addtask scancode after do_patch before do_compile
do_scancode[doc] = "演示用：对源码目录跑 ScanCode。默认跳过，见文件头说明。"
# 每次真跑都重扫：结果不进 sstate，也不让 sstate 命中掩盖工具升级。
do_scancode[nostamp] = "1"
