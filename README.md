# ReSketch

<img width="1920" height="1080" alt="Resketch (1)" src="https://github.com/user-attachments/assets/0d0f533b-29ff-486e-9d8b-93ffc1d0581a" />

A client for Figma which seeks to replace Figma-linux or using the webapp in your browser. It uses QT and kirigami for the UI and uses chromium to display Figma.

This is the CEF version which will replace the version in the main repo. Very broken, very much a work in progress.

## Arch Linux (PKGBUILD)

Build and install, then launch ReSketch:

```sh
sudo pacman -S --needed base-devel git
git clone --branch resketch-cef https://github.com/Ralsei-x64/ReSketch.git
cd ReSketch/packaging/arch
makepkg -si
resketch
```

The PKGBUILD installs dependencies and builds the latest `resketch-cef` branch.

## Build from source

Requires CMake, Ninja, a C++20 compiler, Qt 6.8+ (Concurrent, Network, Quick, Quick Controls, OpenGL, Widgets), Kirigami, KF6 KWindowSystem and KNotifications, Fontconfig, FreeType, GTK3, GLib, EGL, and the KDE desktop Qt Quick Controls style. CMake downloads CEF automatically.

```sh
cmake -S . -B build-cef -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-cef
./build-cef/resketch
```

## Desktop links and sign in

Install the app and register it for Figma desktop links:

```sh
cmake --install build-cef --prefix ~/.local
xdg-mime default org.aether64.resketch.desktop x-scheme-handler/figma
```


## License

Copyright © 2026 Ralsei-x64. ReSketch is licensed under the
GNU General Public License version 3 (`GPL-3.0-only`). See [LICENSE](LICENSE)
for the full license text.

## Disclosure

THIS PROJECT USES AI-GENERATED CODE!! That is not an indication that I support the use of AI in software development. I originally created this for my personal use only, choosing to distribute it because I think it's useful. 
