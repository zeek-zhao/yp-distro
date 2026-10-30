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
    extra=()
    if ((index < html_top)); then
        extra=(--html "${out_dir}/${pkg}.html")
    fi
    "${scancode_bin}" \
        --license --copyright --package --info --email --url \
        --license-score 70 --license-text --consolidate --classify \
        --summary --tallies -n 4 --quiet \
        --json-pp "${out_dir}/${pkg}.json" \
        --csv "${out_dir}/${pkg}.csv" \
        --spdx "${out_dir}/${pkg}.spdx" \
        ${extra[@]+"${extra[@]}"} \
        "${src}" >>"${log}" 2>&1
    rc=$?
    if ((rc == 0)) && [[ -s "${out_dir}/${pkg}.json" ]]; then
        ((ok += 1))
        printf 'SCAN %-32s ok\n' "${pkg}" | tee -a "${log}"
    else
        ((failed += 1))
        printf 'SCAN %-32s rc=%s\n' "${pkg}" "${rc}" | tee -a "${log}"
    fi
    rm -rf -- "${src}"
    ((index += 1))
done <"${input}"

printf 'FOSS 扫描：成功 %d，失败 %d\n' "${ok}" "${failed}" | tee -a "${log}"
((ok > 0))
