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

ReSketch allows `accounts.google.com` in sign-in popups and redirects while continuing to block other non-Figma pages. It shows Figma's normal web login in the main Home view and opens Google sign-in in a separate window. Both views share ReSketch's browser profile. Google may reject authentication in embedded browsers. ReSketch also accepts `figma://app_auth/redeem` callbacks when registered as the default handler, but callback redemption through Figma's web route has not been verified against a live account.

## Local fonts on Linux

ReSketch grants Figma's local-font browser permission and allows its requests to the local font helper. Figma's font picker still requires a helper process on Linux. Install [Figma Agent for Linux](https://github.com/neetly/figma-agent-linux) as your user, then in a Figma design file choose **Preferences → Permissions and helpers → Apps on device → Connect**. The helper detects fonts installed on the computer and starts on demand through its user service.

## Exports

Exporting a document or object opens a native folder picker. ReSketch remembers the last selected folder separately for each Figma file, including across restarts and file renames. The picker starts in that folder on the next export. Cancelling the picker cancels the download.

**File → Export History** lists completed exports from every file, newest first, with image/PDF previews. Open an export or its folder, or delete the exported file. **Clear Exports** clears only the list, leaving files on disk. The history persists across restarts; unsupported preview formats show a file icon.

Each entry includes the export's file type and originating Figma file name. Right-click an entry to copy its file path.

## Figma appearance

Figma follows **Settings → Appearance → App theme**, including system theme changes when set to Auto. The experimental **Use KDE colors** option applies the desktop palette to Figma's interface colors. **Enable custom CSS** reveals an editor for your own CSS rules; these take precedence over the palette overrides. Both options default to off, apply without restarting, and are restricted to Figma pages. Palette overrides do not change document/canvas colors. Figma's internal theme API and CSS tokens can change, so these integrations may need updates as Figma evolves.

**Translucent left and right sidebars** optionally uses the shared **Background opacity** slider. Choose **Desktop** to reveal the desktop with KDE blur (unless Ignore blur is enabled), or **Figma canvas** to show the canvas underneath. When Figma stops rendering its canvas at the sidebars, the canvas background color is used instead. Text and controls remain opaque, and the option defaults to off.

# DISCLOSURE!!

This contains AI-generated code. This app is simply made for my personal use and enjoyment and is in no way meant for professional or commercial use.
