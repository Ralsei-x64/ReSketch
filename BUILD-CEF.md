# CEF branch

Build on Arch with `packaging/arch/PKGBUILD`, or use CMake after installing the dependencies listed there:

```sh
cmake -S . -B build-cef -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-cef
./build-cef/resketch
```

The first configure downloads the pinned CEF SDK (about 311 MB). An extracted SDK can be supplied with `-DCEF_ROOT=/path/to/cef`. Installation includes CEF's runtime and subprocess helper; use `cmake --install build-cef --prefix ~/.local`.

CEF uses a separate profile, so sign in again. The original Qt profile is preserved.

For engine checks, configure with `-DRESKETCH_BUILD_TESTS=ON`, rebuild, then run `build-cef/cef-engine-test --gpu` or `QT_QPA_PLATFORM=offscreen build-cef/cef-engine-test`.
