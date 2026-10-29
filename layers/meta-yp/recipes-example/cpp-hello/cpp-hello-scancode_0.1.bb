include cpp-hello.inc
# inherit scancode-tk
# or other contents as needed


DEPENDS += "scancode-toolkit-native"

# Add scancode scanning task
do_scancode() {
    echo "Running ScanCode analysis..."
    scancode \
    -v \
    --processes 32 \
    --license \
    --license-clarity-score \
    --license-score 70 \
    --license-text \
    --copyright \
    --package \
    --info \
    --consolidate \
    --classify \
    --summary \
    --tallies \
    --url \
    --email \
    --csv ${WORKDIR}/scancode.csv \
    --json-pp ${WORKDIR}/scancode.json \
    --spdx-tv ${WORKDIR}/scancode.spdx \
    ${S}/helloworld.c
}

addtask scancode after do_compile before do_install

# C26：recipe 内 do_scancode 属 P2 未决能力（需要镜像内有 scancode CLI），
# 默认不执行；打开方式：local.conf 里 YP_SCANCODE_ENABLE = "1"。
do_scancode[noexec] = "${@'0' if d.getVar('YP_SCANCODE_ENABLE') == '1' else '1'}"
