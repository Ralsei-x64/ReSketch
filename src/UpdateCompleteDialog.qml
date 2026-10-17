// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    objectName: "updateCompleteDialog"
    required property var updater
    readonly property string version: updater?.available.version || ""
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(440, parent ? parent.width - 40 : 440)
    padding: 16
    modal: true
    focus: true
    title: qsTr("Update Complete")
    background: Rectangle {
        radius: 12
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.22)
    }
    header: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Heading {
            Layout.fillWidth: true
            Layout.leftMargin: dialog.leftPadding
            Layout.rightMargin: dialog.rightPadding
            Layout.topMargin: dialog.topPadding
            text: dialog.title
            level: 3
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }
        Controls.Label {
            objectName: "updatedVersionLabel"
            Layout.fillWidth: true
            Layout.leftMargin: dialog.leftPadding
            Layout.rightMargin: dialog.rightPadding
            text: qsTr("ReSketch %1").arg(dialog.version)
            opacity: 0.72
        }
    }
    closePolicy: Controls.Popup.CloseOnEscape
    onOpened: finishButton.forceActiveFocus()
    contentItem: Controls.Label {
        objectName: "updateRestartMessage"
        text: qsTr("To finish switching to the new version, ReSketch must restart.")
        wrapMode: Text.Wrap
    }

    footer: Controls.Control {
        leftPadding: dialog.leftPadding
        rightPadding: dialog.rightPadding
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: dialog.bottomPadding
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            Controls.Button {
                objectName: "updateLaterButton"
                text: qsTr("Update Later")
                implicitHeight: 36
                onClicked: dialog.reject()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            Controls.Button {
                id: finishButton
                objectName: "finishUpdateButton"
                text: qsTr("Finish Update")
                icon.name: "view-refresh"
                highlighted: true
                implicitHeight: 36
                onClicked: dialog.updater.finishUpdate()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
        }
    }
}
