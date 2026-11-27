#!/usr/bin/env bash
# M1-S2（DES-003）：在已 source environment-setup-* 的宿主 shell 中，最小验证
# devtool add / build / modify 链路 + ide-sdk --help 可用性检查。
# 成功 DEVTOOL_SMOKE_OK；add/modify/build 任一失败 DEVTOOL_SMOKE_FAIL 非 0。
# ide-sdk 仅记 IDE_SDK_HELP_OK / IDE_SDK_UNAVAILABLE，不并入主结论（plan §M1-S2）。
# devshell 交互不跑，标 UNVERIFIED。
set -uo pipefail

WORKDIR=""
KEEP=0
RECIPE="yp-smoke-hello"
MODIFY_RECIPE="m4"

usage() { echo "usage: devtool-smoke.sh [--workdir <dir>] [--keep] [--modify-recipe <name>]"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir)       WORKDIR="${2:-}"; shift 2 ;;
    --keep)          KEEP=1; shift ;;
    --modify-recipe) MODIFY_RECIPE="${2:-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
done

fail() { echo "DEVTOOL_SMOKE_FAIL reason=$*"; exit 1; }
step() { echo; echo "=== $* ==="; }

command -v devtool >/dev/null 2>&1 || fail "devtool not in PATH (source environment-setup-* first?)"

if [ -z "$WORKDIR" ]; then
  WORKDIR=$(mktemp -d /tmp/yp-devtool-smoke-XXXXXX) || fail "mktemp failed"
fi
mkdir -p "$WORKDIR" || fail "cannot create workdir: $WORKDIR"
echo "workdir: $WORKDIR"

cleanup() {
  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$WORKDIR"
  else
    echo "kept workdir: $WORKDIR"
  fi
}
trap cleanup EXIT

# --- 最小本地源码样例：单 Makefile C 程序 ---
SRCDIR="$WORKDIR/src"
mkdir -p "$SRCDIR"
cat > "$SRCDIR/hello.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("yp-devtool-smoke"); return 0; }
EOF
cat > "$SRCDIR/Makefile" <<'EOF'
all: hello
hello: hello.c
	$(CC) $(CFLAGS) -o $@ $<
install: all
	install -d $(DESTDIR)/usr/bin
	install -m 0755 hello $(DESTDIR)/usr/bin/
EOF

# --- devtool --help（非交互，断言关键子命令出现） ---
step "devtool --help"
HELP=$(devtool --help 2>&1) || fail "devtool --help rc=$?"
echo "$HELP"
for cmd in add build modify; do
  echo "$HELP" | grep -qw "$cmd" || fail "devtool --help missing subcommand: $cmd"
done

# --- devtool ide-sdk --help（可用性检查，非阻断） ---
step "devtool ide-sdk --help (availability only)"
if devtool ide-sdk --help >/tmp/yp-ide-sdk-help.txt 2>&1; then
  head -12 /tmp/yp-ide-sdk-help.txt
  echo "IDE_SDK_HELP_OK"
else
  echo "IDE_SDK_UNAVAILABLE (non-blocking; IDE full chain out of scope for S2)"
fi

# --- devtool add（新增 recipe 到 workspace） ---
step "devtool add $RECIPE $SRCDIR"
devtool add "$RECIPE" "$SRCDIR" || fail "devtool add failed (rc=$?)"

# --- devtool build（构建 add 的 recipe） ---
step "devtool build $RECIPE"
devtool build "$RECIPE" || fail "devtool build failed (rc=$?)"

# --- 清理 add 的 recipe：add 与 modify 对同一 recipe 互斥（add 后 recipe 已在 workspace，
#     modify 会报 'already in your workspace'）。reset -n 保留源码、移除 workspace 条目。 ---
step "devtool reset -n $RECIPE (cleanup before modify)"
devtool reset -n "$RECIPE" || fail "devtool reset after add failed (rc=$?)"

# --- devtool modify（对 SDK 中已存在的 recipe，独立于 add） ---
step "devtool modify $MODIFY_RECIPE (existing recipe)"
devtool modify "$MODIFY_RECIPE" || fail "devtool modify $MODIFY_RECIPE failed (rc=$?)"

# --- devtool build（modify 后重编） ---
step "devtool build $MODIFY_RECIPE (after modify)"
devtool build "$MODIFY_RECIPE" || fail "devtool build after modify failed (rc=$?)"

# --- 清理 modify 的 recipe ---
step "devtool reset -n $MODIFY_RECIPE (cleanup)"
devtool reset -n "$MODIFY_RECIPE" || fail "devtool reset after modify failed (rc=$?)"

echo
echo "DEVTOOL_SMOKE_OK add=$RECIPE modify=$MODIFY_RECIPE"
echo "devshell: UNVERIFIED (interactive, not run in non-pty/CI)"
