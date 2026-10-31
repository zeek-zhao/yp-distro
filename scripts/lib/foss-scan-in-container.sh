#!/usr/bin/env bash
# =============================================================================
# scripts/lib/foss-scan-in-container.sh — 在构建容器内批量跑 ScanCode
#
# 为什么必须在容器里跑：ScanCode 的 venv 里 python 是符号链接到容器内的解释器
# （3.1 py3.8 / 4.0 py3.10 / 5.0+ py3.12），宿主机没有对应版本，搬到宿主直接报废。
# 所以 scancode.sh 在哪个容器里 configure，这里就在哪个容器里扫。
#
# 参数（都是容器内绝对路径）：
#   $1  scancode 可执行文件
#   $2  结果目录（每包 .json / .csv / .spdx，前 N 个另有 .html）
#   $3  输入清单 TSV：<包名>\t<源码包路径>
#   $4  .html 保留数量（默认 3；html 体积大，只留 top-N）
#
# 退出码：至少有一个包扫成功就是 0，全失败才非零 —— 汇总脚本按实际产出的
# .json 记账，不靠这里的返回码。
# =============================================================================
set -u

scancode_bin="${1:?需要 scancode 可执行文件}"
out_dir="${2:?需要结果目录}"
input="${3:?需要输入清单}"
html_top="${4:-3}"

mkdir -p -- "${out_dir}"
log="${out_dir}/scancode.log"
: >"${log}"

# 首次调用会触发包装脚本的自动 configure（重建 venv + 从 thirdparty 装 wheel），
# 实测这一枪经常以 rc=126 结束（报的还是 "File name too long" 这种误导性错误），
# 紧接着重跑同一条命令就正常。所以先空跑一次 --version 把 venv 预热出来。
"${scancode_bin}" --version >>"${log}" 2>&1 || true

# 跑一个包；第 1 次失败就在同一容器里重试一次（原因见上）。
run_scan() {
    local pkg="$1" src="$2" attempt="$3" rc
    local -a extra=()
    if ((index < html_top)); then
        extra=(--html "${out_dir}/${pkg}.html")
    fi
    # 输出格式参数用 `--spdx-tv` 而不是 `--spdx`：32.x 只有 `--spdx-tv` / `--spdx-rdf`，
    # 写 `--spdx` 会直接 Usage 报错退出。
    "${scancode_bin}" \
        --license --copyright --package --info --email --url \
        --license-score 70 --license-text --consolidate --classify \
        --summary --tallies -n 8 --quiet \
        --json-pp "${out_dir}/${pkg}.json" \
        --csv "${out_dir}/${pkg}.csv" \
        --spdx-tv "${out_dir}/${pkg}.spdx" \
        ${extra[@]+"${extra[@]}"} \
        "${src}" >>"${log}" 2>&1
    rc=$?
    # 成败以**产物**为准，不以 rc 为准：实测 curl 的 json/csv/spdx/html 全部生成、
    # json 能正常解析，rc 却是 1（ScanCode 32.x 的内部告警会让进程非零退出）。
    # 早先按 rc 判定，导致 curl 在每版都被记成失败，覆盖率被低估一个包。
    if [[ -s "${out_dir}/${pkg}.json" ]] &&
        python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "${out_dir}/${pkg}.json" 2>/dev/null; then
        if ((rc != 0)); then
            printf 'SCAN %-32s ok（rc=%s，产物齐备）\n' "${pkg}" "${rc}" | tee -a "${log}"
        else
            printf 'SCAN %-32s ok\n' "${pkg}" | tee -a "${log}"
        fi
        return 0
    fi
    if ((attempt == 1)); then
        printf 'SCAN %-32s 第 1 次 rc=%s，重试\n' "${pkg}" "${rc}" | tee -a "${log}"
        run_scan "${pkg}" "${src}" 2
        return $?
    fi
    printf 'SCAN %-32s 失败 rc=%s\n' "${pkg}" "${rc}" | tee -a "${log}"
    return 1
}

index=0
ok=0
failed=0
while IFS=$'\t' read -r pkg archive; do
    [[ -n "${pkg:-}" ]] || continue
    [[ "${pkg}" == \#* ]] && continue
    src="${out_dir}/src/${pkg}"
    rm -rf -- "${src}"
    mkdir -p -- "${src}"
    case "${archive}" in
        *.zip) unzip -qq -o "${archive}" -d "${src}" >/dev/null 2>&1 || true ;;
        *) tar -xf "${archive}" -C "${src}" 2>/dev/null || true ;;
    esac
    # 解包失败（空目录）也照样扫：产物里 files=0 比静默跳过更可追溯。
    if run_scan "${pkg}" "${src}" 1; then
        ((ok += 1))
    else
        ((failed += 1))
    fi
    rm -rf -- "${src}"
    ((index += 1))
done <"${input}"

printf 'FOSS 扫描：成功 %d，失败 %d\n' "${ok}" "${failed}" | tee -a "${log}"
((ok > 0))
