#!/usr/bin/env bash
# 从 threshold.conf 生成 cache-meta.json：数值唯一源，改阈值后重新生成随之变化（F-05 / CHG-006）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=threshold.conf
. "$SCRIPT_DIR/threshold.conf"

# 所有数值常量来自 threshold.conf，脚本内不得写死阈值数字
SLICE_MAX_BYTES="${SLICE_MAX_BYTES:?threshold.conf 未定义 SLICE_MAX_BYTES}"
UPLOAD_TIMEOUT_SEC="${UPLOAD_TIMEOUT_SEC:?threshold.conf 未定义 UPLOAD_TIMEOUT_SEC}"

python3 - "$SLICE_MAX_BYTES" "$UPLOAD_TIMEOUT_SEC" <<'PY'
import json, sys
slice_max, upload_timeout = int(sys.argv[1]), int(sys.argv[2])
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
    "note": "Baseline layout only; real cache payload is produced by S5 and packed by pack.sh (ADR-005 / RV-010 F-02).",
}
print(json.dumps(meta, indent=2, ensure_ascii=False))
PY
