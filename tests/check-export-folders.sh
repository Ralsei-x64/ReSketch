#!/bin/sh
# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only

set -eu
cd "$(dirname "$0")/.."
updater_moc=$(mktemp /tmp/resketch-updates-moc.XXXXXX.cpp)
test_binary=$(mktemp /tmp/resketch-export-folders.XXXXXX)
trap 'rm -f "$test_binary" "$updater_moc"' EXIT
/usr/lib/qt6/moc src/UpdateChecker.h -o "$updater_moc"
c++ -std=c++20 -DCEF_API_VERSION=15400 -fPIC tests/export-folders.test.cpp src/FontHelper.cpp src/UpdateChecker.cpp "$updater_moc" -Ibuild-cef/resketch_autogen/include -Isrc -I"${CEF_ROOT:?Set CEF_ROOT to the extracted distribution}" -I/usr/include/KF6/KNotifications -I/usr/include/KF6/KColorScheme -I/usr/include/KF6/KIconThemes \
    $(pkg-config --cflags --libs fontconfig freetype2 Qt6DBus Qt6Concurrent Qt6Widgets Qt6Network Qt6Quick Qt6QuickControls2 KF6WindowSystem) -lKF6Notifications -lKF6ColorScheme -lKF6IconThemes \
    -Lbuild-cef -lresketch_cef -Lbuild-cef/cef -lcef -Wl,-rpath,"$PWD/build-cef:$PWD/build-cef/cef" -o "$test_binary"
QT_QPA_PLATFORM=offscreen "$test_binary"
