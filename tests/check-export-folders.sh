#!/bin/sh
# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp /tmp/resketch-export-folders.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
c++ -std=c++20 -DCEF_API_VERSION=15400 -fPIC tests/export-folders.test.cpp src/FontHelper.cpp -Ibuild-cef/resketch_autogen/include -Isrc -I"${CEF_ROOT:?Set CEF_ROOT to the extracted distribution}" -I/usr/include/KF6/KNotifications -I/usr/include/KF6/KColorScheme \
    $(pkg-config --cflags --libs fontconfig freetype2 Qt6DBus Qt6Concurrent Qt6Widgets Qt6Network Qt6Quick Qt6QuickControls2 KF6WindowSystem) -lKF6Notifications -lKF6ColorScheme \
    -Lbuild-cef -lresketch_cef -Lbuild-cef/cef -lcef -Wl,-rpath,"$PWD/build-cef:$PWD/build-cef/cef" -o "$test_binary"
QT_QPA_PLATFORM=offscreen "$test_binary"
