// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.ToolButton {
    id: button
    property var dragWindow: null
    property bool dimmed: false
    property bool animatePress: false
    property bool reduceMotion: appSettings.reduceMotion
    property color pressedTint: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                       Kirigami.Theme.highlightColor.g,
                                       Kirigami.Theme.highlightColor.b, 0.14)
    readonly property bool pressedFeedback: animatePress && enabled && !dimmed && (down || buttonTap.pressed)
    display: Controls.AbstractButton.IconOnly

    background: Rectangle {
        property real hoverAmount: button.hovered ? 1 : 0
        Behavior on hoverAmount {
            enabled: !button.reduceMotion
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        color: button.pressedFeedback ? button.pressedTint
             : hoverAmount > 0 ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                        Kirigami.Theme.highlightColor.g,
                                        Kirigami.Theme.highlightColor.b, 0.12 * hoverAmount)
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
            id: buttonTap
            enabled: !!button.dragWindow
            acceptedButtons: Qt.LeftButton
            onTapped: button.clicked()
        }

        Kirigami.Icon {
            objectName: "tabBarButtonIcon"
            scale: button.pressedFeedback ? 0.85 : 1
            Behavior on scale {
                enabled: !button.reduceMotion
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0, 0, 0, 1, 1, 1]
                }
            }
            width: button.icon.width
            height: button.icon.height
            anchors.centerIn: parent
            source: button.icon.name
            color: button.icon.color.a > 0 ? button.icon.color : Kirigami.Theme.textColor
            opacity: button.enabled && !button.dimmed ? 1 : 0.5
        }
    }
}
