// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page
    required property var updater
    readonly property bool managedBySystem: !!updater?.managedBySystem
    spacing: Kirigami.Units.largeSpacing
    Controls.Frame {
        objectName: "updateControls"
        Layout.fillWidth: true
        padding: Kirigami.Units.largeSpacing
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                objectName: "legacyBranchHeading"
                Layout.fillWidth: true
                level: 3
                text: page.managedBySystem ? qsTr("Updates are disabled") : qsTr("You're on the Legacy branch.")
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                objectName: "managedUpdatesDescription"
                Layout.fillWidth: true
                text: page.managedBySystem ? qsTr("Updates are managed by your package manager.")
                    : qsTr("Switch to the new version of ReSketch on the main branch.")
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                objectName: "updateVersionLabel"
                Layout.fillWidth: true
                visible: page.managedBySystem
                text: qsTr("Current version: %1").arg(page.updater?.currentVersion || "")
                font.bold: true
            }
            Controls.Button {
                objectName: "viewChangelogButton"
                visible: page.managedBySystem
                text: qsTr("View Changelog")
                icon.name: "text-x-generic"
                onClicked: changelog.open()
            }
            Controls.Button {
                objectName: "switchToMainButton"
                visible: !page.managedBySystem
                text: page.updater?.installed ? qsTr("Finish Update") : qsTr("Switch to New Version")
                icon.name: "view-refresh"
                enabled: !!page.updater && (page.updater.canMigrate || page.updater.installed)
                onClicked: page.updater.installed ? page.updater.finishUpdate() : page.updater.migrateToMain()
            }
            Controls.ProgressBar {
                objectName: "updateProgressBar"
                Layout.fillWidth: true
                visible: !page.managedBySystem && !!page.updater?.installing
                indeterminate: (page.updater?.downloadProgress ?? 0) < 0
                value: page.updater?.downloadProgress ?? 0
            }
            Controls.Label {
                objectName: "updateInstallStatus"
                Layout.fillWidth: true
                visible: !page.managedBySystem && (!!page.updater?.installStatus || !!page.updater?.installError)
                text: page.updater?.installError || page.updater?.installStatus || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Controls.Button {
                objectName: "cancelMigrationButton"
                text: qsTr("Cancel update")
                visible: !page.managedBySystem && !!page.updater?.downloading
                onClicked: page.updater.cancelDownload()
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: !page.managedBySystem && !page.updater?.installed
                text: qsTr("Installs the new version system-wide. Administrator authentication is required; Arch Linux on x86_64 and polkit must be installed.")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.7
            }
        }
    }
    ChangelogDialog {
        id: changelog
        version: page.updater?.currentVersion || ""
        notes: page.updater?.currentChangelog || ""
    }
}
