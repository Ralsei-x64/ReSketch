#!/bin/sh
# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp /tmp/resketch-native-tab-drop.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
c++ -std=c++17 -fPIC tests/native-tab-drop.test.cpp src/FontHelper.cpp -Ibuild/resketch_autogen/include -I/usr/include/KF6/KNotifications \
    $(pkg-config --cflags --libs fontconfig freetype2 Qt6DBus Qt6Concurrent Qt6Widgets Qt6Network Qt6Quick Qt6QuickControls2 Qt6WebEngineQuick KF6WindowSystem) -lKF6Notifications \
    -o "$test_binary"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
    QT_QUICK_CONTROLS_STYLE=org.kde.desktop "$test_binary"
