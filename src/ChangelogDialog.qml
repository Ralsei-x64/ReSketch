// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    objectName: "updateChangelogDialog"
    property string version
    property string notes
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(520, parent ? parent.width - 40 : 520)
    height: Math.min(560, parent ? parent.height - 40 : 560,
                     notesText.contentHeight + topPadding + bottomPadding
                     + implicitHeaderHeight + implicitFooterHeight + spacing * 2)
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
        topPadding: dialog.topPadding
    }
    onOpened: closeButton.forceActiveFocus()
    modal: true
    focus: true
    title: qsTr("Changelog — ReSketch %1").arg(version)
    contentItem: Controls.ScrollView {
        clip: true
        contentWidth: availableWidth
        Controls.TextArea {
            id: notesText
            text: dialog.notes
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            padding: 0
            background: null
        }
    }
    footer: Controls.Control {
        leftPadding: dialog.leftPadding
        rightPadding: dialog.rightPadding
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: dialog.bottomPadding
        contentItem: RowLayout {
            Item { Layout.fillWidth: true }
            Controls.Button {
                id: closeButton
                text: qsTr("Close")
                implicitHeight: 36
                onClicked: dialog.close()
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
        }
    }
}
