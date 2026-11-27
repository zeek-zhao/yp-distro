#!/usr/bin/env bash
# M1-S2（DES-003）：非交互安装 eSDK installer 到指定 prefix，验证 environment-setup 存在。
# 成功 SDK_INSTALL_OK，失败 SDK_INSTALL_FAIL 非 0。installer 名不硬编码，由 --installer 显式传入。
set -uo pipefail

INSTALLER=""
PREFIX=""
EXTRA=()

usage() {
  echo "usage: install-sdk.sh --installer <sdk.sh> --prefix <dir> [-- <installer-args...>]"
  echo "  --installer   eSDK installer (.sh)，须存在且可执行"
  echo "  --prefix      安装目标前缀（建议 /tmp/yp-sdk 之类绝对路径）"
  echo "  --            其后参数原样透传给 installer（覆盖默认 -y -d <prefix>）"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --installer) INSTALLER="${2:-}"; shift 2 ;;
    --prefix)    PREFIX="${2:-}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    --)          shift; EXTRA=("$@"); break ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "SDK_INSTALL_FAIL reason=$*"; exit 1; }

[ -n "$INSTALLER" ] || fail "missing --installer"
[ -n "$PREFIX" ]    || fail "missing --prefix"
[ -f "$INSTALLER" ] || fail "installer not found: $INSTALLER"
[ -x "$INSTALLER" ] || fail "installer not executable: $INSTALLER"

mkdir -p "$PREFIX" || fail "cannot create prefix: $PREFIX"

# Yocto eSDK installer 通用非交互：-y 免确认；-d <dir> 指定安装目录。
# 若调用方用 `--` 透传了参数，则完全采用透传参数（不追加默认）。
if [ "${#EXTRA[@]}" -gt 0 ]; then
  ARGS=("${EXTRA[@]}")
else
  ARGS=(-y -d "$PREFIX")
fi

echo "installer: $INSTALLER"
echo "prefix:    $PREFIX"
echo "installer args: ${ARGS[*]}"
"$INSTALLER" "${ARGS[@]}" || fail "installer exited non-zero (rc=$?)"

# 安装后验证：environment-setup-* 必须存在于 prefix 下（可能在 prefix/ 或 prefix/sysroots 同级）
ENVSET=$(find "$PREFIX" -maxdepth 2 -name 'environment-setup-*' -type f 2>/dev/null | head -1)
[ -n "$ENVSET" ] || fail "no environment-setup-* under $PREFIX"

echo "environment-setup: $ENVSET"
echo "SDK_INSTALL_OK prefix=$PREFIX"
