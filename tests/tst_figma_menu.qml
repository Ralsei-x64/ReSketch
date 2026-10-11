// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import Qt.labs.platform as Platform
import QtTest
import "../src" as App

Item {
    Controls.ApplicationWindow {
        id: testWindow
        width: 640
        height: 480
        visible: true
        Platform.MenuBar {
            id: bar
            window: testWindow
            Platform.Menu {
                id: fileMenu
                title: "File"
                Platform.MenuItem { text: "Home" }
            }
            Platform.Menu {
                id: preferencesMenu
                title: "Preferences"
                Platform.MenuItem { text: "Settings" }
            }
        }
        Controls.Menu {
            id: popup
            Controls.Menu {
                id: filePopup
                title: "File"
                Controls.MenuItem { text: "Home" }
            }
            Controls.Menu {
                id: preferencesPopup
                title: "Preferences"
                Controls.MenuItem { text: "Settings" }
            }
        }
        QtObject {
            id: view
            property bool loading: false
            property int lifecycleState: 0
            property url url: "about:blank"
            property string lastScript: ""
            property var response: ({authenticated: true})
            property bool defer: false
            property var callbacks: []
            function runJavaScript(script, callback) {
                lastScript = script
                if (defer) callbacks.push(callback)
                else callback(script.endsWith('("")') ? JSON.stringify(response) : '{"executed":true}')
            }
        }
        App.FigmaMenus {
            id: menus
            page: view
            menuBar: bar
            popup: popup
            fileMenu: fileMenu
            filePopup: filePopup
            preferencesMenu: preferencesMenu
            preferencesPopup: preferencesPopup
        }

        SignalSpy { id: commands; target: menus; signalName: "applicationCommand" }

        TestCase {
            name: "FigmaNativeMenus"
            when: windowShown
            function init() {
                menus.integrationEnabled = true
                menus.inFlightViews = []
                view.defer = false
                view.callbacks = []
                view.response = {authenticated: true}
                view.loading = false
                view.lifecycleState = 0
                view.url = "about:blank"
                menus.fileCache = ({})
                menus.page = view
                wait(0)
                menus.clear()
                commands.clear()
            }
            function test_native_and_popup_share_commands_and_states() {
                const snapshot = [{id: "figma/view-menu", text: "View", enabled: true, children: [
                    {id: "figma/view-menu/toggle-rulers", text: "Rulers", enabled: true,
                     checkable: true, checked: true, shortcut: "Shift+R"},
                    {id: "separator", separator: true},
                    {id: "nested", text: "Zoom", enabled: true, children: [
                        {id: "zoom-fit", text: "Zoom to fit", enabled: false,
                         checkable: false, checked: false, shortcut: "Shift+1"}
                    ]}
                ]}]
                menus.update(snapshot)
                compare(bar.menus.length, 3)
                compare(popup.count, 3)
                compare(menus.entries[0].native.items.length, 3)
                compare(menus.entries[0].popup.count, 3)
                const ruler = menus.entries[0].children[0]
                compare(ruler.native.checked, true)
                compare(ruler.popup.checked, true)
                compare(menus.entries[0].children[2].children[0].native.enabled, false)

                snapshot[0].children[0].checked = false
                menus.update(snapshot)
                compare(menus.entries[0].children[0].native, ruler.native)
                compare(ruler.native.checked, false)
                compare(ruler.popup.checked, false)
                menus.fileMenuAvailable = true
                menus.trigger(ruler.native.commandId)
                verify(view.lastScript.includes("Figma menu helper unavailable"), view.lastScript.slice(0,200))
                verify(view.lastScript.endsWith('("figma/view-menu/toggle-rulers")'))
                menus.page = null
                compare(bar.menus.length, 4)
                compare(popup.count, 4)
                verify(menus.usingHomeMenu)
            }

            function test_file_actions_merge_and_help_is_renamed() {
                const snapshot = [
                    {id: "figma/file-menu", text: "File", enabled: true, children: [
                        {id: "export", text: "Export", enabled: true,
                         checkable: false, checked: false, shortcut: ""},
                        {id: "export-menu", text: "Export as", enabled: true, children: [
                            {id: "pdf", text: "PDF", enabled: true,
                             checkable: false, checked: false, shortcut: ""}
                        ]}
                    ]},
                    {id: "figma/preferences-menu", text: "Preferences", enabled: true, children: [
                        {id: "snap", text: "Snap to pixel grid", enabled: true,
                         checkable: true, checked: true, shortcut: ""}
                    ]},
                    {id: "figma/figma-account-menu", text: "Help and account", enabled: true, children: []}
                ]
                menus.update(snapshot)
                compare(bar.menus.length, 3)
                compare(popup.count, 3)
                compare(fileMenu.items.length, 3)
                compare(fileMenu.items[0].text, "Export")
                compare(fileMenu.items[2].text, "Home")
                compare(filePopup.itemAt(0).text, "Export")
                compare(filePopup.itemAt(2).text, "Home")
                compare(preferencesMenu.items.length, 2)
                compare(preferencesMenu.items[0].text, "Snap to pixel grid")
                compare(preferencesMenu.items[1].text, "Settings")
                compare(preferencesPopup.itemAt(1).text, "Settings")
                compare(bar.menus[1], preferencesMenu)
                compare(menus.entries[2].native.title, "Help")
                compare(menus.entries[2].popup.title, "Help")
                menus.clear()
                compare(bar.menus.length, 2)
                compare(popup.count, 2)
                compare(fileMenu.items.length, 1)
                compare(filePopup.count, 1)
                compare(fileMenu.items[0].text, "Home")
                compare(preferencesMenu.items.length, 1)
                compare(preferencesPopup.count, 1)
                compare(preferencesMenu.items[0].text, "Settings")
            }

            function documentMenus(label = "Rulers") {
                return [
                    {id: "figma/view-menu", text: "View", enabled: true, children: [
                        {id: "rulers", text: label, enabled: true, shortcut: "Shift+R",
                         checkable: true, checked: false},
                        {id: "zoom", text: "Zoom", enabled: true, children: [
                            {id: "fit", text: "Fit", enabled: true, shortcut: ""}
                        ]}
                    ]},
                    {id: "figma/preferences-menu", text: "Preferences", enabled: true, children: []},
                    {id: "figma/figma-account-menu", text: "Help", enabled: true, children: []}
                ]
            }

            function test_cached_file_survives_failure_and_recovers() {
                view.loading = true
                view.url = "https://www.figma.com/design/first/First"
                verify(menus.usingHomeMenu)
                view.response = {menus: documentMenus()}
                view.loading = false
                verify(menus.fileMenuAvailable)
                const viewMenu = menus.entries[0].native
                const ruler = menus.entries[0].children[0].native
                const zoom = menus.entries[0].children[1].native
                view.response = {menus: []}
                menus.refresh()
                verify(!menus.usingHomeMenu)
                verify(!menus.fileMenuAvailable)
                compare(menus.entries[0].native, viewMenu)
                compare(ruler.enabled, false)
                compare(menus.entries[0].children[1].children[0].popup.enabled, false)
                const last = view.lastScript
                menus.trigger("rulers")
                compare(view.lastScript, last)
                view.response = {menus: documentMenus("Recovered")}
                menus.refresh()
                compare(menus.entries[0].native, viewMenu)
                compare(menus.entries[0].children[0].native, ruler)
                compare(menus.entries[0].children[1].native, zoom)
                compare(ruler.enabled, true)
                compare(ruler.text, "Recovered")
                view.lifecycleState = 1
                compare(ruler.enabled, false)
                view.lifecycleState = 0
                verify(menus.fileMenuAvailable)
            }

            function test_home_and_file_share_roots_and_file_caches_are_separate() {
                view.loading = true
                view.url = "https://www.figma.com/files/recent"
                const viewMenu = menus.entries[0].native
                const helpMenu = menus.entries[2].popup
                view.url = "https://www.figma.com/design/first/First"
                view.response = {menus: documentMenus("First")}
                view.loading = false
                compare(menus.entries[0].native, viewMenu)
                compare(menus.entries[2].popup, helpMenu)
                view.loading = true
                view.url = "https://www.figma.com/design/second/Second"
                verify(menus.usingHomeMenu)
                view.response = {menus: documentMenus("Second")}
                view.loading = false
                compare(menus.entries[0].children[0].native.text, "Second")
                view.loading = true
                view.url = "https://www.figma.com/design/first/First?node-id=1-1"
                verify(!menus.usingHomeMenu)
                compare(menus.entries[0].children[0].native.text, "First")
                compare(menus.entries[0].children[0].native.enabled, false)
                view.url = "https://www.figma.com/files/recent"
                verify(menus.usingHomeMenu)
                compare(menus.entries[0].native, viewMenu)
                compare(menus.entries[2].popup, helpMenu)
                compare(fileMenu.items.length, 1)
                menus.trigger("app/overview")
                compare(commands.count, 1)
                view.url = "about:blank"
                verify(menus.usingHomeMenu)
                menus.trigger("app/about")
                compare(commands.count, 2)
            }

            function test_unchanged_snapshot_skips_reconciliation() {
                const snapshot = documentMenus()
                menus.update(snapshot)
                const original = menus.entries
                menus.update(JSON.parse(JSON.stringify(snapshot)))
                verify(menus.entries === original)
                menus.update(snapshot, true)
                verify(menus.entries !== original)
                compare(menus.entries[0].children[0].native.enabled, false)
            }

            function test_reorder_and_insert_preserve_existing_commands() {
                const snapshot = documentMenus()
                menus.update(snapshot)
                const ruler = menus.entries[0].children[0]
                const zoom = menus.entries[0].children[1]
                snapshot[0].children.reverse()
                snapshot[0].children.splice(1, 0, {id: "new", text: "New", enabled: true, shortcut: ""})
                menus.update(snapshot)
                compare(menus.entries[0].children[0].native, zoom.native)
                compare(menus.entries[0].children[2].native, ruler.native)
                compare(menus.entries[0].native.items[0], zoom.native.menuItem)
                compare(menus.entries[0].popup.menuAt(0), zoom.popup)
                compare(menus.entries[0].popup.itemAt(2), ruler.popup)
                snapshot[0].children.splice(1, 1)
                menus.update(snapshot)
                compare(menus.entries[0].children[1].native, ruler.native)
                compare(menus.entries[0].popup.count, 2)
            }

            function test_request_timeout_disables_cache_and_ignores_late_response() {
                view.loading = true
                view.url = "https://www.figma.com/design/first/First"
                view.response = {menus: documentMenus()}
                view.loading = false
                verify(menus.fileMenuAvailable)
                view.defer = true
                menus.refresh()
                const late = view.callbacks[0]
                menus.requestTimeout.triggered()
                verify(!menus.fileMenuAvailable)
                verify(!menus.pending)
                compare(menus.entries[0].children[0].native.enabled, false)
                late(JSON.stringify({menus: documentMenus("Late")}))
                verify(!menus.fileMenuAvailable)
                compare(menus.entries[0].children[0].native.text, "Rulers")
                view.defer = false
                menus.refresh()
                verify(menus.fileMenuAvailable)
            }

            function test_old_async_response_cannot_replace_new_page_menu() {
                view.url = "https://www.figma.com/design/first/First"
                view.defer = true
                menus.refresh()
                compare(view.callbacks.length, 1)
                const old = view.callbacks[0]
                view.url = "https://www.figma.com/files/recent"
                menus.refresh()
                compare(view.callbacks.length, 1)
                old(JSON.stringify({menus: documentMenus()}))
                wait(0)
                compare(view.callbacks.length, 2)
                const current = view.callbacks[1]
                verify(menus.pending)
                verify(menus.usingHomeMenu)
                current('{"authenticated":true}')
                verify(!menus.pending)
                verify(menus.homeAuthenticated)
            }

            function test_integration_toggle_stops_requests_and_ignores_callbacks() {
                view.loading = true
                view.url = "https://www.figma.com/design/first/First"
                view.response = {menus: documentMenus()}
                view.loading = false
                verify(menus.fileMenuAvailable)
                view.defer = true
                menus.refresh()
                const late = view.callbacks[0]
                menus.integrationEnabled = false
                verify(menus.usingHomeMenu)
                verify(!menus.poll.running)
                menus.refresh()
                compare(view.callbacks.length, 1)
                late(JSON.stringify({menus: documentMenus("Late")}))
                wait(0)
                compare(view.callbacks.length, 1)
                verify(menus.usingHomeMenu)
                menus.integrationEnabled = true
                wait(0)
                compare(view.callbacks.length, 2)
                view.callbacks[1](JSON.stringify({menus: documentMenus()}))
                verify(menus.fileMenuAvailable)
            }

            function test_slow_request_does_not_accumulate_work() {
                view.url = "https://www.figma.com/design/slow/Slow"
                view.defer = true
                menus.refresh()
                menus.requestTimeout.triggered()
                for (let i = 0; i < 10; ++i) menus.refresh()
                compare(view.callbacks.length, 1)
                verify(!menus.fileMenuAvailable)
            }

            function test_rapid_large_menu_transitions() {
                const snapshot = []
                for (let group = 0; group < 9; ++group) {
                    const children = []
                    for (let index = 0; index < 12; ++index)
                        children.push({id: "menu" + group + "/" + index, text: "Action", enabled: true,
                                       shortcut: "", checkable: false, checked: false})
                    children.push({id: "submenu" + group, text: "Submenu", enabled: true,
                                   children: children.slice(0, 8)})
                    snapshot.push({id: "menu" + group, text: "Menu", enabled: true, children})
                }
                for (let iteration = 0; iteration < 30; ++iteration) {
                    menus.update(snapshot)
                    menus.update(snapshot)
                    menus.update(snapshot.slice().reverse())
                    menus.reset()
                    wait(1)
                }
                compare(bar.menus.length, 4)
                compare(popup.count, 4)
            }

            function test_home_layout_and_available_commands() {
                view.loading = true
                view.url = "https://www.figma.com/files/recent"
                tryVerify(() => bar.menus.length === 4)
                compare(bar.menus[0].title, "File")
                compare(bar.menus[1].title, "View")
                compare(bar.menus[2].title, "Preferences")
                compare(bar.menus[3].title, "Help")
                compare(popup.menuAt(1).title, "View")
                compare(menus.entries[0].native.items[0].text, "Reload page")
                const account = menus.entries[2].children.find(entry => entry.native.commandId === "home/account-settings")
                compare(account.native.enabled, false)
                view.loading = false
                menus.refresh()
                compare(account.native.enabled, true)
                menus.trigger("app/overview")
                compare(commands.count, 1)
                compare(commands.signalArguments[0][0], "overview")
                menus.clear()
            }
        }
    }
}
