// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Row {
    id: controls
    required property var targetWindow
    property int buttonSize: 40
    property int iconSize: Kirigami.Units.iconSizes.small
    property bool showMinimizeMaximize: true

    visible: appSettings.windowControlsInTabBar
    width: visible ? buttonSize * (showMinimizeMaximize ? 3 : 1) : 0
    height: buttonSize
    spacing: 0

    TabBarButton {
        visible: controls.showMinimizeMaximize
        width: controls.buttonSize
        height: controls.buttonSize
        icon.name: "window-minimize"
        icon.width: controls.iconSize
        icon.height: controls.iconSize
        Accessible.name: "Minimize window"
        Controls.ToolTip.text: Accessible.name
        Controls.ToolTip.visible: hovered
        onClicked: controls.targetWindow.showMinimized()
    }
    TabBarButton {
        objectName: "maximizeWindowButton"
        visible: controls.showMinimizeMaximize
        width: controls.buttonSize
        height: controls.buttonSize
        icon.name: controls.targetWindow.visibility === Window.Maximized ? "window-restore" : "window-maximize"
        icon.width: controls.iconSize
        icon.height: controls.iconSize
        Accessible.name: controls.targetWindow.visibility === Window.Maximized ? "Restore window" : "Maximize window"
        Controls.ToolTip.text: Accessible.name
        Controls.ToolTip.visible: hovered
        onClicked: {
            if (controls.targetWindow.visibility === Window.Maximized)
                controls.targetWindow.showNormal()
            else
                controls.targetWindow.showMaximized()
        }
    }
    TabBarButton {
        width: controls.buttonSize
        height: controls.buttonSize
        icon.name: "window-close"
        icon.width: controls.iconSize
        icon.height: controls.iconSize
        Accessible.name: "Close window"
        Controls.ToolTip.text: Accessible.name
        Controls.ToolTip.visible: hovered
        onClicked: controls.targetWindow.close()
    }
}
