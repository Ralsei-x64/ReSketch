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
    readonly property string version: afterRestart ? updater?.completedUpdate.version || ""
        : updater?.available.version || updater?.currentVersion || ""
    readonly property string notes: (updater?.completedUpdate.changelog || "")
        .replace(/^\d+\.\d+\.\d+ - [^\n]+\n+/, "").trim()
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(afterRestart ? 520 : 440, parent ? parent.width - 40 : 520)
    padding: 20
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
            Layout.topMargin: Kirigami.Units.largeSpacing
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
    closePolicy: afterRestart ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
    onOpened: afterRestart ? okayButton.forceActiveFocus() : finishButton.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Controls.Label {
            objectName: "updateRestartMessage"
            Layout.fillWidth: true
            visible: !dialog.afterRestart
            text: qsTr("To finish updating, ReSketch must restart.")
            wrapMode: Text.Wrap
        }
        Controls.Label {
            Layout.fillWidth: true
            visible: dialog.afterRestart
            text: qsTr("What’s new")
            font.weight: Font.DemiBold
        }
        Controls.Frame {
            objectName: "updatedVersionNotesCard"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Math.max(48, dialog.parent ? dialog.parent.height - 260 : 320),
                                            320, Math.max(80, notesText.contentHeight + 32))
            visible: dialog.afterRestart
            padding: 1
            contentItem: Controls.ScrollView {
                id: notesScroll
                clip: true
                contentWidth: availableWidth
                Controls.TextArea {
                    id: notesText
                    objectName: "updatedVersionChangelog"
                    text: dialog.notes
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnTab: false
                    padding: Kirigami.Units.largeSpacing
                    background: null
                }
            }
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
                objectName: "updateLaterButton"
                visible: !dialog.afterRestart
                text: qsTr("Update Later")
                implicitHeight: 36
                onClicked: dialog.reject()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            Controls.Button {
                id: finishButton
                objectName: "finishUpdateButton"
                visible: !dialog.afterRestart
                text: qsTr("Finish Update")
                icon.name: "view-refresh"
                highlighted: true
                implicitHeight: 36
                onClicked: dialog.updater.finishUpdate()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            Controls.Button {
                id: okayButton
                objectName: "acknowledgeUpdateButton"
                text: qsTr("Okay")
                visible: dialog.afterRestart
                highlighted: true
                implicitHeight: 36
                onClicked: { dialog.updater.dismissCompletedUpdate(); dialog.close() }
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
        }
    }
}
