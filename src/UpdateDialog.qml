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
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            font.bold: true
        }
    }
    footer: Controls.DialogButtonBox {
        Controls.Button {
            id: cancelButton
            objectName: "cancelUpdateButton"
            text: qsTr("Cancel")
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
        }
        Controls.Button {
            objectName: "skipUpdateButton"
            text: qsTr("Skip Update")
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: { dialog.updater.skipUpdate(); dialog.close() }
        }
        Controls.Button {
            objectName: "openUpdateButton"
            text: qsTr("View in GitHub")
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: { dialog.updater.openRelease(); dialog.close() }
        }
        onRejected: dialog.reject()
    }
    Connections {
        target: dialog.updater
        function onChanged() { if (!dialog.updater.available.version) dialog.close() }
    }
}
