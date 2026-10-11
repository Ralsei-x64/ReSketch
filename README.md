<img width="460" height="166" alt="ReSketch" src="https://github.com/user-attachments/assets/5975be6e-a445-4476-857a-f715c030b083" />

A client for Figma which seeks to replace Figma-linux or using the webapp in your browser. It uses QT and kirigami for the UI and uses chromium to display Figma.

## Build and run

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


## DISCLOSURE!!

This contains AI-generated code. This app is simply made for my personal use and enjoyment and is in no way meant for professional or commercial use.
