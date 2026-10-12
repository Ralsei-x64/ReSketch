// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as Controls

Controls.Menu {
    id: menu
    required property var appWindow
    required property var tabView
    title: qsTr("Tab groups")
    Controls.MenuItem {
        text: qsTr("New group")
        onTriggered: menu.appWindow.requestTabGroup(menu.tabView)
    }
    Instantiator {
        model: menu.appWindow.tabGroups
        delegate: Controls.MenuItem {
            required property var modelData
            text: modelData.title
            onTriggered: menu.appWindow.assignSelectedTabGroup(menu.tabView, modelData.id)
        }
        onObjectAdded: (index, object) => menu.insertItem(index + 1, object)
        onObjectRemoved: (index, object) => menu.removeItem(object)
    }
    Controls.MenuSeparator { }
    Controls.MenuItem {
        text: qsTr("Remove from group")
        enabled: menu.appWindow.tabsForAction(menu.tabView).some(view => !!view.tabGroupId)
        onTriggered: menu.appWindow.assignSelectedTabGroup(menu.tabView, "")
    }
}
