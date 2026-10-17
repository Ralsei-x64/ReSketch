// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    objectName: afterRestart ? "updatedVersionDialog" : "updateCompleteDialog"
    required property var updater
    property bool afterRestart: false
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(afterRestart ? 600 : 480, parent ? parent.width - 40 : 480)
    modal: true
    focus: true
    title: qsTr("Update Complete")
    header: Kirigami.Heading {
        text: dialog.title
        level: 3
        padding: Kirigami.Units.largeSpacing
    }
    closePolicy: afterRestart ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
    onOpened: afterRestart ? okayButton.forceActiveFocus() : finishButton.forceActiveFocus()
    contentItem: ColumnLayout {
        Controls.Label {
            Layout.fillWidth: true
            visible: !dialog.afterRestart
            text: qsTr("To finish updating, ReSketch must restart.")
            wrapMode: Text.Wrap
        }
        Controls.Label {
            objectName: "updatedVersionLabel"
            Layout.fillWidth: true
            visible: dialog.afterRestart
            text: dialog.updater?.completedUpdate.version || ""
            font.bold: true
            font.pointSize: 16
        }
        Controls.ScrollView {
            clip: true
            contentWidth: availableWidth
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, dialog.parent ? dialog.parent.height - 220 : 300)
            visible: dialog.afterRestart
            Controls.TextArea {
                objectName: "updatedVersionChangelog"
                text: dialog.updater?.completedUpdate.changelog || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                readOnly: true
                selectByMouse: true
            }
        }
    }
    footer: Controls.DialogButtonBox {
        Controls.Button {
            objectName: "updateLaterButton"
            visible: !dialog.afterRestart
            text: qsTr("Update Later")
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
        }
        Controls.Button {
            id: finishButton
            objectName: "finishUpdateButton"
            visible: !dialog.afterRestart
            text: qsTr("Finish Update")
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: dialog.updater.finishUpdate()
        }
        Controls.Button {
            id: okayButton
            objectName: "acknowledgeUpdateButton"
            text: qsTr("Okay")
            visible: dialog.afterRestart
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: { dialog.updater.dismissCompletedUpdate(); dialog.close() }
        }
        onRejected: dialog.reject()
    }
}
