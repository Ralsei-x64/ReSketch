#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only
# Run inside a dedicated compositor, never the user's desktop.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/resketch-pointer-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
wayland-scanner client-header /usr/share/plasma-wayland-protocols/fake-input.xml "$work/fake-input-client.h"
wayland-scanner private-code /usr/share/plasma-wayland-protocols/fake-input.xml "$work/fake-input.c"
cc -c "$work/fake-input.c" -o "$work/fake-input.o" $(pkg-config --cflags wayland-client)
c++ -std=c++20 -fPIC tests/mouse-capture.test.cpp "$work/fake-input.o" -Isrc -I"$work" \
    $(pkg-config --cflags --libs Qt6Quick Qt6Test wayland-client) -Lbuild-cef -lresketch_cef -Wl,-rpath,"$PWD/build-cef" -o "$work/check"
cat > "$work/run" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software "$work/check"
QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software "$work/check"
SCRIPT
chmod +x "$work/run"
mkdir -p "$work/runtime" "$work/config"
chmod 700 "$work/runtime"
XDG_RUNTIME_DIR="$work/runtime" XDG_CONFIG_HOME="$work/config" QT_QPA_PLATFORM=offscreen \
    dbus-run-session -- timeout --kill-after=2s 30s kwin_wayland --virtual --xwayland --no-lockscreen \
    --no-global-shortcuts --no-kactivities --width 800 --height 600 --exit-with-session "$work/run"
