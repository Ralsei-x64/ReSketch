// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.ToolButton {
    id: button
    property var dragWindow: null
    property bool dimmed: false
    display: Controls.AbstractButton.IconOnly

    background: Rectangle {
        color: button.hovered ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                        Kirigami.Theme.highlightColor.g,
                                        Kirigami.Theme.highlightColor.b, 0.12)
                              : "transparent"
    }
    contentItem: Item {
        DragHandler {
            enabled: !!button.dragWindow
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: {
                if (active)
                    button.dragWindow.startSystemMove()
            }
        }
        TapHandler {
            enabled: !!button.dragWindow
            acceptedButtons: Qt.LeftButton
            onTapped: button.clicked()
        }

        Kirigami.Icon {
            width: button.icon.width
            height: button.icon.height
            anchors.centerIn: parent
            source: button.icon.name
            color: button.icon.color.a > 0 ? button.icon.color : Kirigami.Theme.textColor
            opacity: button.enabled && !button.dimmed ? 1 : 0.5
        }
    }
}
