// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import Qt.labs.platform as Platform
import QtWebEngine
import "FigmaMenu.js" as FigmaMenu
import "Policy.js" as Policy

QtObject {
    id: controller
    required property var page
    required property var menuBar
    required property var popup
    required property var fileMenu
    required property var filePopup
    required property var preferencesMenu
    required property var preferencesPopup
    property bool integrationEnabled: true
    property var entries: []
    property string appliedSnapshot: ""
    property var inFlightViews: []
    property int retryDelay: 1000
    property int fileActionCount: 0
    property int preferencesActionCount: 0
    property var fileCache: ({})
    property int generation: 0
    property bool usingHomeMenu: true
    property bool fileMenuAvailable: false
    property bool pending: false
    property string lastError: ""
    property string theme: "auto"
    property bool homeAuthenticated: false
    readonly property bool homePage: !!page && (Policy.isFileBrowserUrl(page.url)
                                               || Policy.isNewFileTabUrl(page.url))

    readonly property string fileKey: {
        if (!page || !Policy.isFileUrl(page.url)) return ""
        const match = String(page.url).match(/^https:\/\/[^/]+\/(file|design|board|proto|slides|deck|site|buzz|make)\/([^/?#]+)/)
        return match ? match[1] + "/" + match[2] : ""
    }

    signal commandFailed(string message)
    signal applicationCommand(string command)

    property Component nativeMenu: Platform.Menu { }
    property Component nativeItem: Platform.MenuItem {
        property string commandId
        onTriggered: controller.trigger(commandId)
    }
    property Component nativeSeparator: Platform.MenuSeparator { }
    property Component popupMenu: Controls.Menu { }
    property Component popupItem: Controls.MenuItem {
        property string commandId
        onTriggered: controller.trigger(commandId)
    }
    property Component popupSeparator: Controls.MenuSeparator { }
    property Timer poll: Timer {
        interval: controller.retryDelay
        running: controller.integrationEnabled && !!controller.page && !controller.page.loading
                 && controller.page.lifecycleState === WebEngineView.LifecycleState.Active
        repeat: true
        onTriggered: controller.refresh()
    }

    property Timer requestTimeout: Timer {
        interval: 2000
        onTriggered: {
            ++controller.generation
            controller.pending = false
            controller.showFallback()
        }
    }
    property Connections pageState: Connections {
        target: controller.page
        function onLoadingChanged() {
            if (controller.page.loading) controller.reset()
            else controller.refresh()
        }
        function onLifecycleStateChanged() {
            if (controller.page.lifecycleState !== WebEngineView.LifecycleState.Active)
                controller.reset()
            else controller.refresh()
        }
    }

    onIntegrationEnabledChanged: reset()
    onPageChanged: reset()
    onFileKeyChanged: reset()
    onHomePageChanged: reset()
    onThemeChanged: {
        if (usingHomeMenu) update(FigmaMenu.homeMenus(theme, homeAuthenticated))
        Qt.callLater(refresh)
    }
    Component.onCompleted: reset()

    function reset() {
        ++generation
        pending = false
        requestTimeout.stop()
        homeAuthenticated = false
        retryDelay = 1000
        showFallback()
        Qt.callLater(refresh)
    }

    function showFallback() {
        fileMenuAvailable = false
        const cached = integrationEnabled && fileKey && fileCache[fileKey]
        usingHomeMenu = !cached
        update(cached || FigmaMenu.homeMenus(theme, homePage && homeAuthenticated), !!cached)
    }

    // Hard teardown; normal navigation reconciles existing menu objects instead.
    function clear() {
        for (const entry of entries)
            remove(entry, menuBar, popup)
        entries = []
        appliedSnapshot = ""
        fileActionCount = 0
        preferencesActionCount = 0
    }

    function detach(entry, nativeParent, popupParent) {
        if (entry.isMenu) nativeParent.removeMenu(entry.native)
        else nativeParent.removeItem(entry.native)
        for (let index = 0; index < popupParent.count; ++index) {
            if (entry.isMenu ? popupParent.menuAt(index) === entry.popup
                             : popupParent.itemAt(index) === entry.popup) {
                if (entry.isMenu) popupParent.takeMenu(index)
                else popupParent.takeItem(index)
                break
            }
        }
    }

    function remove(entry, nativeParent, popupParent) {
        if (entry.fixed) {
            for (const child of entry.children)
                remove(child, entry.native, entry.popup)
            return
        }
        // Detach descendants before Qt destroys their parent's native handle.
        for (const child of entry.children)
            remove(child, entry.native, entry.popup)
        detach(entry, nativeParent, popupParent)
        entry.native.destroy()
        entry.popup.destroy()
    }

    function refresh() {
        const view = page
        if (!integrationEnabled || pending || inFlightViews.includes(view)) return
        if (!view || view.loading
                || !/^https:\/\/www\.figma\.com\//.test(String(view.url))
                || view.lifecycleState !== WebEngineView.LifecycleState.Active) {
            showFallback()
            return
        }
        const token = generation
        const key = fileKey
        const home = homePage
        pending = true
        inFlightViews.push(view)
        requestTimeout.restart()
        view.runJavaScript(home ? FigmaMenu.homeScript() : FigmaMenu.script(), result => {
            inFlightViews = inFlightViews.filter(item => item !== view)
            if (!integrationEnabled || token !== generation || page !== view || fileKey !== key || homePage !== home) {
                Qt.callLater(refresh)
                return
            }
            pending = false
            requestTimeout.stop()
            try {
                const snapshot = JSON.parse(result)
                if (snapshot.error && snapshot.error !== lastError)
                    console.warn("Figma AppMenu:", snapshot.error)
                lastError = snapshot.error || ""
                if (home && !snapshot.error) {
                    retryDelay = 2000
                    homeAuthenticated = !!snapshot.authenticated
                    usingHomeMenu = true
                    fileMenuAvailable = false
                    update(FigmaMenu.homeMenus(theme, homeAuthenticated))
                } else if (key && !snapshot.error && snapshot.menus && snapshot.menus.length) {
                    retryDelay = 1000
                    fileCache[key] = snapshot.menus
                    usingHomeMenu = false
                    fileMenuAvailable = true
                    update(snapshot.menus)
                } else {
                    retryDelay = Math.min(8000, retryDelay * 2)
                    showFallback()
                }
            } catch (_) {
                retryDelay = Math.min(8000, retryDelay * 2)
                showFallback()
            }
        })
    }

    // Qt.labs.platform destroys handles when menus are reparented. Empty the
    // subtree first, then restore it, so no child retains a deleted widget.
    function takeNativeChildren(menu) {
        const children = Array.from(menu.items).map(item => ({item, menu: item.subMenu,
            children: item.subMenu ? takeNativeChildren(item.subMenu) : []}))
        for (const child of children) {
            if (child.menu) menu.removeMenu(child.menu)
            else menu.removeItem(child.item)
        }
        return children
    }

    function restoreNativeChildren(menu, children) {
        for (const child of children) {
            if (child.menu) {
                menu.addMenu(child.menu)
                restoreNativeChildren(child.menu, child.children)
            } else menu.addItem(child.item)
        }
    }

    function moveNative(entry, parent, index) {
        const children = entry.isMenu ? takeNativeChildren(entry.native) : []
        if (entry.isMenu) {
            parent.removeMenu(entry.native)
            parent.insertMenu(index, entry.native)
            restoreNativeChildren(entry.native, children)
        } else {
            parent.removeItem(entry.native)
            parent.insertItem(index, entry.native)
        }
    }

    function reconcile(previous, items, nativeParent, popupParent) {
        const next = []
        const available = previous.slice()
        for (let index = 0; index < items.length; ++index) {
            const item = items[index]
            const match = available.findIndex(entry => entry.id === item.id
                                              && entry.isMenu === !!item.children
                                              && entry.separator === !!item.separator)
            let entry = match < 0 ? null : available.splice(match, 1)[0]
            if (!entry) {
                const position = nativeParent === menuBar
                    ? index + (items[0]?.id === "figma/file-menu" ? 0 : 1) : index
                entry = create(item, nativeParent, popupParent, position)
            } else if (!entry.fixed && nativeParent !== menuBar) {
                const current = nativeParent.items.indexOf(entry.isMenu ? entry.native.menuItem : entry.native)
                if (current !== index) moveNative(entry, nativeParent, index)
                const quickIndex = popupIndex(popupParent, entry.popup, entry.isMenu)
                if (quickIndex !== index) popupParent.moveItem(quickIndex, index)
            }
            if (item.children)
                entry.children = reconcile(entry.children, item.children, entry.native, entry.popup)
            next.push(entry)
        }
        for (const entry of available)
            remove(entry, nativeParent, popupParent)
        return next
    }

    function popupIndex(parent, item, group) {
        for (let index = 0; index < parent.count; ++index)
            if (group ? parent.menuAt(index) === item : parent.itemAt(index) === item) return index
        return -1
    }

    function update(menus, disabled = false) {
        const snapshot = JSON.stringify([menus, disabled])
        if (snapshot === appliedSnapshot) return
        entries = reconcile(entries, menus, menuBar, popup)
        fileActionCount = menus.find(item => item.id === "figma/file-menu")?.children.length || 0
        preferencesActionCount = menus.find(item => item.id === "figma/preferences-menu")?.children.length || 0
        // File is always first. Preserve the shared Preferences and Help objects.
        const order = [fileMenu]
        const quickOrder = [filePopup]
        for (const entry of entries) {
            if (entry.native === fileMenu) continue
            order.push(entry.native)
            quickOrder.push(entry.popup)
        }
        if (!order.includes(preferencesMenu)) {
            order.push(preferencesMenu)
            quickOrder.push(preferencesPopup)
        }
        for (let index = 0; index < order.length; ++index) {
            if (menuBar.menus[index] !== order[index])
                moveNative({native: order[index], isMenu: true}, menuBar, index)
            const quickIndex = popupIndex(popup, quickOrder[index], true)
            if (quickIndex !== index) popup.moveItem(quickIndex, index)
        }
        for (let i = 0; i < menus.length; ++i)
            updateEntry(entries[i], menus[i], disabled)
        appliedSnapshot = snapshot
    }

    function create(item, nativeParent, popupParent, position = -1) {
        const group = !!item.children
        const isFile = item.id === "figma/file-menu"
        const isPreferences = item.id === "figma/preferences-menu"
        if (group && nativeParent === menuBar && (isFile || isPreferences)) {
            const targetMenu = isFile ? fileMenu : preferencesMenu
            const targetPopup = isFile ? filePopup : preferencesPopup
            return {id: item.id, native: targetMenu, popup: targetPopup, fixed: true,
                    isMenu: true, separator: false, children: []}
        }
        const native = (group ? nativeMenu : item.separator ? nativeSeparator : nativeItem)
                       .createObject(nativeParent, group || item.separator ? {} : {commandId: item.id})
        const quick = (group ? popupMenu : item.separator ? popupSeparator : popupItem)
                      .createObject(group ? popupParent : popupParent.contentItem,
                                    group || item.separator ? {} : {commandId: item.id})
        if (group) {
            if (position >= 0) {
                nativeParent.insertMenu(position, native)
                popupParent.insertMenu(position, quick)
            } else {
                nativeParent.addMenu(native)
                popupParent.addMenu(quick)
            }
        } else {
            if (position >= 0) {
                nativeParent.insertItem(position, native)
                popupParent.insertItem(position, quick)
            } else {
                nativeParent.addItem(native)
                popupParent.addItem(quick)
            }
        }
        return {id: item.id, native, popup: quick, isMenu: group,
                separator: !!item.separator, children: []}
    }

    function updateEntry(entry, item, disabled) {
        if (item.separator) return
        if (!entry.fixed) {
            entry.native.enabled = !disabled && item.enabled
            entry.popup.enabled = !disabled && item.enabled
        }
        if (item.children) {
            if (!entry.fixed) {
                const title = item.id === "figma/figma-account-menu" ? qsTr("Help") : item.text
                entry.native.title = title
                entry.popup.title = title
            }
            for (let i = 0; i < item.children.length; ++i)
                updateEntry(entry.children[i], item.children[i], disabled)
        } else {
            entry.native.text = item.text
            entry.native.shortcut = item.shortcut.replace(/⌫/g, "Backspace")
                                                .replace(/⌦/g, "Delete")
                                                .replace(/↑/g, "Up").replace(/↓/g, "Down")
                                                .replace(/←/g, "Left").replace(/→/g, "Right")
            entry.popup.text = item.text + (item.shortcut ? "\t" + item.shortcut : "")
            entry.native.checkable = entry.popup.checkable = !!item.checkable
            entry.native.checked = entry.popup.checked = !!item.checked
        }
    }

    function trigger(command) {
        if (command.startsWith("app/")) {
            if (usingHomeMenu) applicationCommand(command.slice(4))
            return
        }
        const view = page
        if (!integrationEnabled || !view || view.loading || view.lifecycleState !== WebEngineView.LifecycleState.Active) return
        if (!command.startsWith("home/") && !fileMenuAvailable) return
        if (command.startsWith("home/") && !homePage) return
        const token = generation
        view.runJavaScript(command.startsWith("home/") ? FigmaMenu.homeScript(command)
                                                      : FigmaMenu.script(command), result => {
            if (page !== view || token !== generation) return
            try {
                const response = JSON.parse(result)
                if (!response.executed)
                    commandFailed(response.error || qsTr("This Figma action is no longer available."))
            } catch (_) {
                commandFailed(qsTr("Figma could not run this action."))
            }
            refresh()
        })
    }
}
