// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    objectName: "updateAvailableDialog"
    required property var updater
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent ? parent.width - 40 : 520)
    padding: 20
    background: Rectangle {
        radius: 12
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.22)
    }
    header: Kirigami.Heading {
        text: dialog.title
        level: 3
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
        leftPadding: dialog.leftPadding
        rightPadding: dialog.rightPadding
        topPadding: Kirigami.Units.largeSpacing
    }
    modal: true
    focus: true
    onOpened: cancelButton.forceActiveFocus()
    title: qsTr("ReSketch has pending updates.")
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("There's new updates available to install.")
            wrapMode: Text.WordWrap
        }
        Controls.Label {
            objectName: "pendingUpdateVersion"
            text: (dialog.updater?.currentVersion || "") + "  →  " + (dialog.updater?.available.version || "")
            font.bold: true
        }
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
                id: cancelButton
                objectName: "cancelUpdateButton"
                text: qsTr("Cancel")
                implicitHeight: 36
                onClicked: dialog.reject()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            Controls.Button {
                objectName: "skipUpdateButton"
                text: qsTr("Skip Update")
                implicitHeight: 36
                onClicked: { dialog.updater.skipUpdate(); dialog.close() }
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            Controls.Button {
                objectName: "openUpdateButton"
                text: qsTr("View in GitHub")
                implicitHeight: 36
                onClicked: { dialog.updater.openRelease(); dialog.close() }
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
        }
    }
    Connections {
        target: dialog.updater
        function onChanged() { if (!dialog.updater.available.version) dialog.close() }
    }
}
