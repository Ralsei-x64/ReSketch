# ReSketch

<img width="1920" height="1080" alt="Resketch (1)" src="https://github.com/user-attachments/assets/0d0f533b-29ff-486e-9d8b-93ffc1d0581a" />


A client for Figma which seeks to replace Figma-linux or using the webapp in your browser. It uses QT and kirigami for the UI and uses chromium to display Figma.

## Arch Linux (PKGBUILD)

Build and install, then launch ReSketch:

```sh
sudo pacman -S --needed base-devel git
git clone https://github.com/Ralsei-x64/ReSketch.git
cd ReSketch/packaging/arch
makepkg -si
resketch
```

The PKGBUILD installs dependencies and builds the latest `main` branch.

## Build from source

Requires Qt 6.8 or newer with Network, Quick, Quick Controls, WebEngine Quick, and Widgets, plus Kirigami, KF6 KWindowSystem, and the KDE desktop Qt Quick Controls style.

```sh
cmake -S . -B build -G Ninja
cmake --build build
./build/resketch
```

## Desktop links and sign in

Install the app and register it for Figma desktop links:

```sh
cmake --install build --prefix ~/.local
xdg-mime default org.aether64.resketch.desktop x-scheme-handler/figma
```


## License

Copyright © 2026 Ralsei-x64. ReSketch is licensed under the
GNU General Public License version 3 (`GPL-3.0-only`). See [LICENSE](LICENSE)
for the full license text.

## Disclosure

THIS PROJECT USES AI-GENERATED CODE!! That is not an indication that I support the use of AI in software development. I originally created this for my personal use only, choosing to distribute it because I think it's useful. 
