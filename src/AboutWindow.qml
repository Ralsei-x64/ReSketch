// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: aboutWindow
    transientParent: null
    objectName: "aboutWindow"
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations

    width: 440
    height: 340
    minimumWidth: 360
    minimumHeight: 300
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: qsTr("About ReSketch")
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    pageStack.initialPage: Kirigami.Page {
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

        header: ExternalWindowHeader {
            targetWindow: aboutWindow
            title: qsTr("About ReSketch")
            iconName: "help-about"
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 112
                Layout.preferredHeight: 112
                source: "qrc:/Branding/SketchbookPNG/Folder-256.png"
                sourceSize.width: 256
                sourceSize.height: 256
                fillMode: Image.PreserveAspectFit
            }
            Kirigami.Heading {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("ReSketch")
                level: 1
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                objectName: "aboutVersion"
                text: qsTr("Version %1").arg(Qt.application.version)
                opacity: 0.75
            }
            Controls.Label {
                objectName: "aboutCommit"
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Commit %1").arg(appSettings.buildCommit)
                font: Kirigami.Theme.smallFont
                opacity: 0.75
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Open-source Figma client for Linux!")
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: qsTr("By Ralsei-x64")
                opacity: 0.75
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("GNU General Public License v3")
                opacity: 0.75
            }
        }
    }

    WindowResizeHandles {
        parent: aboutWindow.contentItem
        anchors.fill: parent
        active: aboutWindow.framelessControls
        targetWindow: aboutWindow
    }
}
