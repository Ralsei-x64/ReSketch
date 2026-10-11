<img width="460" height="166" alt="ReSketch" src="https://github.com/user-attachments/assets/5975be6e-a445-4476-857a-f715c030b083" />

A client for Figma which seeks to replace Figma-linux or using the webapp in your browser. It uses QT and kirigami for the UI and uses chromium to display Figma.

## Build and run

Requires Qt 6.8 or newer with Network, Quick, Quick Controls, WebEngine Quick, and Widgets, plus Kirigami, KF6 KWindowSystem, and the KDE desktop Qt Quick Controls style.

```sh
cmake -S . -B build -G Ninja
cmake --build build
./build/resketch
```

## Recovering broken settings

Hold **Alt** while launching ReSketch until its window appears to open **Safe Mode Settings**.
You can also run `resketch --safe-mode`. Safe mode uses software rendering and opens
only Settings, bypassing Chromium, custom switches, Figma modifications, and UI
effects. It leaves your saved preferences intact so you can repair them, then
close the window and restart normally.

**Reset Settings** at the bottom restores default preferences without removing
your Figma sign-in, export history, or remembered export folders.

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

This project contains AI-generated code and started as a personal project.
