#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build --target resketch-export-folders-test
QT_QPA_PLATFORM=offscreen ./build/resketch-export-folders-test
