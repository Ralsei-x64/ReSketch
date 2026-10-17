// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page
    required property var updater
    spacing: Kirigami.Units.largeSpacing
    Controls.Frame {
        Layout.fillWidth: true
        padding: Kirigami.Units.largeSpacing
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                objectName: "legacyBranchHeading"
                Layout.fillWidth: true
                level: 3
                text: qsTr("You're on the Legacy branch.")
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                Layout.fillWidth: true
                text: qsTr("Switch to the new version of ReSketch on the main branch.")
                wrapMode: Text.WordWrap
            }
            Controls.Button {
                objectName: "switchToMainButton"
                text: page.updater?.installed ? qsTr("Finish Update") : qsTr("Switch to New Version")
                icon.name: "view-refresh"
                enabled: !!page.updater && (page.updater.canMigrate || page.updater.installed)
                onClicked: page.updater.installed ? page.updater.finishUpdate() : page.updater.migrateToMain()
            }
            Controls.ProgressBar {
                objectName: "updateProgressBar"
                Layout.fillWidth: true
                visible: !!page.updater?.installing
                indeterminate: (page.updater?.downloadProgress ?? 0) < 0
                value: page.updater?.downloadProgress ?? 0
            }
            Controls.Label {
                objectName: "updateInstallStatus"
                Layout.fillWidth: true
                visible: !!page.updater?.installStatus || !!page.updater?.installError
                text: page.updater?.installError || page.updater?.installStatus || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Controls.Button {
                objectName: "cancelMigrationButton"
                text: qsTr("Cancel update")
                visible: !!page.updater?.downloading
                onClicked: page.updater.cancelDownload()
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: !page.updater?.installed
                text: qsTr("Installs the new version system-wide. Administrator authentication is required; Arch Linux on x86_64 and polkit must be installed.")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.7
            }
        }
    }
}
