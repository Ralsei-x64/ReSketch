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
    width: Math.min(afterRestart ? 560 : 460, parent ? parent.width - 40 : 560)
    padding: 24
    topPadding: 0
    bottomPadding: 20
    modal: true
    focus: true
    title: qsTr("Update Complete")
    background: Rectangle {
        radius: 16
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.18)
    }
    header: Controls.Control {
        leftPadding: 24
        rightPadding: 24
        topPadding: 24
        bottomPadding: 20
        contentItem: RowLayout {
            spacing: 16
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 12
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.14)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 26
                    height: width
                    source: dialog.afterRestart ? "dialog-ok-apply" : "view-refresh"
                    color: Kirigami.Theme.highlightColor
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Kirigami.Heading {
                    Layout.fillWidth: true
                    text: dialog.title
                    level: 2
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                Controls.Label {
                    objectName: "updatedVersionLabel"
                    text: qsTr("ReSketch %1").arg(dialog.version)
                    opacity: 0.72
                    font.weight: Font.Medium
                }
            }
        }
    }
    closePolicy: afterRestart ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape
    onOpened: afterRestart ? okayButton.forceActiveFocus() : finishButton.forceActiveFocus()
    contentItem: ColumnLayout {
        spacing: 12
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
            background: Rectangle {
                radius: 10
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.035)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.10)
            }
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
                    padding: 15
                    background: null
                }
            }
        }
    }
    footer: Controls.Control {
        leftPadding: 24
        rightPadding: 24
        topPadding: 16
        bottomPadding: 20
        background: Item {
            Rectangle {
                x: 24
                width: parent.width - 48
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.10)
            }
        }
        contentItem: RowLayout {
            spacing: 10
            Item { Layout.fillWidth: true }
            Controls.Button {
                objectName: "updateLaterButton"
                visible: !dialog.afterRestart
                text: qsTr("Update Later")
                Layout.minimumWidth: 112
                Layout.minimumHeight: 36
                onClicked: dialog.reject()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
            Controls.Button {
                id: finishButton
                objectName: "finishUpdateButton"
                visible: !dialog.afterRestart
                text: qsTr("Finish Update")
                icon.name: "view-refresh"
                highlighted: true
                Layout.minimumWidth: 136
                Layout.minimumHeight: 36
                onClicked: dialog.updater.finishUpdate()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
            Controls.Button {
                id: okayButton
                objectName: "acknowledgeUpdateButton"
                text: qsTr("Okay")
                visible: dialog.afterRestart
                highlighted: true
                Layout.minimumWidth: 112
                Layout.minimumHeight: 36
                onClicked: { dialog.updater.dismissCompletedUpdate(); dialog.close() }
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
        }
    }
}
