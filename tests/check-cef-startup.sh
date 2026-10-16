#!/usr/bin/env bash
# Exercise CEF initialization: --version alone never starts Chromium.
set -euo pipefail
executable=$(realpath "${1:?Usage: check-cef-startup.sh /path/to/resketch}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"
status=0
(
    ulimit -c 0
    export XDG_RUNTIME_DIR="$work" XDG_CONFIG_HOME="$work/config"
    export XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
    export RESKETCH_CEF_CACHE_ROOT="$work/cef"
    export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software QT_NO_GLIB=1
    export RESKETCH_CEF_FLAGS="${RESKETCH_CEF_FLAGS:---disable-gpu}"
    timeout --kill-after=2s 10s "$executable" about:blank
) > "$work/startup.log" 2>&1 || status=$?
if [[ $status -ne 124 ]] || ! grep -q '^DevTools listening on ws://127\.0\.0\.1:' "$work/startup.log"; then
    cat "$work/startup.log" >&2
    echo "CEF startup failed (exit $status)" >&2
    exit 1
fi
echo 'CEF initialized and remained running through the startup check'
