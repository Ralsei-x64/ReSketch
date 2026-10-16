// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Dialog {
    id: dialog
    objectName: "updateChangelogDialog"
    property string version
    property string notes
    parent: Controls.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(700, parent ? parent.width - 40 : 700)
    height: Math.min(560, parent ? parent.height - 40 : 560)
    modal: true
    focus: true
    title: qsTr("Changelog — ReSketch %1").arg(version)
    standardButtons: Controls.Dialog.Close
    contentItem: Controls.ScrollView {
        clip: true
        contentWidth: availableWidth
        Controls.TextArea {
            text: dialog.notes
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
        }
    }
}
