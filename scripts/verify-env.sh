#!/usr/bin/env bash
# 换机环境只读预检（T2 / RV-013）：只检查、不修改任何文件，不 chown、不 mkdir、不 docker pull。
# registry 探测只走 GitHub Container Registry 的 token + tags list API。
# 退出码：0 全通过 / 1 致命（docker、磁盘、网络、镜像不可拉）/ 2 警告（内存、UID/GID 或资源低于 32c/128GiB 标准基线）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/scripts/cache/threshold.conf"
BUILDER_REPO="zeek-zhao/yp-builder"
BUILDER_TAG="wrynose-m0"
NET_DOMAINS=(ghcr.io api.github.com git.openembedded.org git.yoctoproject.org)
MEM_WARN_GB=16
CPU_STD=32
MEM_STD_GB=120   # 128 GiB 档的可见下限（MemTotal 实报约 123.3 GiB）

DOWNLOADS=""; SSTATE=""; MIN_DISK_GB=200; SKIP_NETWORK=0
FAIL_N=0; WARN_N=0

pass() { echo "PASS $*"; }
warn() { echo "WARN $*"; WARN_N=$((WARN_N+1)); }
fail() { echo "FAIL $*"; FAIL_N=$((FAIL_N+1)); }
skip() { echo "SKIP $*"; }

usage() {
  cat <<EOF
用法: bash scripts/verify-env.sh --downloads <dir> --sstate <dir> [--min-disk-gb 200] [--skip-network]

  --downloads <dir>     下载卷宿主目录（可不存在；检查其所在卷空间）
  --sstate <dir>        缓存卷宿主目录（可不存在；检查其所在卷空间）
  --min-disk-gb <n>     最小可用磁盘 GB（默认 200）
  --skip-network        跳过网络与 registry API 探测（打印 SKIP，不算通过）

退出码: 0 全通过 / 1 致命 / 2 警告。本脚本为只读检查，不创建目录、不 chown、不拉镜像。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --downloads) [ $# -ge 2 ] || { echo "ERROR: --downloads 缺少参数" >&2; exit 1; }; DOWNLOADS="$2"; shift 2 ;;
    --sstate)    [ $# -ge 2 ] || { echo "ERROR: --sstate 缺少参数" >&2; exit 1; }; SSTATE="$2"; shift 2 ;;
    --min-disk-gb) [ $# -ge 2 ] || { echo "ERROR: --min-disk-gb 缺少参数" >&2; exit 1; }; MIN_DISK_GB="$2"; shift 2 ;;
    --skip-network) SKIP_NETWORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 未知参数 $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$DOWNLOADS" ] || [ -z "$SSTATE" ]; then
  echo "ERROR: 必须同时提供 --downloads 与 --sstate" >&2; usage >&2; exit 1
fi
case "$MIN_DISK_GB" in
  ''|*[!0-9]*) echo "ERROR: --min-disk-gb 必须是整数" >&2; exit 1 ;;
esac

echo "===== ENV PRECHECK (read-only) ====="

# 0) 宿主依赖（fetch/verify/clone 需要；缺 python3 不得落到 registry 401）
for c in git bash python3 curl tar sha256sum; do
  if command -v "$c" >/dev/null 2>&1; then
    pass "DEP $c=$(command -v "$c")"
  else
    fail "DEP_MISSING $c（fetch/verify/clone 需要；先安装再继续）"
  fi
done

# 1) 集中配置存在性（唯一阈值源）
if [ -f "$CONF" ]; then
  pass "THRESHOLD_CONF $CONF"
  # shellcheck source=cache/threshold.conf
  . "$CONF"
else
  fail "THRESHOLD_CONF 缺少 $CONF"
fi

# 2) docker 命令与 daemon
if ! command -v docker >/dev/null 2>&1; then
  fail "DOCKER docker 命令不可用（本机未安装 docker）"
elif ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  fail "DOCKER daemon 不可用（docker version 无法取得 server 版本）"
else
  pass "DOCKER version=$(docker version --format '{{.Server.Version}}') daemon=ok"
fi

# 3) 目标卷空间（目标目录可以尚不存在，取最近的已存在祖先做 df）
nearest_existing() {
  local p="$1" parent
  while [ ! -e "$p" ]; do
    parent="$(dirname "$p")"
    [ "$parent" = "$p" ] && { echo /; return; }
    p="$parent"
  done
  echo "$p"
}
min_bytes=$((MIN_DISK_GB * 1024 * 1024 * 1024))
for item in "downloads:$DOWNLOADS" "sstate:$SSTATE"; do
  role="${item%%:*}"; dir="${item#*:}"
  probe="$(nearest_existing "$dir")"
  avail="$(df -PB1 "$probe" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [ -z "$avail" ]; then
    fail "DISK_${role} 无法读取 $probe 的可用空间"
  elif [ "$avail" -lt "$min_bytes" ]; then
    fail "DISK_${role} 可用 ${avail} B < 阈值 ${min_bytes} B (${MIN_DISK_GB} GB)"
  else
    pass "DISK_${role} dir=$dir volume=$probe avail=${avail} B >= ${min_bytes} B"
  fi
done

# 4) 物理内存（/proc/meminfo MemTotal，非 cgroup 限额）
mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
mem_gb=$((mem_kb / 1024 / 1024))
if [ "$mem_gb" -lt "$MEM_WARN_GB" ]; then
  warn "MEMORY physical=${mem_gb} GB < ${MEM_WARN_GB} GB 建议下限（RV-005 在 8 GB cgroup 下需下调并发）"
else
  pass "MEMORY physical=${mem_gb} GB >= ${MEM_WARN_GB} GB"
fi

# 5) CPU 核数（只报告，不作为失败条件）
cpus="$(nproc 2>/dev/null || echo unknown)"
pass "CPU cores=$cpus"
if [ "$cpus" != "unknown" ] && [ "$cpus" -lt "$CPU_STD" ] 2>/dev/null; then
  warn "RESOURCE_PARTIAL cores=${cpus} < ${CPU_STD} 标准基线（结果不得写成 32c/128G full-quota PASS）"
elif [ "$mem_gb" -lt "$MEM_STD_GB" ]; then
  warn "RESOURCE_PARTIAL mem=${mem_gb} GB < ${MEM_STD_GB} GB 标准基线（结果不得写成 32c/128G full-quota PASS）"
fi

# 6) 当前 uid/gid 与镜像默认对比
cur_uid="$(id -u)"; cur_gid="$(id -g)"
if [ "${JENKINS_UID:-}" != "$cur_uid" ] || [ "${JENKINS_GID:-}" != "$cur_gid" ]; then
  warn "UID current=${cur_uid}:${cur_gid} != image default=${JENKINS_UID:-unknown}:${JENKINS_GID:-unknown}（见 runbook §5.2：用 sudo 或重建 yp-builder:local）"
else
  pass "UID current=${cur_uid}:${cur_gid} == image default"
fi

# 7) editions 符号链接
if [ -L "$ROOT/editions" ] && [ "$(readlink -f "$ROOT/editions")" = "$ROOT/kas/editions" ]; then
  pass "EDITIONS symlink $ROOT/editions -> kas/editions"
else
  fail "EDITIONS 符号链接缺失或未指向 kas/editions: $ROOT/editions"
fi

# 8) builder 镜像匿名 registry 探测（只 API，不 docker pull）
if [ "$SKIP_NETWORK" -eq 1 ]; then
  skip "REGISTRY --skip-network（未验证 builder 镜像可匿名拉取）"
elif ! command -v curl >/dev/null 2>&1; then
  fail "REGISTRY curl 不可用，无法做 registry token + tags list 探测"
else
  token_resp="$(curl -sS -m 20 "https://ghcr.io/token?scope=repository:${BUILDER_REPO}:pull&service=ghcr.io" 2>/dev/null)" || token_resp=""
  token="$(printf '%s' "$token_resp" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("token",""))
except Exception: print("")' 2>/dev/null || true)"
  if [ -z "$token" ]; then
    fail "REGISTRY 无法取得 ghcr.io 匿名 token（网络/代理/401？见 runbook §5.3）"
  else
    resp="$(curl -sS -m 20 -H "Authorization: Bearer $token" -w '\n%{http_code}' \
      "https://ghcr.io/v2/${BUILDER_REPO}/tags/list" 2>/dev/null)" || resp=""
    code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
    if [ "$code" = "200" ] && printf '%s' "$body" | grep -q "$BUILDER_TAG"; then
      pass "REGISTRY ${BUILDER_REPO}:${BUILDER_TAG} 匿名 tags list 可见（未拉取镜像）"
    else
      fail "REGISTRY tags list code=${code:-none}，未见 tag ${BUILDER_TAG}（镜像不可拉，401？）"
    fi
  fi
fi

# 9) 出网可达性
if [ "$SKIP_NETWORK" -eq 1 ]; then
  skip "NETWORK --skip-network（未验证出网）"
elif ! command -v curl >/dev/null 2>&1; then
  fail "NETWORK curl 不可用，无法探测出网"
else
  for d in "${NET_DOMAINS[@]}"; do
    if curl -sS -I -m 10 -o /dev/null "https://${d}" 2>/dev/null; then
      pass "NETWORK https://${d} reachable (10s timeout)"
    else
      fail "NETWORK https://${d} unreachable (10s timeout)"
    fi
  done
fi

echo "===== ENV RESULT: fail=$FAIL_N warn=$WARN_N ====="
if [ "$FAIL_N" -gt 0 ]; then
  echo "ENV_FAIL"; exit 1
elif [ "$WARN_N" -gt 0 ]; then
  echo "ENV_WARN"; exit 2
fi
echo "ENV_OK"; exit 0