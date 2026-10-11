#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp /tmp/resketch-export-folders.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
c++ -std=c++17 -fPIC tests/export-folders.test.cpp -Ibuild/resketch_autogen/include \
    $(pkg-config --cflags --libs Qt6Widgets Qt6Network Qt6Quick Qt6QuickControls2 Qt6WebEngineQuick KF6WindowSystem) \
    -o "$test_binary"
QT_QPA_PLATFORM=offscreen "$test_binary"
