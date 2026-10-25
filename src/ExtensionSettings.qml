// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: panel
    readonly property var manager: appSettings.extensions ?? null
    required property var appWindow
    spacing: Kirigami.Units.largeSpacing
    function showExtension(key, options) {
        const page = manager?.extensionPage(key, options)
        const entry = manager?.extensions.find(e => e.key === key)
        if (page && String(page)) appWindow?.openExtensionWindow(page, entry?.name || qsTr("Extension"), key, null)
    }
    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: !!panel.manager?.error
        text: panel.manager?.error ?? ""
        type: Kirigami.MessageType.Error
    }
    SettingsGroup {
        Layout.fillWidth: true
        title: qsTr("Custom Chrome extensions")
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Load a trusted Manifest V3 .crx package. Packages run locally as unpacked extensions with their declared permissions; store signatures are not verified. Reload existing tabs after enabling or disabling a custom extension to apply content-script changes.")
            wrapMode: Text.WordWrap
        }
        Controls.Button {
            objectName: "loadCrxExtension"
            text: qsTr("Load .crx file…")
            icon.name: "document-open"
            enabled: !!panel.manager?.available
            onClicked: panel.manager.choosePackage()
        }
        Repeater {
            model: panel.manager?.extensions ?? []
            delegate: Controls.Frame {
                id: extensionCard
                objectName: "extensionCard-" + modelData.key
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                contentItem: ColumnLayout {
                    RowLayout {
                        Layout.fillWidth: true
                        Kirigami.Icon {
                            source: extensionCard.modelData.icon || "application-x-addon"
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            objectName: "extensionName-" + extensionCard.modelData.key
                            text: extensionCard.modelData.name
                            textFormat: Text.PlainText
                            font.bold: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.WordWrap
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: qsTr("Version %1").arg(extensionCard.modelData.version)
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: extensionCard.modelData.error || (extensionCard.modelData.enabled ? (extensionCard.modelData.loaded ? qsTr("Loaded") : qsTr("Loading…")) : qsTr("Disabled"))
                        wrapMode: Text.WordWrap
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: extensionCard.modelData.permissions.length ? qsTr("Permissions: %1").arg(extensionCard.modelData.permissions.join(", ")) : qsTr("No extra permissions")
                        wrapMode: Text.WrapAnywhere
                        opacity: 0.8
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.CheckBox {
                            objectName: "extensionEnabled-" + extensionCard.modelData.key
                            text: qsTr("Enabled")
                            checked: extensionCard.modelData.enabled
                            enabled: !!panel.manager?.available
                            onToggled: panel.manager.setExtensionEnabled(extensionCard.modelData.key, checked)
                        }
                        Controls.Button {
                            visible: !!extensionCard.modelData.popup
                            enabled: extensionCard.modelData.loaded && extensionCard.modelData.enabled
                            text: qsTr("Open popup")
                            objectName: "extensionPopup-" + extensionCard.modelData.key
                            onClicked: panel.showExtension(extensionCard.modelData.key, false)
                        }
                        Controls.Button {
                            visible: !!extensionCard.modelData.options
                            enabled: extensionCard.modelData.loaded && extensionCard.modelData.enabled
                            text: qsTr("Options")
                            objectName: "extensionOptions-" + extensionCard.modelData.key
                            onClicked: panel.showExtension(extensionCard.modelData.key, true)
                        }
                        Controls.Button {
                            objectName: "extensionRemove-" + extensionCard.modelData.key
                            text: qsTr("Remove")
                            icon.name: "edit-delete"
                            onClicked: panel.manager.removeExtension(extensionCard.modelData.key)
                        }
                    }
                }
            }
        }
        Controls.Label {
            visible: !(panel.manager?.extensions.length ?? 0)
            text: qsTr("No custom extensions loaded.")
        }
    }
}
