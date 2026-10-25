// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ReSketch.Cef

Controls.Menu {
    id: menu
    objectName: "extensionsMenu"
    required property var appWindow
    property var anchorItem: null
    readonly property var manager: appSettings.extensions ?? null
    function showExtension(key, options) {
        const page = manager?.extensionPage(key, options)
        if (!page || !page.toString()) return
        const entry = manager.extensions.find(e => e.key === key)
        if (options) {
            menu.appWindow.openExtensionWindow(page, entry?.name || qsTr("Extension"), key, null)
            return
        }
        extensionPopup.pageTitle = entry?.name || qsTr("Extension")
        extensionPopup.extensionKey = key
        extensionPopup.page = page
        const position = anchorItem ? anchorItem.mapToItem(menu.appWindow.contentItem, anchorItem.width, anchorItem.height) : Qt.point(appWindow.width, appWindow.tabStripHeight)
        extensionPopup.x = Math.max(0, Math.min(position.x - extensionPopup.width, appWindow.width - extensionPopup.width))
        extensionPopup.y = position.y
        extensionPopup.open()
    }
    Instantiator {
        model: menu.manager?.extensions ?? []
        delegate: Controls.Menu {
            id: extensionMenu
            required property var modelData
            title: extensionMenu.modelData.name
            icon.source: extensionMenu.modelData.icon || ""
            Controls.MenuItem {
                text: qsTr("Enabled")
                checkable: true
                checked: extensionMenu.modelData.enabled
                onTriggered: menu.manager.setExtensionEnabled(extensionMenu.modelData.key, !extensionMenu.modelData.enabled)
            }
            Controls.MenuItem {
                text: qsTr("Open popup")
                visible: !!extensionMenu.modelData.popup
                height: visible ? implicitHeight : 0
                enabled: extensionMenu.modelData.enabled && extensionMenu.modelData.loaded
                onTriggered: menu.showExtension(extensionMenu.modelData.key, false)
            }
            Controls.MenuItem {
                text: qsTr("Options")
                visible: !!extensionMenu.modelData.options
                height: visible ? implicitHeight : 0
                enabled: extensionMenu.modelData.enabled && extensionMenu.modelData.loaded
                onTriggered: menu.showExtension(extensionMenu.modelData.key, true)
            }
            Controls.MenuItem {
                text: qsTr("Remove")
                icon.name: "edit-delete"
                onTriggered: menu.manager.removeExtension(extensionMenu.modelData.key)
            }
        }
        onObjectAdded: (index, object) => menu.insertMenu(index, object)
        onObjectRemoved: (index, object) => menu.removeMenu(object)
    }
    Controls.MenuSeparator {}
    Controls.MenuItem {
        text: qsTr("Manage extensions…")
        icon.name: "configure"
        onTriggered: menu.appWindow.openExtensionSettings()
    }
    Controls.Popup {
        id: extensionPopup
        objectName: "extensionToolbarPopup"
        property string pageTitle: ""
        property string extensionKey: ""
        property url page: ""
        parent: menu.appWindow.contentItem
        popupType: Controls.Popup.Item
        width: Math.min(400, menu.appWindow.width - 20)
        height: Math.min(460, menu.appWindow.height - menu.appWindow.tabStripHeight - 12)
        focus: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
        contentItem: ColumnLayout {
            RowLayout {
                Controls.Label { Layout.fillWidth: true; text: extensionPopup.pageTitle; textFormat: Text.PlainText; elide: Text.ElideRight; font.bold: true; Layout.minimumWidth: 0 }
                Controls.ToolButton { text: qsTr("Close"); icon.name: "window-close"; onClicked: extensionPopup.close() }
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: extensionPopup.visible
                sourceComponent: ExtensionView {
                    appWindow: menu.appWindow
                    extensionKey: extensionPopup.extensionKey
                    onWindowCloseRequested: extensionPopup.close()
                    objectName: "toolbarExtensionView"
                    url: extensionPopup.page
                }
            }
        }
        Connections {
            target: menu.manager
            function onChanged() {
                if (!menu.manager.extensions.some(e => e.key === extensionPopup.extensionKey && e.loaded && e.enabled)) extensionPopup.close()
            }
        }
    }
}
