#!/usr/bin/env bats
# ScanCode CLI 供给与 recipe 内 do_scancode 的 demo 形态（issue #28 / C26）。
# 只验证脚本契约与配方文本：真下载、真扫描需要出网与几分钟，不进门禁。
# 实测数据（体积、启动开销、--processes 影响）记在 docs/scancode.md。

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    scancode_sh="${ROOT_DIR}/scripts/scancode.sh"
    recipe="${ROOT_DIR}/layers/meta-yp/recipes-example/cpp-hello/cpp-hello-scancode_0.1.bb"
}

# bats test_tags=scancode
@test "scancode.sh status 覆盖四个 release 且版本按镜像 python 选" {
    run bash "${scancode_sh}" status
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"dunfell"* ]]
    [[ "${output}" == *"kirkstone"* ]]
    [[ "${output}" == *"scarthgap"* ]]
    [[ "${output}" == *"wrynose"* ]]
    # 32.5.0 要求 python>=3.10，所以 dunfell(3.8) 必须退回 32.0.6
    [[ "${output}" == *"32.0.6"* ]]
    [[ "${output}" == *"py3.8"* ]]
    [[ "${output}" == *"py3.10"* ]]
    [[ "${output}" == *"py3.12"* ]]
}

# bats test_tags=scancode
@test "scancode.sh path 给出容器内绝对路径，路径带版本与 python" {
    run bash "${scancode_sh}" path --release dunfell
    [ "${status}" -eq 0 ]
    [ "${output}" = "/work/work/tools/scancode-v32.0.6-py3.8/scancode" ]

    run bash "${scancode_sh}" path --release kirkstone
    [ "${output}" = "/work/work/tools/scancode-v32.5.0-py3.10/scancode" ]
}

# bats test_tags=scancode
@test "scarthgap 与 wrynose 共用同一份 scancode" {
    # 两者镜像 base 都是 ubuntu:24.04 / py3.12，没必要下两份、占两份额外磁盘。
    local sc w
    sc="$(bash "${scancode_sh}" path --release scarthgap)"
    w="$(bash "${scancode_sh}" path --release wrynose)"
    [ "${sc}" = "${w}" ]
    [[ "${sc}" == *"py3.12"* ]]
}

# bats test_tags=scancode
@test "scancode.sh 拒绝缺少 --release 的 path 与未知 release" {
    run bash "${scancode_sh}" path
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"--release"* ]]

    run bash "${scancode_sh}" path --release nosuchrelease
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"不支持的 release"* ]]
}

# bats test_tags=scancode
@test "scancode-toolkit-native 的 shim 配方已删除且无人依赖" {
    # 那个配方不构建任何东西，只写 wrapper 去 exec 一个不存在的宿主路径
    # （/workspace/resources/scancode-toolkit-31.2.6）。「有 recipe」不等于「有工具」。
    [ ! -d "${ROOT_DIR}/layers/meta-yp/recipes-example/scancode-toolkit" ]
    run grep -rn 'scancode-toolkit-native' "${ROOT_DIR}/layers" "${ROOT_DIR}/kas" "${ROOT_DIR}/config"
    [ "${status}" -eq 1 ]
}

# bats test_tags=scancode
@test "do_scancode 走外部 CLI，不写 DEPENDS" {
    # scancode 是 Python 应用，做不成可行的 native recipe，所以只能运行时给路径。
    run grep -q '^DEPENDS' "${recipe}"
    [ "${status}" -eq 1 ]
    grep -q 'YP_SCANCODE_BIN ?=' "${recipe}"
    grep -q 'bbfatal "YP_SCANCODE_BIN 未设置' "${recipe}"
    grep -q '! -x "${YP_SCANCODE_BIN}"' "${recipe}"
}

# bats test_tags=scancode
@test "do_scancode 必须显式传 --processes 并忽略工作目录噪音" {
    # scancode 不传 --processes 时基本等于串行：实测同一份 busybox，
    # 不传 570 秒、传 32 是 46 秒，差 12 倍。默认值必须落在配方里。
    grep -q 'YP_SCANCODE_PROCESSES ?=' "${recipe}"
    grep -q -- '--processes "${YP_SCANCODE_PROCESSES}"' "${recipe}"
    # file:// recipe 的 S 就是 WORKDIR，不忽略 temp/ 与自身输出目录会扫出 19 MB 噪音。
    grep -q -- '--ignore "temp/\*"' "${recipe}"
    grep -q -- '--ignore "scancode/\*"' "${recipe}"
    # 必须在编译前扫：do_compile 之后工作区里会多出二进制与中间产物。
    grep -q '^addtask scancode after do_patch before do_compile' "${recipe}"
}

# bats test_tags=scancode
@test "do_scancode 默认跳过且不进任何镜像" {
    # 刻意不用 do_scancode[noexec] = "${@...}"：实测 kas overlay 把
    # YP_SCANCODE_ENABLE 设成 "1" 之后，noexec 这个 varflag 仍被判成 1，
    # 任务照样以 noexec 跑完、什么都不做。改成函数体内判断。
    grep -q 'YP_SCANCODE_ENABLE}" != "1"' "${recipe}"
    # 只看真正的 flag 行：文件头的注释会引用这个写法当反面例子。
    run grep -qE '^do_scancode\[noexec\]' "${recipe}"
    [ "${status}" -eq 1 ]
    # C27：general 用 core-image-minimal，不应被这个 demo 能力污染。
    run grep -rn 'cpp-hello-scancode' "${ROOT_DIR}/layers/meta-yp/recipes-core"
    [ "${status}" -eq 1 ]
}
