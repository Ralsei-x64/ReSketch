// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Rectangle {
    id: header
    required property var targetWindow
    property string title: targetWindow.title
    property string iconName
    property bool showMinimizeMaximize: false
    property alias actions: headerActions.data
    readonly property real titleInset: Math.max(headerIcon.x + headerIcon.width,
                                               rightControls.width) + Kirigami.Units.largeSpacing
    objectName: "externalWindowHeader"
    implicitHeight: Math.max(36, Math.round(Kirigami.Units.gridUnit * 2))
    height: implicitHeight
    color: Kirigami.Theme.backgroundColor

    Item {
        width: Math.max(0, rightControls.x)
        height: parent.height
        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) header.targetWindow.startSystemMove()
        }
        TapHandler {
            enabled: header.showMinimizeMaximize
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                if (header.targetWindow.visibility === Window.Maximized)
                    header.targetWindow.showNormal()
                else
                    header.targetWindow.showMaximized()
            }
        }
    }
    Kirigami.Icon {
        id: headerIcon
        objectName: "externalWindowIcon"
        x: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.small
        height: width
        source: header.iconName
    }
    Controls.Label {
        objectName: "externalWindowTitle"
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 2 * header.titleInset)
        text: header.title
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font: Kirigami.Theme.defaultFont
        opacity: header.targetWindow.active ? 1 : 0.7
    }
    Row {
        id: rightControls
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        Row { id: headerActions; spacing: 0 }
        WindowControls {
            objectName: "externalWindowControls"
            targetWindow: header.targetWindow
            buttonSize: header.height
            showMinimizeMaximize: header.showMinimizeMaximize
        }
    }
    Rectangle {
        objectName: "externalWindowSeparator"
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Kirigami.Theme.textColor
        opacity: 0.2
    }
}
