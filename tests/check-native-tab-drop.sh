#!/bin/sh
# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp /tmp/resketch-native-tab-drop.XXXXXX)
icon_data=$(mktemp -d /tmp/resketch-empty-icon-data.XXXXXX)
trap 'rm -f "$test_binary"; rm -rf "$icon_data"' EXIT
c++ -std=c++20 -DCEF_API_VERSION=15400 -fPIC tests/native-tab-drop.test.cpp src/FontHelper.cpp -Ibuild-cef/resketch_autogen/include -Isrc -I"${CEF_ROOT:?Set CEF_ROOT to the extracted distribution}" -I/usr/include/KF6/KNotifications -I/usr/include/KF6/KColorScheme -I/usr/include/KF6/KIconThemes \
    $(pkg-config --cflags --libs fontconfig freetype2 Qt6DBus Qt6Concurrent Qt6Widgets Qt6Network Qt6Quick Qt6QuickControls2 KF6WindowSystem) -lKF6Notifications -lKF6ColorScheme -lKF6IconThemes \
    -Lbuild-cef -lresketch_cef -Lbuild-cef/cef -lcef -Wl,-rpath,"$PWD/build-cef:$PWD/build-cef/cef" -o "$test_binary"
QT_NO_GLIB=1 RESKETCH_CEF_HELPER="$PWD/build-cef/resketch-cef-helper" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
    QT_QUICK_CONTROLS_STYLE=org.kde.desktop "$test_binary"
QT_NO_GLIB=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    XDG_DATA_DIRS="$icon_data" XDG_DATA_HOME="$icon_data" "$test_binary" --icons
