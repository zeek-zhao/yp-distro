#!/usr/bin/env bash
# 判据 8：关键变量手改检测。对 variable-index.md 中每个受保护变量断言归口值，漂移即 DRIFT + exit 1
# 用法：bash scripts/check-vars.sh   —— 全通过打印 VARS_OK exit 0；任一漂移 exit 1
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cache/threshold.conf
. "$SCRIPT_DIR/cache/threshold.conf"   # CHG-009：阈值期望值不写死，唯一源

DRIFT=0
CHECKED=0
# 每条：标签|文件|固定字符串（grep -F 匹配，命中即视为值正确）
RULES=(
  'MACHINE|kas/machines/qemux86-64.yml|machine: qemux86-64'
  'DISTRO|meta-yp-distro/conf/distro/yp-wrynose.conf|DISTRO = "yp-wrynose"'
  'DISTRO_VERSION|meta-yp-distro/conf/distro/yp-wrynose.conf|DISTRO_VERSION = "0.1.0"'
  'DL_DIR|kas/base.yml|DL_DIR = "/work/downloads"'
  'SSTATE_DIR|kas/base.yml|SSTATE_DIR = "/work/sstate"'
  'BB_HASHSERVE|kas/base.yml|BB_HASHSERVE = "auto"'
  'BB_HASHSERVE_DB_DIR|kas/base.yml|BB_HASHSERVE_DB_DIR = "${SSTATE_DIR}"'
  'BB_SERVER_TIMEOUT|kas/base.yml|BB_SERVER_TIMEOUT = "300"'
  'BB_NUMBER_THREADS|kas/base.yml|BB_NUMBER_THREADS = "${@oe.utils.cpu_count()}"'
  'PARALLEL_MAKE|kas/base.yml|PARALLEL_MAKE = "-j ${@oe.utils.cpu_count() // 2}"'
  'PACKAGE_CLASSES|kas/base.yml|PACKAGE_CLASSES ??= "package_rpm"'
  'DISTRO_FEATURES|kas/base.yml|DISTRO_FEATURES ??= ""'
  'INIT_MANAGER|kas/base.yml|INIT_MANAGER ??= "systemd"'
  'CONF_VERSION|kas/base.yml|CONF_VERSION = "2"'
  'IMAGE_FSTYPES|kas/editions/prod.yml|IMAGE_FSTYPES = "ext4"'
  'INHERIT_rm_work_ci|kas/editions/ci.yml|INHERIT += "rm_work"'
  'BB_NO_NETWORK|kas/editions/ci.yml|BB_NO_NETWORK ??= "0"'
  'DEBUG_FLAGS|kas/editions/dev.yml|DEBUG_FLAGS = "-g"'
  'KERNEL_CONFIG_FRAGMENTS|kas/editions/dev-kernel.yml|KERNEL_CONFIG_FRAGMENTS ??= ""'
  'LAYERSERIES_COMPAT|meta-yp-distro/conf/layer.conf|LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"'
  'LAYERDEPENDS|meta-yp-distro/conf/layer.conf|LAYERDEPENDS_meta-yp-distro = "core yocto"'
  "SLICE_MAX_BYTES|scripts/cache/threshold.conf|SLICE_MAX_BYTES=${SLICE_MAX_BYTES}"
  "UPLOAD_TIMEOUT_SEC|scripts/cache/threshold.conf|UPLOAD_TIMEOUT_SEC=${UPLOAD_TIMEOUT_SEC}"
  "JENKINS_UID|scripts/cache/threshold.conf|JENKINS_UID=${JENKINS_UID}"
  "MIN_FREE_BYTES|scripts/cache/threshold.conf|MIN_FREE_BYTES=${MIN_FREE_BYTES}"
  'MACHINE_measure|scripts/build/measure.sh|MACHINE="qemux86-64"'
  'EDITION_measure|scripts/build/measure.sh|EDITION="ci"'
)

echo "===== 变量手改检测 (variable-index.md) ====="
for rule in "${RULES[@]}"; do
  label="${rule%%|*}"; rest="${rule#*|}"
  file="${rest%%|*}"; pattern="${rest#*|}"
  CHECKED=$((CHECKED+1))
  if [ ! -f "$file" ]; then
    echo "  DRIFT [$label] 文件缺失: $file" >&2; DRIFT=$((DRIFT+1)); continue
  fi
  if ! grep -Fq "$pattern" "$file"; then
    echo "  DRIFT [$label] 期望 '$pattern' 不在 $file（疑似被手改）" >&2
    # 打印该变量当前实际内容，便于定位
    key="${pattern%% *}"; key="${key%%=*}"
    grep -nF "$key" "$file" | head -2 >&2 || true
    DRIFT=$((DRIFT+1))
  fi
done

# SSTATE_MIRRORS 禁令：任何赋值即漂移
if grep -rqE 'SSTATE_MIRRORS[[:space:]]*=' kas/ meta-yp-distro/ scripts/ docker/ 2>/dev/null; then
  echo "  DRIFT [SSTATE_MIRRORS] 检出远程缓存服务器赋值（违反 AGENTS §3.6）" >&2
  grep -rnE 'SSTATE_MIRRORS[[:space:]]*=' kas/ meta-yp-distro/ scripts/ docker/ >&2 || true
  DRIFT=$((DRIFT+1))
else
  CHECKED=$((CHECKED+1))
fi

echo "===== RESULT: checked=$CHECKED drift=$DRIFT ====="
if [ "$DRIFT" -eq 0 ]; then
  echo "VARS_OK"
  exit 0
else
  echo "VARS_DRIFT_DETECTED" >&2
  exit 1
fi
