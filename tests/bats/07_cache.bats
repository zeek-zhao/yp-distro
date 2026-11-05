#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    mkdir -p "${ROOT_DIR}/work"
}

teardown() {
    if [[ -n "${lock_pid:-}" ]]; then
        kill "${lock_pid}" 2>/dev/null || true
        wait "${lock_pid}" 2>/dev/null || true
        if [[ -f "${lock_ready}" ]]; then
            rm -f -- "${ROOT_DIR}/work/build.lock"
        fi
    fi
    if [[ -n "${test_root:-}" ]]; then
        rm -rf -- "${test_root}"
    fi
    if [[ -n "${render_archive:-}" ]]; then
        rm -f -- "${render_archive}"
    fi
}

cache_fixture() {
    test_root="$(mktemp -d "${ROOT_DIR}/work/cache-test.XXXXXX")"
    cp -R "${ROOT_DIR}/kas" "${ROOT_DIR}/config" "${ROOT_DIR}/scripts" "${test_root}/"
}

# bats test_tags=cache
@test "check_shared_cache passes for the current base configuration" {
    run python3 "${ROOT_DIR}/scripts/kas-verify.py" --engine builtin
    [ "${status}" -eq 0 ]
}

# bats test_tags=cache
@test "check_shared_cache rejects per-release caches" {
    cache_fixture
    sed -i 's|/../../|/../|g' "${test_root}/kas/base.yml"
    run python3 "${ROOT_DIR}/scripts/kas-verify.py" --engine builtin --root "${test_root}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"#23"* ]]
    [[ "${output}" == *"每版本一份 downloads"* ]]
}

# bats test_tags=cache
@test "check_shared_cache rejects missing and weak cache assignments" {
    cache_fixture
    local variable
    for variable in DL_DIR SSTATE_DIR; do
        cp "${ROOT_DIR}/kas/base.yml" "${test_root}/kas/base.yml"
        sed -i "/${variable} =/d" "${test_root}/kas/base.yml"
        run python3 "${ROOT_DIR}/scripts/kas-verify.py" --engine builtin --root "${test_root}"
        [ "${status}" -ne 0 ]
        [[ "${output}" == *"#23"* ]]
        [[ "${output}" == *"${variable}"* ]]
        cp "${ROOT_DIR}/kas/base.yml" "${test_root}/kas/base.yml"
        sed -i "s/${variable} =/${variable} ??=/" "${test_root}/kas/base.yml"
        run python3 "${ROOT_DIR}/scripts/kas-verify.py" --engine builtin --root "${test_root}"
        [ "${status}" -ne 0 ]
        [[ "${output}" == *"#23"* ]]
    done
}

# bats test_tags=cache
@test "build.sh validates required arguments and allowed values" {
    run bash "${ROOT_DIR}/scripts/build.sh" --variant general --dry-run
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"Usage:"* ]]
    run bash "${ROOT_DIR}/scripts/build.sh" --release scarthgap --dry-run
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/build.sh" --release ../scarthgap --variant general --dry-run
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/build.sh" --release scarthgap --variant invalid --dry-run
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/build.sh" --release scarthgap --variant general --image-mode invalid --dry-run
    [ "${status}" -eq 2 ]
    run bash "${ROOT_DIR}/scripts/build.sh" --release
    [ "${status}" -eq 2 ]
}

# bats test_tags=cache
@test "build.sh rejects concurrent builds without waiting" {
    lock_ready="${BATS_TEST_TMPDIR}/lock-ready"
    (
        exec 9>"${ROOT_DIR}/work/build.lock"
        flock -n 9 || exit 1
        touch "${lock_ready}"
        exec sleep 30
    ) >/dev/null 2>&1 3>&- &
    lock_pid=$!
    local attempt
    for attempt in {1..100}; do
        [[ ! -f "${lock_ready}" ]] || break
        sleep 0.05
    done
    [ -f "${lock_ready}" ]
    run timeout 5 bash "${ROOT_DIR}/scripts/build.sh" --release scarthgap --variant general --dry-run
    [ "${status}" -eq 3 ]
    [[ "${output}" == *"另一个构建正在运行"* ]]
}

# bats test_tags=cache
@test "build.sh dry-run prints the container command and shared cache paths" {
    run bash "${ROOT_DIR}/scripts/build.sh" --release scarthgap --variant general --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == "./project.sh shell --release scarthgap --variant general --machine qemux86-64 -- bash -lc '"* ]]
    [[ "${output}" == *"KAS_CLONE_DEPTH=1"* ]]
    [[ "${output}" == *"KAS_WORK_DIR=/work/work/kas-scarthgap-general"* ]]
    [[ "${output}" == *"/work/work/downloads /work/work/sstate"* ]]
    [[ "${output}" == *"kas build /work/kas/targets/scarthgap-general.yml"* ]]
    run bash "${ROOT_DIR}/scripts/build.sh" --release wrynose --variant custom --image-mode dev --dry-run
    [ "${status}" -eq 0 ]
    [[ "${output}" == "bash scripts/dev.sh bash -lc '"* ]]
}

# bats test_tags=cache
@test "build.sh records logs and duration and preserves build failure status" {
    cache_fixture
    cat >"${test_root}/project.sh" <<'EOF'
#!/usr/bin/env bash
printf 'mock shell args: %s\n' "$*"
printf 'mock build stderr\n' >&2
exit "${MOCK_BUILD_STATUS:-0}"
EOF
    chmod +x "${test_root}/project.sh"
    local expected
    for expected in 0 37; do
        run env MOCK_BUILD_STATUS="${expected}" bash "${test_root}/scripts/build.sh" \
            --release scarthgap --variant general
        [ "${status}" -eq "${expected}" ]
        local log="${test_root}/work/logs/build-scarthgap-general.log"
        grep -Fq 'Build start:' "${log}"
        grep -Fq "Build end:" "${log}"
        grep -Fq "(exit ${expected})" "${log}"
        grep -Fq 'mock build stderr' "${log}"
        grep -Fq 'KAS_WORK_DIR=/work/work/kas-scarthgap-general' "${log}"
        grep -Eq '^[0-9]+$' "${log%.log}.meta"
        [ -d "${test_root}/work/downloads" ]
        [ -d "${test_root}/work/sstate" ]
        [ -d "${test_root}/work/kas-scarthgap-general" ]
    done
}

# bats test_tags=cache
@test "report.sh render-only includes build statistics" {
    run bash "${ROOT_DIR}/scripts/report.sh" --release wrynose --variant general --render-only
    [ "${status}" -eq 0 ]
    render_archive="${ROOT_DIR}/${output##*Archive: }"
    grep -Fq '### 构建统计' "${render_archive}"
    grep -Fq 'Build duration' "${render_archive}"
}

# bats test_tags=cache
@test "report.sh renders latest build metrics and n/a without adding degraded items" {
    cache_fixture
    git -C "${test_root}" init -q
    git -C "${test_root}" add config scripts
    git -C "${test_root}" -c user.name=Test -c user.email=test@example.invalid \
        -c core.hooksPath=/dev/null commit -qm fixture
    mkdir -p "${test_root}/work/logs"
    local log="${test_root}/work/logs/build-scarthgap-general.log"
    printf '123\n' >"${log%.log}.meta"
    cat >"${log}" <<'EOF'
NOTE: Tasks Summary: Attempted 10 tasks of which 2 didn't need to be rerun and all succeeded.
Sstate summary: Wanted 10 Local 2 Mirrors 0 Missed 8 Current 5 (20% match, 0 missed)
NOTE: Tasks Summary: Attempted 100 tasks of which 80 didn't need to be rerun and all succeeded.
# Keep Current different from Local so using the cache total as hits fails this test.
Sstate summary: Wanted 50 Local 20 Mirrors 0 Missed 30 Current 40 (40% match, 0 missed)
EOF
    # degraded.txt 是活文件（#81 起 scarthgap 有 uboot-qfw-chain），本测试关心的是
    # 渲染逻辑不是降级清单内容——钉死沙箱里的清单，断言才不会跟着真实降级项漂。
    printf '# aspect | release | 理由 | 需求条款\n' >"${test_root}/config/degraded.txt"
    run bash "${test_root}/scripts/report.sh" --release scarthgap --variant general --render-only
    [ "${status}" -eq 0 ]
    local archive="${test_root}/${output##*Archive: }"
    grep -Fq 'Build duration: 123s' "${archive}"
    grep -Fq 'Tasks attempted / cached: 100 / 80' "${archive}"
    grep -Fq 'Sstate hit: 20/50 (40%)' "${archive}"
    grep -Fq "Build log: \`${log}\`" "${archive}"
    rm -- "${log}" "${log%.log}.meta"
    run bash "${test_root}/scripts/report.sh" --release scarthgap --variant general --render-only
    [ "${status}" -eq 0 ]
    grep -Fq 'Build duration: n/a' "${archive}"
    grep -Fq 'Tasks attempted / cached: n/a' "${archive}"
    grep -Fq 'Sstate hit: n/a' "${archive}"
    ! grep -Fq 'Build log:' "${archive}"
    grep -Fq '无（本版本全部能力按标准实现）' "${archive}"
}

# bats test_tags=cache
@test "report.sh falls back to the 3.1 sstate summary format" {
    # bitbake 1.46 的 summary 没有 Local/Mirrors，命中数叫 Found：
    #   Sstate summary: Wanted N Found M Missed K Current C (P% match, Q% complete)
    # 只认 4.0+ 的写法会让 dunfell 的 Sstate hit 一直是 n/a（#47）。
    cache_fixture
    git -C "${test_root}" init -q
    git -C "${test_root}" add config scripts
    git -C "${test_root}" -c user.name=Test -c user.email=test@example.invalid \
        -c core.hooksPath=/dev/null commit -qm fixture
    mkdir -p "${test_root}/work/logs"
    local log="${test_root}/work/logs/build-dunfell-general.log"
    # Current(340) 故意远大于 Found(12)：把缓存总数当命中数的实现会渲染成 340/100。
    cat >"${log}" <<'EOF'
Sstate summary: Wanted 100 Found 12 Missed 88 Current 340 (12% match, 0% complete)
EOF
    run bash "${test_root}/scripts/report.sh" --release dunfell --variant general --render-only
    [ "${status}" -eq 0 ]
    local archive="${test_root}/${output##*Archive: }"
    grep -Fq 'Sstate hit: 12/100 (12%)' "${archive}"
    rm -- "${log}"
}
