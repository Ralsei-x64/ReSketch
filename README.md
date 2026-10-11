<img width="460" height="166" alt="ReSketch" src="https://github.com/user-attachments/assets/5975be6e-a445-4476-857a-f715c030b083" />

A client for Figma which seeks to replace Figma-linux or using the webapp in your browser. It uses QT and kirigami for the UI and uses chromium to display Figma.

## Build and run

With Nix and flakes enabled, build and launch the app with:

```sh
nix run
```

The flake provides the Qt/KDE build and runtime dependencies on x86_64 and
aarch64 Linux. To build without launching, use `nix build`; the executable is
then available at `./result/bin/resketch`. Run `nix flake check` to build the app
and run the JavaScript, export/history, and theme-switching tests.

For development, enter `nix develop`, then use the CMake commands below.
The shell also includes Node.js and pkg-config for the tests in `tests/`.
Run the C++ tests after building with `ctest --test-dir build --output-on-failure`.

Requires Qt 6.8 or newer with Network, Quick, Quick Controls, WebEngine Quick, and Widgets, plus Kirigami, KF6 KWindowSystem, KF6 KColorScheme (6.6 or newer), KF6 KIconThemes (6.3 or newer), the KDE desktop Qt Quick Controls style, Breeze icons, and the Breeze light/dark color schemes.

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


## DISCLOSURE!!

This contains AI-generated code. This app is simply made for my personal use and enjoyment and is in no way meant for professional or commercial use.
