// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import ReSketch.Cef

CefView {
    id: view
    required property var appWindow
    property string extensionKey: ""
    property bool standalone: false

    profile: CefProfile { storageName: "resketch"; persistentStoragePath: appSettings.profileStoragePath }

    onNavigationRequested: request => {
        if (!request.isMainFrame) return
        const address = String(request.url)
        if (/^https?:\/\//i.test(address)) {
            if (!standalone) {
                request.reject()
                appWindow.openExtensionWindow(address, title, extensionKey, null)
            }
        } else if (!/^chrome-extension:\/\//i.test(address) && address !== "about:blank") {
            request.reject()
        }
    }
    onNewWindowRequested: request => {
        appWindow.openExtensionWindow(request.requestedUrl, title, extensionKey, request)
    }
}
