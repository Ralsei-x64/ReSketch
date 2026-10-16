// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: page
    required property var updater
    readonly property var release: updater ? updater.available : ({})
    readonly property bool showCurrent: !!updater && updater.checked && !updater.checking && !updater.error && !release.version
    readonly property string notes: showCurrent ? updater.currentChangelog : release.changelog || ""
    spacing: Kirigami.Units.largeSpacing
    Controls.Frame {
        Layout.fillWidth: true
        padding: Kirigami.Units.largeSpacing
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    objectName: "updateStatusHeading"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.WordWrap
                    level: 3
                    text: page.updater?.checking ? qsTr("Checking for updates…")
                        : page.release.version ? qsTr("Update Found")
                        : page.updater?.error ? qsTr("Couldn't fetch updates.")
                        : page.updater?.checked ? qsTr("You're already on the newest version!") : qsTr("Updates")
                }
                Controls.Button {
                    objectName: "checkForUpdatesButton"
                    text: qsTr("Check for updates")
                    icon.name: "view-refresh"
                    enabled: !!page.updater && !page.updater.checking
                    onClicked: page.updater.checkForUpdates()
                }
            }
            Controls.Label {
                objectName: "updateVersionLabel"
                Layout.fillWidth: true
                visible: !!page.release.version || page.showCurrent
                text: page.showCurrent ? page.updater.currentVersion
                    : (page.updater?.currentVersion || "") + "  →  " + (page.release.version || "")
                font.bold: true
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: !page.updater?.error
                text: qsTr("Branch: %1").arg(page.updater?.branch || "")
                opacity: 0.7
            }
            Controls.Label {
                objectName: "updateChangelogPreview"
                Layout.fillWidth: true
                visible: !!page.release.version || page.showCurrent
                text: page.notes
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            Controls.Button {
                objectName: "viewChangelogButton"
                visible: !!page.release.version || page.showCurrent
                text: qsTr("View entire changelog")
                flat: true
                onClicked: changelog.open()
            }
            Controls.Button {
                objectName: "viewUpdateOnGitHubButton"
                visible: !!page.release.version
                text: qsTr("View in GitHub")
                icon.name: "document-open"
                onClicked: page.updater.openRelease()
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: !page.release.version && !page.showCurrent && !page.updater?.error
                text: qsTr("Current version: %1").arg(page.updater?.currentVersion || "")
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                opacity: 0.75
            }
        }
    }
    Kirigami.FormLayout {
        Layout.fillWidth: true
        Controls.CheckBox {
            objectName: "startupUpdateCheck"
            text: qsTr("Check for updates at startup")
            checked: !!page.updater && page.updater.enabled
            onToggled: if (page.updater) page.updater.enabled = checked
        }
        Controls.ComboBox {
            objectName: "updateBranchCombo"
            Kirigami.FormData.label: qsTr("Update branch:")
            model: [qsTr("CEF (resketch-cef)"), qsTr("Qt WebEngine (main)")]
            currentIndex: page.updater?.branch === "main" ? 1 : 0
            enabled: !!page.updater
            onActivated: {
                page.updater.branch = currentIndex === 1 ? "main" : "resketch-cef"
                page.updater.checkForUpdates()
            }
        }
    }
    ChangelogDialog {
        id: changelog
        version: page.showCurrent ? page.updater.currentVersion : page.release.version || ""
        notes: page.notes
    }
}
