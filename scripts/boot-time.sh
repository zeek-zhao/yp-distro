#!/usr/bin/env bash
# =============================================================================
# scripts/boot-time.sh —— 启动时间三段测量（墙钟 / 内核+用户态 / bootloader）
#
#   bash scripts/boot-time.sh --release wrynose --variant custom --image minimal --runs 3
#   bash scripts/boot-time.sh --from-log work/logs/serial-xx.log      # 只验解析，不起机
#
# 为什么是三段而不是一个数：单一「开机 3 秒」没法归因 —— 到底是 bootloader 慢、
# 内核慢、还是用户态在等某个 unit？三段分开记，v0.5.0 的优化才有对照。
#
# 口径警告：mode=tcg 的数字不能与 kvm 的比较。TCG 是纯软件模拟，
# 同一镜像能差出十倍，拿它对基线做「优化了 40%」毫无意义。
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${ROOT_DIR}/scripts/lib/common.sh"

usage() {
    cat <<'USAGE'
用法：scripts/boot-time.sh --release <r> [--variant <v>] [--image <层>] [--runs N]
       scripts/boot-time.sh --from-log <串口日志>

  --release <r>        dunfell | kirkstone | scarthgap | wrynose
  --variant <v>        general | custom（默认 custom）
  --machine <m>        默认 qemux86-64
  --image <层>         minimal | base | full（默认 full）
  --runs <N>           起机次数，取中位数（默认 3）
  --timeout <秒>       单次起机超时（默认 240）
  --from-log <文件>    回放模式：只解析已有串口日志，验证判定逻辑，不起机

产出：work/artifacts/<release>/<variant>/boot-time.json
USAGE
}

release=""
variant="custom"
machine="qemux86-64"
image_layer="full"
runs=3
boot_timeout=240
from_log=""

while (($# > 0)); do
    case "$1" in
        --release | --variant | --machine | --image | --runs | --timeout | --from-log)
            (($# >= 2)) || die "$1 缺少参数"
            case "$1" in
                --release) release="$2" ;;
                --variant) variant="$2" ;;
                --machine) machine="$2" ;;
                --image) image_layer="$2" ;;
                --runs) runs="$2" ;;
                --timeout) boot_timeout="$2" ;;
                --from-log) from_log="$2" ;;
            esac
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1" ;;
    esac
done

# ---------------------------------------------------------------- 回放模式
if [[ -n "${from_log}" ]]; then
    [[ -f "${from_log}" ]] || die "日志不存在：${from_log}"
    python3 - "${from_log}" <<'PY'
import json
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1])
text = log.read_text(errors="replace").replace("\r", "")
lines = [ln for ln in text.splitlines() if "runqemu - INFO" not in ln]

has_login = any("login:" in ln for ln in lines)
has_kernel = any("[    0.000000]" in ln for ln in lines)
has_uboot = any("U-Boot 20" in ln for ln in lines)
has_loader = any("Starting kernel" in ln for ln in lines)
m = re.search(r"Startup finished in ([^\n]+)", text)

payload = {
    "mode": "replay",
    "wall_ms": None,
    "kernel_ms": None,
    "uboot_ms": None,
    "detected": {
        "login": has_login,
        "kernel": has_kernel,
        "uboot": has_uboot,
        "loader": has_loader,
    },
    "systemd_analyze": m.group(1).strip() if m else None,
    "log": str(log),
}
print(json.dumps(payload, ensure_ascii=False))
# 缺 login 必须判失败，不能返回 0 —— 否则「没起来」会被记成「极快」
sys.exit(0 if has_login else 3)
PY
    exit $?
fi

# ---------------------------------------------------------------- 真起机
[[ -n "${release}" ]] || die "--release 必填（或用 --from-log 回放）"
case "${image_layer}" in
    minimal | base | full) ;;
    *) die "--image 必须是 minimal|base|full" ;;
esac
[[ "${runs}" =~ ^[1-9][0-9]*$ ]] || die "--runs 必须是正整数"

resolve_all "${release}" "${variant}" "${machine}"
image_target="$(resolve_image "${image_layer}")"

artifact_dir="${ROOT_DIR}/work/artifacts/${release}/${variant}"
mkdir -p "${artifact_dir}" "${ROOT_DIR}/work/logs"

runs_json=()
for ((i = 1; i <= runs; i++)); do
    echo "── run ${i}/${runs} (${image_target})"
    run_out="/work/work/logs/boot-time-${release}-${variant}-r${i}.json"
    inner_rc=0
    bash "${ROOT_DIR}/project.sh" shell --release "${release}" --variant "${variant}" \
        --machine "${machine}" -- \
        env RELEASE="${release}" VARIANT="${variant}" IMAGE="${image_target}" \
        MACHINE="${machine}" BOOT_TIMEOUT="${boot_timeout}" RUN_INDEX="${i}" \
        OUT_FILE="${run_out}" \
        bash /work/scripts/lib/inner-boot-time.sh 2>&1 | tail -6 || inner_rc=$?
    host_out="${ROOT_DIR}/work/logs/boot-time-${release}-${variant}-r${i}.json"
    # 内层 rc=3 才是「没起机」；其他非零是测量链自身的错误（曾把脚本 bug
    # 也谎报成「未拿到 login」，排查时被带偏 —— 见 #110），分开报。
    if ((inner_rc == 0)) && [[ -f "${host_out}" ]]; then
        runs_json+=("${host_out}")
    elif ((inner_rc == 3)); then
        echo "run ${i} 未拿到 login，跳过（不计入中位数）"
    else
        echo "run ${i} 测量链失败（rc=${inner_rc}，json 未产出），跳过（不计入中位数）" >&2
    fi
done

((${#runs_json[@]} > 0)) || die "全部 ${runs} 次都没起机成功，拒绝写全部为 0 的基线"

python3 - "${artifact_dir}/boot-time.json" "${release}" "${variant}" "${image_target}" "${runs_json[@]}" <<'PY'
import json
import pathlib
import statistics
import sys

out, release, variant, image = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
runs = [json.loads(pathlib.Path(p).read_text()) for p in sys.argv[5:]]


def collect(key):
    return [r[key] for r in runs if r.get(key) is not None]


def median(vals):
    return int(statistics.median(vals)) if vals else None


wall = collect("wall_ms")
kernel = collect("kernel_ms")
uboot = collect("uboot_ms")

payload = {
    "release": release,
    "variant": variant,
    "image": image,
    "mode": runs[0].get("mode", "unknown"),
    "runs": len(runs),
    "wall_ms": wall,
    "kernel_ms": kernel,
    "uboot_ms": uboot,
    "median": {
        "wall_ms": median(wall),
        "kernel_ms": median(kernel),
        "uboot_ms": median(uboot),
    },
    "systemd_analyze": [r.get("systemd_analyze") for r in runs],
}

# 自检：三段之和应接近墙钟。差太多说明区间定义有重叠或漏算，
# 这种事必须在写基线时当场发现，而不是三个月后拿它对账。
if payload["median"]["wall_ms"] and payload["median"]["kernel_ms"]:
    parts = payload["median"]["kernel_ms"] + (payload["median"]["uboot_ms"] or 0)
    drift = abs(parts - payload["median"]["wall_ms"]) / payload["median"]["wall_ms"]
    payload["self_check_drift"] = round(drift, 3)
    if drift > 0.10:
        print(f"警告：三段之和与墙钟偏差 {drift:.1%}（>10%），区间定义需复核", file=sys.stderr)

pathlib.Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
m = payload["median"]
print(f"mode={payload['mode']} runs={payload['runs']} "
      f"wall={m['wall_ms']}ms kernel={m['kernel_ms']}ms uboot={m['uboot_ms']}")
print(f"→ {out}")
if payload["mode"] == "tcg":
    print("注意：TCG 口径，不可与 KVM 数据比较")
PY
