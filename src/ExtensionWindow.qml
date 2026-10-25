// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import org.kde.kirigami as Kirigami

Window {
    id: extensionWindow
    objectName: "extensionWindow"
    required property var appWindow
    property string extensionKey: ""
    property string pageTitle: qsTr("Extension")
    property alias webView: page
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    width: 800
    height: 680
    minimumWidth: 400
    minimumHeight: 300
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    title: qsTr("ReSketch — %1").arg(page.title || pageTitle)
    color: Kirigami.Theme.backgroundColor
    transientParent: null

    ExtensionView {
        id: page
        objectName: "extensionWindowView"
        anchors.fill: parent
        anchors.topMargin: header.height
        appWindow: extensionWindow.appWindow
        extensionKey: extensionWindow.extensionKey
        standalone: true
        onWindowCloseRequested: extensionWindow.close()
    }
    ExternalWindowHeader {
        id: header
        targetWindow: extensionWindow
        width: parent.width
        height: appSettings.windowControlsInTabBar ? implicitHeight : 0
        visible: height > 0
        title: page.title || extensionWindow.pageTitle
        iconName: "application-x-addon"
        showMinimizeMaximize: true
    }
    WindowResizeHandles {
        anchors.fill: parent
        active: extensionWindow.framelessControls
        targetWindow: extensionWindow
    }
    Connections {
        target: appSettings.extensions
        function onChanged() {
            if (extensionWindow.extensionKey && !appSettings.extensions.extensions.some(
                    e => e.key === extensionWindow.extensionKey && e.enabled && e.loaded))
                extensionWindow.close()
        }
    }
    onClosing: {
        appWindow.extensionWindows = appWindow.extensionWindows.filter(window => window !== extensionWindow)
        Qt.callLater(() => extensionWindow.destroy())
    }
}
