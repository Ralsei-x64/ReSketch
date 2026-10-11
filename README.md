# ReSketch

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

ReSketch allows `accounts.google.com` in sign-in popups and redirects while continuing to block other non-Figma pages. It shows Figma's normal web login in the main Home view and opens Google sign-in in a separate window. Both views share ReSketch's browser profile. Google may reject authentication in embedded browsers. ReSketch also accepts `figma://app_auth/redeem` callbacks when registered as the default handler, but callback redemption through Figma's web route has not been verified against a live account.

## Local fonts on Linux

ReSketch grants Figma's local-font browser permission and allows its requests to the local font helper. Figma's font picker still requires a helper process on Linux. Install [Figma Agent for Linux](https://github.com/neetly/figma-agent-linux) as your user, then in a Figma design file choose **Preferences → Permissions and helpers → Apps on device → Connect**. The helper detects fonts installed on the computer and starts on demand through its user service.

Run `node tests/policy.test.js` to check the URL restriction and tab-title limit, and `node tests/figma-menu.test.js` to check menu conversion and command dispatch. `tests/tst_figma_menu.qml` checks that the native and popup menus share commands and update their states without rebuilding unchanged menus.

# DISCLOSURE!!

This contains AI-generated code. This app is simply made for my personal use and enjoyment and is in no way meant for professional or commercial use.
