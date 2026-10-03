#!/usr/bin/env bash
set -euo pipefail

export CCACHE_DIR=/mnt/ccache
cd "${UGC_WORK:-/mnt/ugc}"

TIMEOUT_BUDGET="${NINJA_TIMEOUT:-19200s}"
: > build-step.log
setsid timeout -k 5m -s INT "$TIMEOUT_BUDGET" ./build.sh "$@" < /dev/null >> build-step.log 2>&1 &
_pid=$!
tail --pid="$_pid" -n +1 -f build-step.log &
_tail=$!
_rc=0
wait "$_pid" || _rc=$?
sudo pkill -9 -s "$_pid" 2>/dev/null || true
wait "$_tail" 2>/dev/null || true

# If build.sh timed out or exited cleanly, ensure status is set in GITHUB_OUTPUT
if [ "$_rc" -eq 124 ] || [ "$_rc" -eq 137 ]; then
    echo "status=running" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
elif [ "$_rc" -eq 0 ]; then
    if grep -q "BUILD COMPLETE" "${UGC_WORK:-/mnt/ugc}/src/out/Default/.build-stamp" 2>/dev/null || [ -n "$(find "${UGC_WORK:-/mnt/ugc}/src/out/Default/apks" -name "TrichromeWebView*.apk" 2>/dev/null | head -1)" ]; then
        echo "status=completed" >> "${GITHUB_OUTPUT:-/dev/null}"
    else
        echo "status=running" >> "${GITHUB_OUTPUT:-/dev/null}"
    fi
    exit 0
fi

exit "$_rc"
