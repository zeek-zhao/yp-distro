#!/usr/bin/env bash
# 从 threshold.conf 生成 cache-meta.json：数值唯一源，改阈值后重新生成随之变化（F-05 / CHG-006）
# T5 / CHG-013：合并静态 docker/cache-provenance.json；禁止时间戳动态生成，保证 gate.sh G2 逐字比对通过。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROVENANCE="$ROOT/docker/cache-provenance.json"
# shellcheck source=threshold.conf
. "$SCRIPT_DIR/threshold.conf"

# 所有数值常量来自 threshold.conf，脚本内不得写死阈值数字
SLICE_MAX_BYTES="${SLICE_MAX_BYTES:?threshold.conf 未定义 SLICE_MAX_BYTES}"
UPLOAD_TIMEOUT_SEC="${UPLOAD_TIMEOUT_SEC:?threshold.conf 未定义 UPLOAD_TIMEOUT_SEC}"
[ -f "$PROVENANCE" ] || { echo "ERROR: 缺少静态 provenance 文件 $PROVENANCE（CHG-013）" >&2; exit 1; }

python3 - "$SLICE_MAX_BYTES" "$UPLOAD_TIMEOUT_SEC" "$PROVENANCE" <<'PY'
import json, sys
slice_max, upload_timeout, prov_path = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
with open(prov_path, encoding='utf-8') as f:
    provenance = json.load(f)
meta = {
    "image": "yp-cache",
    "tag": "wrynose-m0",
    "format": "yp-cache-v1",
    "sources": ["DL_DIR", "SSTATE_DIR"],
    "layout": {"downloads": "/work/downloads", "sstate": "/work/sstate"},
    "split": {
        "slice_max_bytes": slice_max,
        "upload_timeout_sec": upload_timeout,
        "note": "= 80% of repository limits (DES-006 / CHG-006)",
    },
    "server": "none",
    "note": "真实 S5 载荷；分片分发见 ADR-005/CHG-012/CHG-013。",
    "provenance": provenance,
}
print(json.dumps(meta, indent=2, ensure_ascii=False))
PY
