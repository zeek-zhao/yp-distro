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
