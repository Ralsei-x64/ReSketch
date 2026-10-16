// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtTest
import ReSketch.Cef
import "../src" as App
import "../src/FigmaTheme.js" as FigmaTheme

Item {
    id: fixture
    property int notificationCount: 0
    readonly property bool gpuMasking: GraphicsInfo.api !== GraphicsInfo.Software
    width: 1280
    height: 800
    property QtObject appSettings: QtObject {
        readonly property string buildCommit: "abc1234"
        property bool safeMode: false
        property bool desktopNotifications: false
        property string theme: "auto"
        property bool menuIntegration: false
        property bool darkTheme: false
        property bool figmaSystemColors: false
        property bool figmaCustomCssEnabled: false
        property string figmaCustomCss: ""
        property var figmaPalette: ({})
        property bool translucentSidebars: false
        property bool floatingSidebars: false
        property int sidebarCornerRadius: 12
        property int sidebarMargin: 8
        property bool hideFloatingScrollbars: true
        property string sidebarBackdrop: "desktop"
        property int sidebarCanvasBlur: 0
        property int sidebarCanvasOpacity: 100
        property bool reduceMotion: false
        property int toolbarOpacity: 100
        function defaultToolbarItems() {
            return [{id: "new-tab", title: "New tab", icon: "tab-new", enabled: true},
                    {id: "overview", title: "Tab overview", icon: "view-grid", enabled: true},
                    {id: "refresh", title: "Refresh page", icon: "view-refresh", enabled: true},
                    {id: "menu", title: "Application menu", icon: "application-menu", enabled: true},
                    {id: "export-history", title: "Export History", icon: "document-export", enabled: false},
                    {id: "settings", title: "Settings", icon: "configure", enabled: false},
                    {id: "task-manager", title: "Task Manager", icon: "view-process-system", enabled: false},
                    {id: "developer-tools", title: "Developer Tools", icon: "applications-development", enabled: false}]
        }
        property var toolbarItems: defaultToolbarItems()
        property var shortcutOverrides: ({})
        function shortcutSequenceText(value) { return String(value) }
        function keyEventSequence(key, modifiers) {
            const keys = {}
            keys[Qt.Key_Left] = "Left"; keys[Qt.Key_Right] = "Right"
            keys[Qt.Key_Up] = "Up"; keys[Qt.Key_Down] = "Down"
            keys[Qt.Key_Return] = "Return"; keys[Qt.Key_Enter] = "Enter"
            keys[Qt.Key_Delete] = "Delete"
            return ((modifiers & Qt.ControlModifier) ? "Ctrl+" : "")
                + ((modifiers & Qt.AltModifier) ? "Alt+" : "")
                + ((modifiers & Qt.ShiftModifier) ? "Shift+" : "")
                + ((modifiers & Qt.MetaModifier) ? "Meta+" : "")
                + (keys[key] || String.fromCharCode(key))
        }
        property bool windowControlsInTabBar: false
        property bool keepWindowDecorations: true
        property bool ignoreToolbarBlur: false
        property int minimumLoadedTabs: 5
        property int maximumLoadedTabs: 5
        property int memoryLimitMiB: 0
        property real totalAppMemoryMiB: 0
        function refreshMemoryUsage() {}
        property int sleepMinutes: 5
        property bool sleepingTabPreviews: false
        property bool keepHomeAwake: true
        property bool rememberOpenedTabs: false
        property bool deferRestoredTabs: true
        property var rememberedFileTabs: []
        property var rememberedTabGroups: []
        property bool releaseClosedWindows: true
        property bool cullOffscreenOverviewEffects: true
        property bool compactPreviewTextures: true
        property int overviewPreviewQuality: 100
        property bool gpuRasterization: true
        property bool zeroCopyRasterization: true
        property bool experimentalCanvasFeatures: false
        property bool useSystemCursor: false
        property bool useVulkan: false
        property string chromiumFlags: ""
        property string profileStoragePath: ""
        property string exportFolderResult: "/tmp/resketch-exports"
        property string requestedExportKey: ""
        property var requestedExportOwner: null
        property var exportHistory: []
        property string recordedExport: ""
        property string recordedOrigin: ""
        property string copiedText: ""
        property bool exportDeletionSucceeds: true
        property bool nativeTabDragSupported: false
        property string gpuAccelerationWarning: ""
        function cursorPosition() { return Qt.point(0, 0) }
        signal changed()
        signal effectiveThemeChanged()
        signal figmaAppearanceChanged()
        function refreshWindowBlur(window) {}
        function repaintWebView(view) {}
        function registerMainWindow(window) {}
        function showDesktopNotification(notification, owner) {}
        function showHomeNotification(title, body, url, owner) {}
        function chooseGroupColor(initial, owner) { return "#e75d73" }
        function copyToClipboard(text) { copiedText = text }
        function chooseExportFolder(key, filename, owner) {
            requestedExportKey = key
            requestedExportOwner = owner
            return exportFolderResult
        }
        function recordExport(directory, filename, originName, originUrl) {
            recordedExport = directory + "/" + filename
            recordedOrigin = originName
        }
        function clearExports() { exportHistory = [] }
        function resetSettings() { figmaCustomCss = ""; toolbarItems = defaultToolbarItems(); shortcutOverrides = {} }
        function openExport(path, folder) { return true }
        function deleteExport(path) {
            if (!exportDeletionSucceeds) return false
            exportHistory = exportHistory.filter(item => item.path !== path)
            return true
        }
    }

    CefProfile { id: testProfile; offTheRecord: true }
    Component {
        id: notificationProbe
        CefView {
            profile: testProfile
            onPermissionRequested: permission => permission.grant()
        }
    }
    Connections {
        target: testProfile
        function onPresentNotification(notification) {
            ++fixture.notificationCount
            notification.close()
        }
    }
    App.Main {
        id: app
        sharedProfile: testProfile
        property int systemMoveRequests: 0
        property int groupIconRequests: 0
        // Observe activation without opening a QWidget in the QGui test runner.
        function chooseTabGroupIcon(id) { ++groupIconRequests }
        property var externalLinks: []
        function openExternalLink(address) {
            externalLinks = externalLinks.concat(String(address))
        }
        function startSystemMove() {
            ++systemMoveRequests
            return true
        }
    }

    TestCase {
        name: "TabCloseSelection"
        when: windowShown && app.visible

        function tabButton(index, window) {
            function find(item) {
                if (item.index === index && item.closePending !== undefined)
                    return item
                for (const child of item.children || []) {
                    const result = find(child)
                    if (result) return result
                }
                return null
            }
            return find((window || app).contentItem)
        }

        function visualChild(item, name) {
            if (item.objectName === name) return item
            for (const child of item.children || []) {
                const result = visualChild(child, name)
                if (result) return result
            }
            return null
        }

        function init() {
            app.externalLinks = []
            app.dismissOverview()
            appSettings.reduceMotion = true
            appSettings.changed()
            for (const view of app.views.slice())
                app.closeTab(app.views.indexOf(view))
            tryCompare(app, "activeIndex", -1)
            tryVerify(() => app.views.length === 0)
            appSettings.reduceMotion = false
            appSettings.changed()
            app.homeView.stop()
            for (let i = 0; i < 4; ++i) {
                app.openTab("about:blank", null, true)
                app.views[app.views.length - 1].stop()
            }
            wait(300)
            app.activateTab(2)
            wait(350)
        }

        function test_cursor_preference_applies_to_existing_views() {
            const views = [app.homeView].concat(app.views)
            for (const view of views) compare(view.useSystemCursor, false)
            appSettings.useSystemCursor = true
            for (const view of views) compare(view.useSystemCursor, true)
            appSettings.useSystemCursor = false
            for (const view of views) compare(view.useSystemCursor, false)
        }

        function test_overview_keeps_canvas_density_and_layout_data() {
            return [{tag:"compact-full-quality", compact:true, quality:100},
                    {tag:"compact-low-quality", compact:true, quality:25},
                    {tag:"full-textures-low-quality", compact:false, quality:25}]
        }

        function test_overview_keeps_canvas_density_and_layout(data) {
            appSettings.maximumLoadedTabs = 100
            appSettings.compactPreviewTextures = data.compact
            appSettings.overviewPreviewQuality = data.quality
            const target = app.views[0]
            let ready = false, result = null
            target.runJavaScript("document.body.innerHTML='<canvas id=previewCanvas></canvas><div id=anchor></div>';"
                + "document.body.style.margin='0';document.getElementById('anchor').style.cssText='position:absolute;left:37%;top:42%;width:20px;height:20px';"
                + "window.canvasStates=[];window.recordCanvas=()=>{const c=document.getElementById('previewCanvas');"
                + "c.width=Math.round(innerWidth*devicePixelRatio);c.height=Math.round(innerHeight*devicePixelRatio);"
                + "const r=document.getElementById('anchor').getBoundingClientRect();"
                + "const state=[devicePixelRatio,innerWidth,innerHeight,c.width,c.height,r.x,r.y];"
                + "if(JSON.stringify(state)!==JSON.stringify(canvasStates.at(-1)))canvasStates.push(state);"
                + "requestAnimationFrame(recordCanvas)};recordCanvas();", () => ready = true)
            tryVerify(() => ready)
            target.hasLoadedFrame = true
            function inspect() {
                result = null
                target.runJavaScript('canvasStates', value => result = value)
                tryVerify(() => result !== null)
                return result
            }
            const original = inspect()[0]
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            wait(100)
            const previewStates = inspect()
            compare(previewStates.length, 1, "Entering overview must not change Figma's canvas density or layout")
            compare(previewStates[0], original)
            app.selectOverviewView(target)
            verify(app.overviewClosing, "Exercise the animated transition to another tab")
            tryCompare(app, "overviewVisible", false)
            wait(150)
            const openedStates = inspect()
            compare(openedStates.length, 1, "Zooming into a card must not rerasterize or shift its web content")
            compare(openedStates[0], original)
            compare(app.activeView, target)
        }

        function test_all_visible_overview_previews_keep_animating() {
            appSettings.reduceMotion = true
            appSettings.maximumLoadedTabs = 100
            appSettings.sleepMinutes = 240
            app.width = 1360
            app.height = 900
            for (let i = app.views.length; i < 10; ++i) app.openTab("about:blank", null, true)
            const views = app.views.slice()
            for (let i = 0; i < views.length; ++i) {
                const view = views[i]
                app.activateTab(i, false)
                tryVerify(() => view.renderProcessPid > 0)
                view.runJavaScript("document.title='Live preview " + i + "';document.body.innerHTML='';"
                    + "window.previewTicks=0;window.tick=()=>{++previewTicks;"
                    + "document.body.style.backgroundColor=previewTicks%2?'#224488':'#448822';"
                    + "requestAnimationFrame(tick)};requestAnimationFrame(tick);true")
                tryCompare(view, "title", "Live preview " + i)
                tryCompare(view, "loading", false)
                view.hasLoadedFrame = true
            }
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            function sample() {
                const values = []
                for (let i = 0; i < views.length; ++i)
                    views[i].runJavaScript('previewTicks', value => values[i] = Number(value))
                tryVerify(() => values.filter(value => Number.isFinite(value)).length === views.length)
                return values
            }
            const before = sample()
            wait(1000)
            const after = sample()
            for (let i = 0; i < views.length; ++i) {
                verify(views[i].overviewPreview, "Preview " + i + " uses the overview frame budget")
                verify(after[i] - before[i] <= 45, "Preview " + i + " is capped at 30 fps")
                verify(views[i].visible, "Preview " + i + " remains visible")
                compare(views[i].lifecycleState, CefView.LifecycleState.Active)
                verify(after[i] > before[i], "Preview " + i + " continues animating")
            }
            app.selectOverviewView(views[7])
            tryCompare(app, "overviewVisible", false)
            compare(views[7].overviewPreview, false)
            appSettings.compactPreviewTextures = false
            for (let cycle = 0; cycle < 2; ++cycle) {
                app.toggleOverview()
                tryCompare(app, "overviewProgress", 1)
                const start = sample()
                wait(300)
                const end = sample()
                for (let i = 0; i < views.length; ++i) {
                    verify(end[i] > start[i], "Preview " + i + " recovers after hiding/showing")
                }
                app.selectOverviewView(views[cycle])
                tryCompare(app, "overviewVisible", false)
            }
            appSettings.compactPreviewTextures = true
            appSettings.maximumLoadedTabs = 5
            appSettings.sleepMinutes = 5
        }

        function verifySelection(view) {
            compare(app.activeView, view)
            compare(app.activeIndex, app.views.indexOf(view))
            for (let index = 0; index < app.views.length; ++index) {
                const button = tabButton(index)
                compare(button.tabView, app.views[index])
                compare(button.selected, app.views[index] === view)
            }
        }

        function test_tab_groups_collapse_rename_color_and_membership() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[2]
            const groupId = app.createTabGroup(first)
            compare(app.groupFor(first).title, "Tab Group 1")
            app.assignTabGroup(second, groupId)
            compare(app.views[1], second)
            compare(second.tabGroupId, groupId)
            compare(app.tabStripWidth, 4 * app.tabWidth + app.groupHeaderWidth)
            app.activateTab(1)
            const header = app.tabGroupHeaderItem(app.tabGroups[0].id)
            verify(header && header.visible)
            mouseClick(header, header.width / 2, header.height / 2)
            compare(app.groupFor(first).collapsed, true)
            compare(tabButton(0).width, app.groupHeaderWidth)
            compare(tabButton(1).width, 0)
            compare(app.activeView, second)
            compare(findChild(app, "selectionBar").targetWidth, app.groupHeaderWidth)
            const reopenedHeader = app.tabGroupHeaderItem(groupId)
            mouseClick(reopenedHeader, reopenedHeader.width / 2, reopenedHeader.height / 2)
            compare(app.groupFor(first).collapsed, false)
            app.updateTabGroup(groupId, {title: "Design work", color: "#e75d73"})
            compare(app.groupFor(second).title, "Design work")
            compare(app.groupFor(second).color, "#e75d73")
            app.updateTabGroup(groupId, {collapsed: true})
            app.activateTab(0)
            compare(app.groupFor(first).collapsed, false)
            app.openTab("about:blank", null, true, first)
            compare(app.views[1].tabGroupId, groupId)
            app.assignTabGroup(second, "")
            compare(second.tabGroupId, "")
            compare(app.views.indexOf(second), 2)
            app.ungroupTabs(groupId)
            compare(app.tabGroups.length, 0)
            compare(app.tabStripWidth, 5 * app.tabWidth)
            compare(app.activeView, first)
        }

        function test_tab_group_name_is_confirmed_before_creation() {
            const view = app.views[0]
            app.requestTabGroup(view)
            const dialog = findChild(app, "tabGroupNameDialog")
            const editor = findChild(app, "tabGroupNameEditor")
            const picker = findChild(app, "tabGroupColorPicker")
            verify(picker.mapToItem(dialog.contentItem, 0, 0).y
                   > editor.mapToItem(dialog.contentItem, 0, editor.height).y,
                   "Color picker is below the name field")
            compare(editor.text, "Tab Group 1")
            compare(app.tabGroups.length, 0)
            dialog.reject()
            compare(app.tabGroups.length, 0)
            compare(view.tabGroupId, "")
            app.requestTabGroup(view)
            editor.text = "Design work"
            picker.clicked()
            dialog.accept()
            compare(app.groupFor(view).title, "Design work")
            compare(String(app.groupFor(view).color), "#e75d73")
            compare(app.tabGroups.length, 1)
            const group = app.groupFor(view)
            dialog.groupId = group.id
            dialog.groupColor = group.color
            editor.text = "Renamed work"
            dialog.open()
            dialog.groupColor = "#4477aa"
            dialog.accept()
            compare(app.groupFor(view).title, "Renamed work")
            compare(String(app.groupFor(view).color), "#4477aa")
        }

        function test_tab_group_dialog_keyboard_navigation() {
            app.requestActivate()
            tryVerify(() => app.active)
            const view = app.views[0]
            app.requestTabGroup(view)
            const dialog = findChild(app, "tabGroupNameDialog")
            const name = findChild(app, "tabGroupNameEditor")
            const icon = findChild(app, "tabGroupIconPicker")
            const color = findChild(app, "tabGroupColorPicker")
            const save = findChild(app, "tabGroupAcceptButton")
            const cancel = findChild(app, "tabGroupCancelButton")
            tryCompare(dialog, "opened", true)
            tryCompare(name, "activeFocus", true)
            compare(name.selectedText, "Tab Group 1")
            name.text = "Keyboard group"
            compare(findChild(app, "tabGroupPreviewName").text, name.text)
            keyClick(Qt.Key_Tab)
            tryCompare(icon, "activeFocus", true)
            keyClick(Qt.Key_Right)
            tryCompare(color, "activeFocus", true)
            keyClick(Qt.Key_Tab)
            tryCompare(save, "activeFocus", true)
            keyClick(Qt.Key_Tab)
            tryCompare(cancel, "activeFocus", true)
            keyClick(Qt.Key_Tab)
            tryCompare(name, "activeFocus", true)
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
            tryCompare(cancel, "activeFocus", true)
            keyClick(Qt.Key_N, Qt.AltModifier)
            tryCompare(name, "activeFocus", true)
            name.text = "  "
            compare(save.enabled, false)
            keyClick(Qt.Key_Return)
            compare(dialog.visible, true, "Blank names cannot be submitted")
            keyClick(Qt.Key_Return, Qt.ControlModifier)
            compare(dialog.visible, true)
            keyClick(Qt.Key_Tab)
            keyClick(Qt.Key_Tab)
            keyClick(Qt.Key_Tab)
            tryCompare(cancel, "activeFocus", true, 5000)
            keyClick(Qt.Key_N, Qt.AltModifier)
            name.text = "  Keyboard group  "
            keyClick(Qt.Key_C, Qt.AltModifier)
            compare(String(dialog.groupColor), "#e75d73")
            tryCompare(color, "activeFocus", true)
            keyClick(Qt.Key_Return, Qt.ControlModifier)
            tryCompare(dialog, "visible", false)
            compare(app.groupFor(view).title, "Keyboard group")
            app.editTabGroup(view.tabGroupId)
            tryCompare(dialog, "opened", true)
            compare(save.text, "Save changes")
            name.text = "Discard this edit"
            keyClick(Qt.Key_Escape)
            tryCompare(dialog, "visible", false)
            compare(app.groupFor(view).title, "Keyboard group")
        }

        function test_tab_group_dialog_enter_data() {
            const rows = []
            for (const control of ["name", "icon", "color", "accept", "cancel"])
                for (const key of [Qt.Key_Return, Qt.Key_Enter])
                    rows.push({tag: control + "-" + (key === Qt.Key_Return ? "return" : "enter"), control, key})
            return rows
        }

        function test_tab_group_dialog_enter(data) {
            app.requestActivate()
            tryVerify(() => app.active)
            const view = app.views[0]
            app.requestTabGroup(view)
            const dialog = findChild(app, "tabGroupNameDialog")
            const name = findChild(app, "tabGroupNameEditor")
            name.text = "Enter test"
            const controls = {name, icon: findChild(app, "tabGroupIconPicker"),
                color: findChild(app, "tabGroupColorPicker"), accept: findChild(app, "tabGroupAcceptButton"),
                cancel: findChild(app, "tabGroupCancelButton")}
            tryCompare(dialog, "opened", true)
            controls[data.control].forceActiveFocus()
            tryCompare(controls[data.control], "activeFocus", true)
            const iconRequests = app.groupIconRequests
            keyClick(data.key)
            if (data.control === "icon") {
                compare(app.groupIconRequests, iconRequests + 1)
                compare(dialog.visible, true, "Enter on a picker must not submit the group")
            } else if (data.control === "color") {
                compare(String(dialog.groupColor), "#e75d73")
                compare(dialog.visible, true, "Enter on a picker must not submit the group")
            } else {
                tryCompare(dialog, "visible", false)
                compare(app.tabGroups.length, data.control === "cancel" ? 0 : 1)
                if (data.control !== "cancel") compare(app.groupFor(view).title, "Enter test")
            }
        }

        function test_empty_groups_are_discarded_and_closing_members_are_not_saved() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            first.deferredRestoreUrl = "https://www.figma.com/design/Group_A/First"
            second.deferredRestoreUrl = "https://www.figma.com/design/Group_B/Second"
            const id = app.createTabGroup(first, "Saved group", "#4477aa")
            app.assignTabGroup(second, id)
            compare(app.sessionTabGroups[0].tabs, [0, 1])
            app.pendingCloseViews = [first, second]
            compare(app.sessionTabGroups, [], "A group with only closing tabs must not be restored")
            app.pendingCloseViews = []
            app.closeTab(app.views.indexOf(first))
            tryCompare(app, "sessionFileUrls", [String(second.tabUrl)])
            compare(app.tabGroups.length, 1)
            compare(app.sessionTabGroups[0].tabs, [0])
            app.closeTab(app.views.indexOf(second))
            tryCompare(app, "tabGroups", [])
            compare(app.sessionTabGroups, [])
        }

        function test_overview_card_right_click_opens_its_options_data() {
            return [{tag: "preview", header: false}, {tag: "title", header: true}, {tag: "home", home: true}]
        }

        function test_overview_card_right_click_opens_its_options(data) {
            appSettings.reduceMotion = true
            const selected = app.activeView
            const view = data.home ? app.homeView : app.views[0]
            if (!data.home) view.deferredRestoreUrl = "https://www.figma.com/design/Context_A/File"
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            const card = overviewCard(view)
            verify(card)
            waitForRendering(app.contentItem)
            const menu = findChild(card, "overviewTabMenu")
            verify(menu)
            mouseClick(card, card.width / 2, data.header ? 15 : card.height / 2, Qt.RightButton)
            tryCompare(menu, "visible", true)
            compare(app.activeView, selected)
            compare(app.overviewVisible, true)
            const copy = Array.from({length: menu.count}, (_, index) => menu.itemAt(index)).find(item => item.text === "Copy URL")
            verify(copy)
            menu.close()
            if (!data.home) {
                verify(copy.enabled)
                copy.triggered()
                compare(appSettings.copiedText, String(view.tabUrl))
                const button = findChild(card, "overviewTabOptions")
                mouseClick(button, button.width / 2, button.height / 2)
                tryCompare(menu, "visible", true)
                menu.close()
            } else {
                const close = Array.from({length: menu.count}, (_, index) => menu.itemAt(index)).find(item => item.text === "Close")
                verify(close && !close.enabled, "Home stays open")
            }
        }

        function test_group_context_menu_actions_data() {
            return [{tag: "tab_strip", overview: false}, {tag: "overview", overview: true}]
        }

        function test_group_context_menu_actions(data) {
            appSettings.reduceMotion = true
            const selected = app.activeView, first = app.views[0], second = app.views[1]
            let id = app.createTabGroup(first, "Design work", "#4477aa")
            app.assignTabGroup(second, id)
            if (data.overview) {
                app.toggleOverview()
                tryCompare(app, "overviewProgress", 1)
                app.updateTabGroup(id, {overviewCollapsed: true}, true)
            } else app.updateTabGroup(id, {collapsed: true}, true)
            const menu = findChild(app, "tabGroupContextMenu")
            function openMenu() {
                const header = data.overview ? findChild(app.overviewGroupContainer(id), "overviewGroupHeader")
                                             : app.tabGroupHeaderItem(id)
                if (!data.overview) findChild(app, "tabsViewport").contentX = 0
                waitForRendering(app.contentItem)
                mouseClick(header, 80, header.height / 2, Qt.RightButton)
                tryCompare(menu, "visible", true)
                compare(menu.groupId, id)
                compare(app.groupFor(first)[data.overview ? "overviewCollapsed" : "collapsed"], true,
                        "Right click must not expand or collapse the group")
                compare(app.activeView, selected)
            }
            function trigger(name) {
                const action = findChild(menu, name)
                verify(action && action.enabled)
                menu.close()
                action.triggered()
            }
            openMenu()
            trigger("renameTabGroup")
            const dialog = findChild(app, "tabGroupNameDialog")
            tryCompare(dialog, "visible", true)
            compare(findChild(app, "tabGroupNameEditor").text, "Design work")
            findChild(app, "tabGroupNameEditor").text = "Renamed work"
            dialog.accept()
            compare(app.groupFor(first).title, "Renamed work")
            openMenu()
            trigger("changeTabGroupColor")
            compare(String(app.groupFor(first).color), "#e75d73")
            openMenu()
            trigger("deleteTabGroup")
            compare(app.tabGroups.length, 0)
            compare(first.tabGroupId, "")
            compare(second.tabGroupId, "")
            compare(app.views.length, 4, "Deleting a group keeps its tabs")
            compare(app.activeView, selected)
            id = app.createTabGroup(first, "Close group", "#4477aa")
            app.assignTabGroup(second, id)
            app.updateTabGroup(id, data.overview ? {overviewCollapsed: true} : {collapsed: true}, true)
            openMenu()
            trigger("closeTabGroup")
            tryVerify(() => !app.views.includes(first) && !app.views.includes(second))
            compare(app.views.length, 2)
            compare(app.tabGroups.length, 0)
            compare(app.activeView, selected)
            compare(app.overviewVisible, data.overview)
        }

        function test_deleting_collapsing_overview_group_keeps_cards_visible() {
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Collapsing group")
            app.assignTabGroup(second, id)
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            app.updateTabGroup(id, {overviewCollapsed: true})
            wait(60)
            verify(app.overviewGroupContainer(id).expansion < 1)
            app.ungroupTabs(id)
            wait(300)
            compare(first.overviewEntrance, 1)
            compare(second.overviewEntrance, 1)
            compare(app.views.length, 4)
            verify(overviewCard(first).visible)
            verify(overviewCard(second).visible)
        }

        function test_group_collapse_animates_members_and_separate_label() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first)
            app.assignTabGroup(second, id)
            appSettings.reduceMotion = false
            const header = app.tabGroupHeaderItem(app.tabGroups[0].id)
            verify(header.parent !== tabButton(0), "The group label is independent of its first tab")
            const arrow = findChild(header, "tabGroupArrow")
            compare(String(arrow.source), "arrow-left")
            const border = findChild(header, "tabGroupHeaderBorder")
            compare(border.color, app.groupFor(first).color)
            mouseClick(header, header.width / 2, header.height / 2)
            compare(app.groupFor(first).collapsed, true)
            tryVerify(() => first.groupExpansion < 1 && first.groupExpansion > 0)
            verify(tabButton(0).width > app.groupHeaderWidth)
            verify(tabButton(1).width > 0)
            tryCompare(first, "groupExpansion", 0)
            compare(tabButton(0).width, app.groupHeaderWidth)
            compare(tabButton(1).width, 0)
            compare(String(findChild(app.tabGroupHeaderItem(app.tabGroups[0].id), "tabGroupArrow").source), "arrow-right")
            const closedHeader = app.tabGroupHeaderItem(app.tabGroups[0].id)
            mouseClick(closedHeader, closedHeader.width / 2, closedHeader.height / 2)
            tryVerify(() => first.groupExpansion > 0 && first.groupExpansion < 1)
            tryCompare(first, "groupExpansion", 1)
            compare(tabButton(1).width, app.tabWidth)
        }

        function test_dragging_tabs_into_within_and_out_of_groups() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], outside = app.views[3]
            const id = app.createTabGroup(first)
            app.assignTabGroup(second, id)
            appSettings.reduceMotion = false
            function drag(view, target) {
                const button = tabButton(app.views.indexOf(view))
                const start = button.mapToItem(app.contentItem, button.groupPrefix + 80, 20)
                mousePress(app.contentItem, start.x, start.y)
                mouseMove(app.contentItem, start.x + 30, start.y, 20)
                mouseMove(app.contentItem, target.x, target.y, 20)
                tryVerify(() => app.draggedTabIndex >= 0)
                mouseRelease(app.contentItem, target.x, target.y)
                tryCompare(app, "draggedTabIndex", -1)
                wait(260)
            }
            const header = app.tabGroupHeaderItem(app.tabGroups[0].id)
            const headerPoint = header.mapToItem(app.contentItem, 80, 20)
            drag(outside, headerPoint)
            compare(outside.tabGroupId, id, "Dropping on the label joins the group")
            compare(app.views.indexOf(outside), 2)
            const beforeX = app.tabGroupHeaderItem(app.tabGroups[0].id).x
            drag(first, tabButton(2).mapToItem(app.contentItem, 180, 20))
            compare(app.views.indexOf(first), 2, "Members can reorder inside their group")
            compare(first.tabGroupId, id)
            compare(app.tabGroupHeaderItem(app.tabGroups[0].id).x, beforeX, "Dragging the first member does not move the label")
            drag(outside, Qt.point(headerPoint.x - 100, headerPoint.y))
            compare(outside.tabGroupId, "", "Dropping before the label leaves the group")
            compare(app.views.indexOf(outside), 0)
            compare(app.views[1].tabGroupId, id)
            compare(app.views[2].tabGroupId, id)
            appSettings.reduceMotion = true
            app.updateTabGroup(id, {collapsed: true})
            drag(outside, app.tabGroupHeaderItem(app.tabGroups[0].id).mapToItem(app.contentItem, 80, 20))
            compare(outside.tabGroupId, id, "Collapsed labels accept tabs too")
            compare(app.groupFor(outside).collapsed, true)
        }

        function test_overview_shows_group_color_and_name() {
            appSettings.reduceMotion = true
            const first = app.views[0]
            const id = app.createTabGroup(first, "A deliberately long group name")
            app.updateTabGroup(id, {color: "#e75d73"})
            app.toggleOverview()
            const card = overviewCard(first)
            const border = findChild(card, "overviewCardBorder")
            const label = findChild(card, "overviewTabGroupName")
            compare(border.border.color, app.groupFor(first).color)
            compare(label.text, app.groupFor(first).title)
            verify(label.visible)
            tryVerify(() => label.width <= card.width * 0.4 + 1)
            compare(findChild(overviewCard(app.homeView), "overviewTabGroupName").visible, false)
        }

        function test_group_selection_bar_matches_the_actual_tab() {
            appSettings.reduceMotion = true
            const id = app.createTabGroup(app.views[0], "Design")
            app.assignTabGroup(app.views[1], id)
            appSettings.reduceMotion = false
            const bar = findChild(app, "selectionBar")
            for (let index = 0; index < app.views.length; ++index) {
                app.activateTab(index)
                wait(360)
                const button = tabButton(index)
                fuzzyCompare(bar.x, button.mapToItem(bar.parent, button.groupPrefix, 0).x, 1)
                fuzzyCompare(bar.width, app.tabWidth, 1)
            }
            app.activateTab(1)
            wait(360)
            app.updateTabGroup(id, {collapsed: true})
            wait(300)
            fuzzyCompare(bar.x, app.tabGroupHeaderItem(id).mapToItem(bar.parent, 0, 0).x, 1)
            fuzzyCompare(bar.width, app.groupHeaderWidth, 1)
        }

        function test_drag_group_label_moves_all_members_and_selection() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.activateTab(1)
            appSettings.reduceMotion = false
            waitForRendering(app.contentItem)
            wait(30)
            const header = app.tabGroupHeaderItem(id)
            const start = header.mapToItem(app.contentItem, 80, 20)
            const destination = tabButton(3).mapToItem(app.contentItem, 200, 20)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            mouseMove(app.contentItem, destination.x, destination.y, 20)
            tryCompare(app, "draggedGroupId", id)
            compare(app.groupDropIndex, 2, "Drop past the last tab moves the group to the end")
            const bar = findChild(app, "selectionBar")
            fuzzyCompare(bar.x, tabButton(1).mapToItem(bar.parent, 0, 0).x, 1)
            fuzzyCompare(bar.x - header.mapToItem(bar.parent, 0, 0).x,
                         app.groupHeaderWidth + app.tabWidth, 1, "Members follow their label without lag")
            mouseRelease(app.contentItem, destination.x, destination.y)
            tryCompare(app, "draggedGroupId", "")
            const releasedMember = tabButton(app.views.indexOf(first))
            fuzzyCompare(releasedMember.mapToItem(bar.parent, releasedMember.groupPrefix, 0).x
                         - header.mapToItem(bar.parent, 0, 0).x, app.groupHeaderWidth, 1,
                         "The whole group settles into its new slot together")
            wait(300)
            verify(app.views[2] === first, "First member moves with the label")
            verify(app.views[3] === second, "Second member moves with the label")
            verifySelection(second)
            compare(app.groupFor(first).collapsed, false, "Dragging must not collapse the group")
            fuzzyCompare(bar.x, tabButton(3).mapToItem(bar.parent, 0, 0).x, 1)
            appSettings.reduceMotion = true
            app.updateTabGroup(id, {collapsed: true})
            app.moveTabGroup(id, 0, app.captureTabStripPositions())
            compare(app.views[0], first)
            compare(app.views[1], second)
            verifySelection(second)
        }

        function test_overview_group_containers_collapse_and_accept_drops() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], outside = app.views[3]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.updateTabGroup(id, {color: "#e75d73"})
            app.toggleOverview()
            const container = app.overviewGroupContainer(id)
            verify(container && container.visible)
            compare(findChild(container, "overviewGroupTitle").text, "Design")
            verify(findChild(container, "overviewGroupCount").text.includes("2"))
            compare(container.border.color, app.groupFor(first).color)
            const card = overviewCard(first)
            compare(card.parent, container.cardArea)
            compare(container.cardArea.clip, true)
            verify(card.y >= 0)
            verify(card.y + card.height <= container.cardArea.height)
            compare(first.frameContainer.parent, card)
            mouseClick(container, 80, 25)
            compare(app.groupFor(first).overviewCollapsed, true)
            fuzzyCompare(container.height, app.overviewCardHeight, 1)
            fuzzyCompare(container.width, app.overviewCardWidth, 1)
            compare(card.visible, false)
            compare(findChild(container, "overviewGroupArrow").opacity, 0)
            compare(findChild(container, "overviewGroupPreviewGrid").opacity, 1)
            findChild(app, "overviewFlickable").resetScroll(0)
            waitForRendering(app.contentItem)
            mouseClick(container, container.width - 30, 25)
            compare(app.groupFor(first).overviewCollapsed, false)
            compare(card.visible, true)
            fuzzyCompare(container.width, app.overviewCardWidth, 1)
            verify(container.expandedArea.y >= container.y + container.height + app.overviewGap - 1)

            // The collapsed header accepts drops; the empty space beside it does not.
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.overviewDraggedView = outside
            app.overviewDropIndex = app.views.indexOf(outside)
            app.overviewDropTarget(Qt.point(container.x + container.width + 4, container.y + 25))
            compare(app.overviewDropGroupId, "")
            const target = app.overviewDropTarget(Qt.point(container.x + 80, container.y + 25))
            compare(app.overviewDropGroupId, id)
            app.overviewDraggedView = null
            app.reorderTab(app.views.indexOf(outside), target, null, false, app.overviewDropGroupId)
            compare(outside.tabGroupId, id)
            app.overviewDraggedView = outside
            app.overviewDropIndex = app.views.indexOf(outside)
            const home = overviewCard(app.homeView)
            const leave = app.overviewDropTarget(Qt.point(home.x + 30, home.y + 30))
            compare(app.overviewDropGroupId, "")
            app.overviewDraggedView = null
            app.overviewDropIndex = -1
            app.reorderTab(app.views.indexOf(outside), leave, null, false, "")
            compare(outside.tabGroupId, "")
            compare(app.views.filter(view => view.tabGroupId === id).length, 2)
        }

        function test_overview_drag_into_and_out_of_group_container() {
            appSettings.reduceMotion = true
            const first = app.views[1], second = app.views[2], outside = app.views[0]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.toggleOverview()
            findChild(app, "overviewFlickable").resetScroll(0)
            const card = overviewCard(outside)
            const frame = outside.frameContainer
            function drag(end) {
                waitForRendering(app.contentItem)
                const start = card.mapToItem(app.contentItem, card.width / 2, card.height / 2)
                mousePress(app.contentItem, start.x, start.y)
                mouseMove(app.contentItem, start.x + 30, start.y, 20)
                mouseMove(app.contentItem, end.x, end.y, 20)
                tryVerify(() => app.overviewDraggedView === outside)
                fuzzyCompare(card.x, card.dragOriginX, 1, "Membership previews must not shift the grabbed card")
                compare(frame.parent, card)
                mouseRelease(app.contentItem, end.x, end.y)
                tryCompare(app, "overviewDraggedView", null)
                waitForRendering(app.contentItem)
            }
            const container = app.overviewGroupContainer(id)
            drag(container.mapToItem(app.contentItem, 80, 25))
            compare(outside.tabGroupId, id)
            const home = overviewCard(app.homeView)
            drag(home.mapToItem(app.contentItem, 60, 100))
            compare(outside.tabGroupId, "")
            compare(app.views[0], outside)
            verifySelection(second)
            compare(frame.parent, card)
        }

        function test_group_label_release_settles_with_members() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.activateTab(1)
            appSettings.reduceMotion = false
            waitForRendering(app.contentItem)
            const header = app.tabGroupHeaderItem(id)
            const start = header.mapToItem(app.contentItem, 80, 20)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            tryCompare(app, "draggedGroupId", id)
            mouseMove(app.contentItem, start.x + 50, start.y, 20)
            compare(app.groupDropIndex, 0)
            mouseRelease(app.contentItem, start.x + 50, start.y)
            tryCompare(app, "draggedGroupId", "")
            verify(header.settling)
            verify(header.releaseOffset > 0, "A drag within the snap zone still animates back")
            const member = tabButton(0)
            fuzzyCompare(member.fillOffset, header.releaseOffset, 1)
            const offset = header.releaseOffset
            wait(60)
            verify(header.releaseOffset > 0 && header.releaseOffset < offset)
            fuzzyCompare(member.fillOffset, header.releaseOffset, 1, "Members and label use the same release easing")
            tryCompare(header, "settling", false)
            fuzzyCompare(header.releaseOffset, 0, 0.1)
            verifySelection(second)
        }

        function test_collapsed_group_card_body_drags_and_returns_without_expanding() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], selected = app.activeView
            const id = app.createTabGroup(first, "Group card")
            app.assignTabGroup(second, id)
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.toggleOverview()
            const container = app.overviewGroupContainer(id)
            fuzzyCompare(container.width, app.overviewCardWidth, 1)
            fuzzyCompare(container.height, app.overviewCardHeight, 1)
            const header = findChild(container, "overviewGroupHeader")
            fuzzyCompare(header.height, container.height, 1)
            const homeCard = overviewCard(app.homeView)
            fuzzyCompare(container.x, homeCard.viewportX + homeCard.width + app.overviewGap, 1)
            fuzzyCompare(container.y, homeCard.viewportY, 1)
            waitForRendering(app.contentItem)
            findChild(app, "overviewFlickable").resetScroll(0)
            appSettings.reduceMotion = false
            const start = container.mapToItem(app.contentItem, container.width / 2, container.height * 0.7)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y + 15, 20)
            tryCompare(app, "overviewDraggedGroupId", id)
            mouseMove(app.contentItem, start.x + 55, start.y + 25, 20)
            mouseRelease(app.contentItem, start.x + 55, start.y + 25)
            tryCompare(app, "overviewDraggedGroupId", "")
            verify(container.settling)
            tryCompare(container, "settling", false)
            compare(app.groupFor(first).overviewCollapsed, true)
            compare(app.views[0], first)
            compare(app.views[1], second)
            compare(app.activeView, selected)
            appSettings.reduceMotion = true
            mouseClick(container, container.width / 2, container.height * 0.7)
            compare(app.groupFor(first).overviewCollapsed, false)
            compare(String(findChild(container, "overviewGroupArrow").source), "arrow-down")
            compare(header.height, app.overviewCardHeight)
            fuzzyCompare(container.width, app.overviewCardWidth, 1)
            verify(container.expandedArea.y >= container.y + container.height + app.overviewGap - 1)
            verify(overviewCard(first).viewportY >= container.expandedArea.y)
        }

        function test_collapsed_groups_share_grid_slots_and_expand_without_jumping() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            const firstId = app.createTabGroup(first, "First")
            app.assignTabGroup(second, firstId)
            const secondId = app.createTabGroup(third, "Second")
            app.assignTabGroup(fourth, secondId)
            app.activateHome()
            app.updateTabGroup(firstId, {overviewCollapsed: true})
            app.updateTabGroup(secondId, {overviewCollapsed: true})
            app.toggleOverview()
            const firstGroup = app.overviewGroupContainer(firstId), secondGroup = app.overviewGroupContainer(secondId)
            const home = overviewCard(app.homeView)
            fuzzyCompare(firstGroup.y, home.viewportY, 1)
            fuzzyCompare(secondGroup.y, home.viewportY, 1)
            fuzzyCompare(secondGroup.x - firstGroup.x, app.overviewCardWidth + app.overviewGap, 1)
            const origin = Qt.point(firstGroup.x, firstGroup.y)
            appSettings.reduceMotion = false
            app.updateTabGroup(firstId, {overviewCollapsed: false})
            fuzzyCompare(firstGroup.x, origin.x, 1)
            fuzzyCompare(firstGroup.y, origin.y, 1)
            tryCompare(firstGroup, "expanding", false)
            fuzzyCompare(firstGroup.x, origin.x, 1)
            fuzzyCompare(firstGroup.y, origin.y, 1)
            fuzzyCompare(secondGroup.y, origin.y, 1)
            fuzzyCompare(secondGroup.x - firstGroup.x, app.overviewCardWidth + app.overviewGap, 1)
            verify(firstGroup.expandedArea.y >= home.viewportY + home.height + app.overviewGap - 1)
            compare(first.frameContainer.parent, overviewCard(first))
            compare(overviewCard(first).parent, firstGroup.cardArea)
            fuzzyCompare(overviewCard(first).viewportX, app.overviewMargin, 1)
        }

        function test_overview_group_card_can_reorder_between_cards_in_the_same_row() {
            appSettings.reduceMotion = true
            app.width = 1600
            const first = app.views[0], second = app.views[1], before = app.views[2], after = app.views[3]
            const id = app.createTabGroup(first, "Group")
            app.assignTabGroup(second, id)
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.toggleOverview()
            const target = overviewCard(after)
            app.overviewDraggedGroupId = id
            const destination = app.overviewGroupDropTarget(Qt.point(target.viewportX + 10, target.viewportY + target.height / 2))
            compare(destination, 1)
            app.overviewDraggedGroupId = ""
            app.moveTabGroup(id, destination, app.captureTabStripPositions())
            compare(app.views, [before, first, second, after])
            compare(app.groupFor(first).overviewCollapsed, true)
        }

        function test_overview_group_header_drags_container_and_cards_together() {
            appSettings.reduceMotion = true
            app.width = 1600
            app.height = 1200
            const first = app.views[0], second = app.views[1], selected = app.activeView
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            const otherId = app.createTabGroup(app.views[2], "Other")
            app.assignTabGroup(app.views[3], otherId)
            app.toggleOverview()
            app.updateTabGroup(otherId, {overviewCollapsed: true})
            app.updateTabGroup(id, {overviewCollapsed: false}, true)
            findChild(app, "overviewFlickable").resetScroll(0)
            waitForRendering(app.contentItem)
            appSettings.reduceMotion = false
            const container = app.overviewGroupContainer(id)
            const other = app.overviewGroupContainer(otherId)
            const header = findChild(container, "overviewGroupHeader")
            const card = overviewCard(first)
            const frame = first.frameContainer
            const origin = card.mapToItem(app.contentItem, 0, 0)
            const start = header.mapToItem(app.contentItem, 80, 25)
            const end = other.mapToItem(app.contentItem, other.width - 2, other.height / 2)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            mouseMove(app.contentItem, end.x, end.y, 20)
            tryCompare(app, "overviewDraggedGroupId", id)
            compare(app.groupDropIndex, 2)
            compare(card.parent, container.cardArea)
            compare(frame.parent, card)
            fuzzyCompare(card.mapToItem(app.contentItem, 0, 0).y - origin.y, container.dragOffsetY, 1)
            tryVerify(() => tabButton(2).visualOffset < -1, 200)
            mouseRelease(app.contentItem, end.x, end.y)
            tryCompare(app, "overviewDraggedGroupId", "")
            verify(container.settling)
            tryCompare(container, "settling", false)
            verify(app.views[2] === first && app.views[3] === second)
            compare(!!app.groupFor(first).overviewCollapsed, false, "Dragging must not collapse the container")
            compare(card.parent, container.cardArea)
            compare(frame.parent, card)
            verifySelection(selected)
        }

        function test_overview_group_expand_and_collapse_animate_inside_clip() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.activateHome()
            app.toggleOverview()
            findChild(app, "overviewFlickable").resetScroll(0)
            const container = app.overviewGroupContainer(id)
            const card = overviewCard(first), next = overviewCard(second)
            const frame = first.frameContainer
            const bodyHeight = container.expandedArea.height
            const origin = Qt.point(container.x, container.y)
            const neighbor = overviewCard(app.views[2])
            const neighborOrigin = Qt.point(neighbor.viewportX, neighbor.viewportY)
            const grid = findChild(container, "overviewGroupPreviewGrid")
            const arrow = findChild(container, "overviewGroupArrow")
            const arrowY = arrow.y
            function verifyGeometry() {
                fuzzyCompare(container.width, app.overviewCardWidth, 1)
                fuzzyCompare(container.height, app.overviewCardHeight, 1)
                fuzzyCompare(container.x, origin.x, 1)
                fuzzyCompare(container.y, origin.y, 1)
                fuzzyCompare(neighbor.viewportX, neighborOrigin.x, 1)
                fuzzyCompare(neighbor.viewportY, neighborOrigin.y, 1)
                fuzzyCompare(container.expandedArea.height, bodyHeight * container.expansion, 1)
                fuzzyCompare(card.opacity, container.expansion, 0.01)
                fuzzyCompare(next.viewportX - card.viewportX, app.overviewCardWidth + app.overviewGap, 1)
                fuzzyCompare(grid.y, 50 * container.expansion, 0.1)
                fuzzyCompare(grid.opacity, 1 - container.expansion, 0.01)
                fuzzyCompare(arrow.y, arrowY - 50 * (1 - container.expansion), 0.1)
                fuzzyCompare(arrow.opacity, container.expansion, 0.01)
                compare(findChild(container, "overviewGroupPreviewClip").clip, true)
                compare(card.parent, container.cardArea)
                compare(container.cardArea.clip, true)
                compare(frame.parent, card)
            }
            appSettings.reduceMotion = false
            app.updateTabGroup(id, {overviewCollapsed: true})
            compare(container.collapsing, true)
            tryVerify(() => container.expansion > 0 && container.expansion < 1)
            verifyGeometry()
            verify(container.expandedArea.height < bodyHeight)
            verify(container.expandedArea.motionY < 0, "The body exits upward while the tile stays fixed")
            verify(container.expandedArea.y >= container.y + container.height + app.overviewGap - 1,
                   "The moving body is clipped below the entire row")
            tryVerify(() => !!app.groupFor(first).overviewCollapsed)
            compare(container.expansion, 0)
            compare(app.views.length, 4)
            compare(card.visible, false)
            app.updateTabGroup(id, {overviewCollapsed: false})
            compare(container.expanding, true)
            compare(card.visible, true)
            tryVerify(() => container.expansion > 0 && container.expansion < 1)
            verifyGeometry()
            tryCompare(container, "expanding", false)
            compare(container.expansion, 1)
            fuzzyCompare(container.expandedArea.height, bodyHeight, 1)
            fuzzyCompare(card.y, 0, 1)
            compare(grid.opacity, 0)
            compare(arrow.opacity, 1)
        }

        function test_collapsed_group_previews_render_live_and_clip() {
            if (!fixture.gpuMasking) skip("Live preview masks require a GPU renderer")
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            for (const pair of [[first, "#ff0000"], [second, "#00ff00"]]) {
                app.activateTab(app.views.indexOf(pair[0]), false)
                let painted = false
                pair[0].runJavaScript("document.documentElement.style.background='" + pair[1]
                    + "'; document.body.style.cssText='margin:0;height:100vh;background:" + pair[1] + "'", () => painted = true)
                tryVerify(() => painted)
                pair[0].hasLoadedFrame = true
                waitForRendering(app.contentItem)
                wait(100)
            }
            const id = app.createTabGroup(first, "Live previews")
            app.assignTabGroup(second, id)
            app.activateHome()
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.toggleOverview()
            const container = app.overviewGroupContainer(id)
            const grid = findChild(container, "overviewGroupPreviewGrid")
            const cells = grid.children.filter(item => item.objectName === "overviewGroupPreviewCell")
            function centerPixel(index) {
                const point = cells[index].mapToItem(app.contentItem, cells[index].width / 2, cells[index].height / 2)
                return String(grabImage(app.contentItem).pixel(Math.floor(point.x), Math.floor(point.y)))
            }
            tryVerify(() => centerPixel(0) === "#ff0000")
            tryVerify(() => centerPixel(1) === "#00ff00")
            const image = grabImage(app.contentItem)
            const corner = cells[0].mapToItem(app.contentItem, 0, 0)
            verify(String(image.pixel(Math.floor(corner.x), Math.floor(corner.y))) !== "#ff0000", "Round the native webview's corners")
            first.runJavaScript("document.documentElement.style.background='#0000ff';document.body.style.background='#0000ff'")
            tryVerify(() => centerPixel(0) === "#0000ff", 3000, "Collapsed previews remain live")
            const frame = first.frameContainer
            app.updateTabGroup(id, {overviewCollapsed: false})
            compare(first.frameContainer, frame, "Expansion keeps the existing Chromium page")
            compare(frame.parent, overviewCard(first))
            app.updateTabGroup(id, {overviewCollapsed: true})
            compare(frame.parent, cells[0].frameHost)
            tryVerify(() => centerPixel(0) === "#0000ff")
        }

        function test_chromium_tools_menu_actions_have_no_shortcuts() {
            appSettings.reduceMotion = true
            for (const name of ["nativeTaskManagerAction", "nativeDeveloperToolsAction", "taskManagerAction", "developerToolsAction"]) {
                const action = findChild(app, name)
                verify(action)
                verify(action.shortcut === undefined || String(action.shortcut) === "")
            }
            const taskView = app.views[0]
            taskView.loadHtml("<html><body>Task preview</body></html>")
            tryVerify(() => taskView.renderProcessPid > 0)
            app.openTaskManager()
            const manager = findChild(app, "chromiumTaskManagerWindow")
            verify(manager && manager.visible)
            compare(manager.transientParent, null, "The task manager stacks independently of the main window")
            compare(manager.modality, Qt.NonModal)
            verify(manager.flags & Qt.WindowMinimizeButtonHint)
            verify(manager.flags & Qt.WindowMaximizeButtonHint)
            const list = findChild(manager, "chromiumTabList")
            compare(list.count, 5, "The task manager lists Home and each tab, not app processes")
            tryVerify(() => Number.isFinite(manager.tasks[1].memory) && manager.tasks[1].memory > 0
                && Number.isFinite(manager.tasks[1].cpu))
            verify(manager.tasks[1].taskId >= 0)
            compare(findChild(manager, "chromiumTaskRefreshTimer").interval, 1000)
            verify(findChild(manager, "chromiumTaskMonitor").active)
            const end = findChild(manager, "closeTaskManagerTabButton")
            list.currentIndex = 0
            tryCompare(end, "enabled", false, 5000, "Home cannot be closed")
            list.currentIndex = 1
            tryCompare(end, "enabled", true)
            const show = findChild(manager, "showTaskManagerTabButton")
            show.clicked()
            compare(app.activeView, taskView)
            waitForRendering(manager.contentItem)
            mouseClick(list, 20, list.itemAtIndex(1).y + list.itemAtIndex(1).height / 2)
            compare(list.currentIndex, 1, "Clicking a row still selects it")
            const blankY = list.itemAtIndex(4).y + list.itemAtIndex(4).height + 20
            verify(blankY < list.height, "Fixture leaves blank space below the tasks")
            mouseClick(list, 20, blankY)
            compare(list.currentIndex, -1, "Clicking empty list space clears selection")
            compare(show.enabled, false)
            compare(end.enabled, false)
            manager.refreshTasks()
            compare(list.currentIndex, -1, "Resource polling keeps the selection cleared")
            list.currentIndex = 1
            end.clicked()
            tryCompare(list, "count", 4)
            compare(list.currentIndex, -1, "A removed tab must not select another task")
            app.openTab("https://www.figma.com/design/Deferred/Design", null, true, null, null, true)
            manager.refreshTasks()
            compare(list.count, 5)
            compare(manager.tasks[4].state, "Unloaded", "Deferred tabs are included without waking them")
            verify(!Number.isFinite(manager.tasks[4].memory), "Unloaded tabs have no stale memory sample")
            verify(String(manager.tasks[4].view.deferredRestoreUrl).length > 0)
            appSettings.releaseClosedWindows = false
            const monitor = findChild(manager, "chromiumTaskMonitor")
            manager.hide()
            tryCompare(monitor, "active", false)
            compare(findChild(manager, "chromiumTaskRefreshTimer").running, false)
            app.openTaskManager()
            tryCompare(monitor, "active", true)
            appSettings.releaseClosedWindows = true
            manager.close()
            tryVerify(() => !findChild(app, "chromiumTaskManagerWindow"))
            app.openDeveloperTools()
            const developer = findChild(app, "developerToolsWindow")
            verify(developer && developer.visible)
            compare(developer.transientParent, null, "Developer Tools stacks independently of the main window")
            compare(developer.modality, Qt.NonModal)
            compare(developer.inspectedView, app.activeView)
            const inspector = findChild(developer, "chromiumDeveloperTools")
            verify(inspector)
            compare(inspector.inspectedView, app.activeView)
            const first = app.activeView
            app.activateTab(1, false)
            app.openDeveloperTools()
            compare(developer.inspectedView, app.activeView)
            compare(first.devToolsView, null)
            developer.close()
            tryVerify(() => !findChild(app, "developerToolsWindow"))
            compare(app.activeView.devToolsView, null, "Closing tools detaches Chromium's inspector")
        }

        function test_collapsed_group_preview_counts_data() {
            return [0, 1, 2, 3, 4, 8].map(count => ({tag: String(count), count: count}))
        }

        function test_collapsed_group_preview_counts(data) {
            appSettings.reduceMotion = true
            while (app.views.length < Math.max(1, data.count)) {
                app.openTab("about:blank", null, true)
                app.views[app.views.length - 1].stop()
            }
            const members = app.views.slice(0, Math.max(1, data.count))
            const id = app.createTabGroup(members[0], "Preview", "#58aaff", "applications-graphics")
            for (const view of members.slice(1)) app.assignTabGroup(view, id)
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.toggleOverview()
            const container = app.overviewGroupContainer(id)
            if (!data.count) members[0].overviewClosingCard = true
            const grid = findChild(container, "overviewGroupPreviewGrid")
            const cells = grid.children.filter(item => item.objectName === "overviewGroupPreviewCell")
            compare(cells.length, 4)
            for (let index = 0; index < 4; ++index) {
                const cell = cells[index]
                compare(cell.previewView, index < Math.min(3, data.count) ? members[index] : null)
                compare(cell.overflow, index === 3 && data.count > 3)
                compare(cell.placeholder, index >= Math.min(3, data.count) && !cell.overflow)
                compare(cell.border.width, 1)
                compare(cell.width, cells[0].width)
                compare(cell.height, cells[0].height)
                compare(cell.radius, cells[0].radius)
                const counter = findChild(cell, "overviewGroupOverflow")
                compare(counter.text, cell.overflow ? "+" + (data.count - 3) : "")
                compare(counter.visible, cell.overflow)
                verify(cell.x + cell.width <= grid.width + 0.1)
                verify(cell.y + cell.height <= grid.height + 0.1)
            }
            compare(String(findChild(container, "overviewGroupIcon").source), "applications-graphics")
            if (!data.count) members[0].overviewClosingCard = false
        }

        function test_collapsed_group_preview_tracks_membership_and_order() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            const id = app.createTabGroup(first)
            app.assignTabGroup(second, id)
            app.assignTabGroup(third, id)
            app.updateTabGroup(id, {overviewCollapsed: true})
            app.toggleOverview()
            const grid = findChild(app.overviewGroupContainer(id), "overviewGroupPreviewGrid")
            const cells = grid.children.filter(item => item.objectName === "overviewGroupPreviewCell")
            compare(cells[3].placeholder, true)
            app.assignTabGroup(fourth, id)
            compare(findChild(cells[3], "overviewGroupOverflow").text, "+1")
            app.reorderTab(app.views.indexOf(third), 0, null, true)
            compare(cells[0].previewView, third)
            app.assignTabGroup(second, "")
            compare(cells[2].previewView, fourth)
            compare(cells[3].placeholder, true)
        }

        function test_opening_another_group_collapses_the_previous_group() {
            appSettings.reduceMotion = true
            const firstId = app.createTabGroup(app.views[0], "First")
            app.assignTabGroup(app.views[1], firstId)
            const secondId = app.createTabGroup(app.views[2], "Second")
            app.assignTabGroup(app.views[3], secondId)
            app.activateHome()
            app.toggleOverview()
            const first = app.overviewGroupContainer(firstId), second = app.overviewGroupContainer(secondId)
            compare(first.expansion, 1)
            compare(second.expansion, 0)
            const origin = Qt.point(first.x, first.y), otherOrigin = Qt.point(second.x, second.y)
            appSettings.reduceMotion = false
            mouseClick(second, second.width / 2, second.height * 0.7)
            verify(first.collapsing)
            verify(second.expanding)
            wait(60)
            verify(first.expansion > 0 && first.expansion < 1)
            verify(second.expansion > 0 && second.expansion < 1)
            fuzzyCompare(first.x, origin.x, 1)
            fuzzyCompare(first.y, origin.y, 1)
            fuzzyCompare(second.x, otherOrigin.x, 1)
            fuzzyCompare(second.y, otherOrigin.y, 1)
            // Reversing both transitions keeps the current geometry and leaves only one group open.
            const progress = first.expansion
            mouseClick(first, first.width / 2, first.height * 0.7)
            fuzzyCompare(first.expansion, progress, 0.01)
            tryCompare(first, "expanding", false)
            tryCompare(second, "collapsing", false)
            compare(first.expansion, 1)
            compare(second.expansion, 0)
            compare(app.tabGroups.filter(group => !group.overviewCollapsed).length, 1)
            const menu = findChild(app, "tabGroupContextMenu")
            app.showGroupContextMenu(firstId, first.selectionHeader, Qt.point(40, 20))
            compare(menu.groupId, firstId)
            verify(findChild(menu, "changeTabGroupIcon"))
            menu.close()
        }

        function test_overview_group_animation_reverses_without_jumping() {
            appSettings.reduceMotion = true
            const first = app.views[0]
            const id = app.createTabGroup(first, "Reversible")
            for (const view of app.views.slice(1)) app.assignTabGroup(view, id)
            app.toggleOverview()
            const container = app.overviewGroupContainer(id)
            const lastCard = overviewCard(app.views[3])
            const fullHeight = container.expandedArea.height
            appSettings.reduceMotion = false
            app.updateTabGroup(id, {overviewCollapsed: true})
            wait(70)
            const progress = container.expansion, height = container.expandedArea.height, width = container.width
            verify(progress > 0 && progress < 1)
            app.updateTabGroup(id, {overviewCollapsed: false})
            fuzzyCompare(container.expansion, progress, 0.01)
            fuzzyCompare(container.expandedArea.height, height, 1)
            fuzzyCompare(container.width, width, 1)
            tryCompare(container, "expanding", false)
            fuzzyCompare(container.expandedArea.height, fullHeight, 1)
            compare(lastCard.parent, container.cardArea)
            verify(lastCard.y + lastCard.height <= container.cardArea.height)
            app.updateTabGroup(id, {overviewCollapsed: true})
            tryVerify(() => !!app.groupFor(first).overviewCollapsed)
            fuzzyCompare(container.width, app.overviewCardWidth, 1)
            app.width = 1400
            tryVerify(() => Math.abs(container.width - app.overviewCardWidth) < 1)
        }

        function test_grouped_card_zoom_and_close_preserve_frames() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.activateTab(0)
            app.toggleOverview()
            findChild(app, "overviewFlickable").resetScroll(0)
            waitForRendering(app.contentItem)
            const card = overviewCard(second)
            const frame = second.frameContainer
            const position = card.mapToItem(app.contentItem, 0, 0)
            appSettings.reduceMotion = false
            app.selectOverviewView(second)
            verify(card.parent !== app.overviewGroupContainer(id).cardArea, "Zooming lifts the card above its container")
            fuzzyCompare(card.mapToItem(app.contentItem, 0, 0).x, position.x, 1)
            fuzzyCompare(card.mapToItem(app.contentItem, 0, 0).y, position.y, 1)
            compare(frame.parent, card)
            tryCompare(app, "overviewVisible", false)
            compare(app.activeView, second)
            compare(frame.parent, app.browserContent)
            appSettings.reduceMotion = true
            app.toggleOverview()
            appSettings.reduceMotion = false
            const closingCard = overviewCard(first)
            app.closeTab(app.views.indexOf(first))
            verify(closingCard.parent !== app.overviewGroupContainer(id).cardArea,
                   "Closing cards retain their exit animation when the container changes size")
            tryVerify(() => !app.views.includes(first))
            compare(second.frameContainer, frame)
            compare(frame.parent, card)
            compare(card.parent, app.overviewGroupContainer(id).cardArea)
            verifySelection(second)
            app.closeTab(app.views.indexOf(second))
            compare(card.visible, true)
            tryVerify(() => second.overviewEntrance > 0 && second.overviewEntrance < 1)
            verify(card.parent !== app.overviewGroupContainer(id).cardArea,
                   "The last card still animates after its empty container disappears")
            tryVerify(() => !app.views.includes(second))
            compare(app.tabGroups.length, 0)
        }

        function test_shift_f11_autohides_without_changing_window_state_data() {
            return [{tag: "windowed", maximized: false}, {tag: "maximized", maximized: true}]
        }

        function test_shift_f11_autohides_without_changing_window_state(data) {
            appSettings.reduceMotion = true
            if (data.maximized) app.showMaximized()
            else app.showNormal()
            app.requestActivate()
            tryVerify(() => app.active)
            app.contentItem.forceActiveFocus()
            waitForRendering(app.contentItem)
            wait(100) // Allow the compositor's maximize resize before recording geometry.
            const state = app.visibility, width = app.width, height = app.height
            const strip = findChild(app, "tabStrip")
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            compare(app.autoHideToolbar, true)
            compare(app.webFullscreen, false)
            compare(app.visibility, state)
            compare(app.width, width)
            compare(app.height, height)
            tryCompare(strip, "y", -app.tabStripHeight)
            compare(app.browserHeight, app.height)
            mouseMove(app.contentItem, 100, 2, 20)
            tryCompare(strip, "y", 0)
            mouseMove(app.contentItem, 100, 150, 20)
            tryCompare(strip, "y", -app.tabStripHeight)
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            compare(app.autoHideToolbar, false)
            compare(app.visibility, state)
            compare(app.browserHeight, app.height - app.tabStripHeight)
            app.showNormal()
        }

        function test_shift_click_toggles_explicit_tabs_in_strip_and_overview() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            compare(app.selectedTabViews, [])
            mouseClick(tabButton(0), 80, 20, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [first])
            compare(app.activeView, third, "Selection never starts from or switches the focused tab")
            verify(tabButton(0).multiSelected)
            verify(!tabButton(1).multiSelected)
            mouseClick(tabButton(2), 80, 20, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [first, third])
            const tint = findChild(tabButton(2), "tabSelectionTint")
            verify(tint.visible && tint.color.a > 0, "A focused tab still shows the selection tint")
            mouseClick(tabButton(0), 80, 20, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [third], "Shift-click toggles the clicked tab exactly once")
            app.toggleOverview()
            const card = overviewCard(fourth)
            mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.overviewVisible, true)
            compare(app.selectedTabViews, [third, fourth])
            compare(app.activeView, third)
            verify(findChild(overviewCard(third), "overviewCardBorder").color.a > 0)
            compare(findChild(overviewCard(fourth), "overviewCardBorder").border.width, 1)
            mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [third])
            verify(findChild(card, "overviewCardBorder").color.a > 0, "A hovered card keeps its hover tint after deselection")
            const target = overviewCard(second)
            mouseClick(target, target.width / 2, target.height / 2)
            compare(app.overviewVisible, false)
            compare(app.selectedTabViews, [])
            compare(app.activeView, second)
        }

        function test_shift_alt_range_selection_data() {
            return [{tag: "strip-forward", overview: false, reverse: false},
                    {tag: "strip-backward", overview: false, reverse: true},
                    {tag: "overview-forward", overview: true, reverse: false},
                    {tag: "overview-backward", overview: true, reverse: true}]
        }

        function test_shift_alt_range_selection(data) {
            appSettings.reduceMotion = true
            const selected = app.activeView, views = app.views.slice()
            if (data.overview) app.toggleOverview()
            function click(index, modifiers) {
                const item = data.overview ? overviewCard(views[index]) : tabButton(app.views.indexOf(views[index]))
                mouseClick(item, item.width / 2, data.overview ? item.height / 2 : 20, Qt.LeftButton, modifiers)
            }
            const modifiers = Qt.ShiftModifier | Qt.AltModifier
            const start = data.reverse ? 3 : 0, end = data.reverse ? 1 : 2
            click(start, modifiers)
            compare(app.selectedTabViews, [views[start]], "Only the explicit starting click establishes a range")
            click(end, modifiers)
            compare(app.selectedTabViews, data.reverse ? views.slice(1) : views.slice(0, 3))
            compare(app.activeView, selected, "Range selection must not switch tabs")
            click(start, Qt.ShiftModifier)
            verify(!app.selectedTabViews.includes(views[start]), "Shift toggles individual tabs")
            compare(app.rangeSelectionAnchor, null)
            app.selectedTabViews = []
            click(end, modifiers)
            compare(app.selectedTabViews, [views[end]], "Clearing a selection starts a new range")
        }

        function test_selected_tabs_drag_together_into_and_out_of_groups_data() {
            return [{tag: "strip", overview: false, motion: false},
                    {tag: "overview", overview: true, motion: false},
                    {tag: "overview-animated", overview: true, motion: true},
                    {tag: "strip-empty-group", overview: false, motion: false, emptyGroup: true},
                    {tag: "overview-empty-group", overview: true, motion: true, emptyGroup: true}]
        }

        function test_selected_tabs_drag_together_into_and_out_of_groups(data) {
            appSettings.reduceMotion = true
            const original = app.views.slice(), focused = app.activeView
            let moving = [original[0], original[2]]
            const anchor = moving[1]
            const id = app.createTabGroup(original[1], "Batch drag")
            app.updateTabGroup(id, {overviewCollapsed: true}, true)
            let frames = moving.map(view => view.frameContainer)
            for (const view of moving) app.selectFileTabs(view, Qt.ShiftModifier)
            if (data.overview) {
                app.toggleOverview()
                findChild(app, "overviewFlickable").resetScroll(0)
            }
            appSettings.reduceMotion = !data.motion
            function drag(target) {
                const item = data.overview ? overviewCard(anchor) : tabButton(app.views.indexOf(anchor))
                waitForRendering(app.contentItem)
                const start = item.mapToItem(app.contentItem, data.overview ? item.width / 2 : item.groupPrefix + 80,
                                            data.overview ? item.height / 2 : 20)
                mousePress(app.contentItem, start.x, start.y)
                mouseMove(app.contentItem, start.x + 30, start.y, 20)
                mouseMove(app.contentItem, target.x, target.y, 20)
                tryCompare(app, "dragViews", moving)
                if (data.overview) {
                    const peer = overviewCard(moving[0])
                    verify(peer.floating, "Selected peers must not be clipped by their old group")
                    compare(peer.previewView.frameContainer.parent, peer)
                    compare(anchor.frameContainer.parent, item)
                }
                mouseRelease(app.contentItem, target.x, target.y)
                tryCompare(app, "dragViews", [])
                wait(300)
                compare(app.activeView, focused, "A block move preserves the focused webview")
                compare(app.selectedTabViews, moving)
                compare(app.views.filter(view => moving.includes(view)), moving, "The block keeps its original tab order")
                for (let index = 0; index < moving.length; ++index) compare(moving[index].frameContainer, frames[index])
            }
            const header = data.overview ? app.overviewGroupContainer(id) : app.tabGroupHeaderItem(id)
            drag(header.mapToItem(app.contentItem, 80, 25))
            for (const view of moving) compare(view.tabGroupId, id)
            const members = app.views.filter(view => view.tabGroupId === id)
            compare(members.length, 3)
            compare(app.views.indexOf(members[2]) - app.views.indexOf(members[0]), 2)
            if (data.emptyGroup) {
                moving = members
                frames = moving.map(view => view.frameContainer)
                app.selectedTabViews = moving
            }
            const home = data.overview ? overviewCard(app.homeView) : null
            const leave = data.overview ? home.mapToItem(app.contentItem, 60, 100)
                                       : app.tabGroupHeaderItem(id).mapToItem(app.contentItem, -40, 20)
            drag(leave)
            for (const view of moving) compare(view.tabGroupId, "")
            compare(app.views.indexOf(moving[1]), app.views.indexOf(moving[0]) + 1)
            compare(original[1].tabGroupId, data.emptyGroup ? "" : id)
            if (data.emptyGroup) compare(app.tabGroups.length, 0)
        }

        function test_selection_escape_and_click_away() {
            appSettings.reduceMotion = true
            app.requestActivate()
            tryVerify(() => app.active)
            app.contentItem.forceActiveFocus()
            app.selectFileTabs(app.views[0], Qt.ShiftModifier)
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            app.selectFileTabs(app.views[0], Qt.ShiftModifier)
            app.toggleToolbarAutoHide()
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            verify(app.autoHideToolbar, "Escape clears selection without disabling autohide")
            keyClick(Qt.Key_Escape)
            verify(app.autoHideToolbar, "Escape with no selection also keeps autohide enabled")
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            verify(!app.autoHideToolbar)
            app.selectFileTabs(app.views[0], Qt.ShiftModifier)
            mouseClick(tabButton(1), 80, 20)
            compare(app.selectedTabViews, [])
            app.selectFileTabs(app.views[0], Qt.ShiftModifier)
            mouseClick(app.contentItem, app.width - 5, app.height - 5)
            tryCompare(app, "selectedTabViews", [])
            app.toggleOverview()
            app.selectFileTabs(app.views[0], Qt.ShiftModifier, true)
            mouseClick(findChild(app, "overviewSearch"), 100, 15)
            tryCompare(app, "selectedTabViews", [])
        }

        function test_overview_drag_box_selects_cards_inside_groups() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2]
            const id = app.createTabGroup(first, "Box", "#ab3344")
            app.assignTabGroup(second, id)
            app.toggleOverview()
            wait(20)
            const flick = findChild(app, "overviewFlickable")
            const card = overviewCard(first), next = overviewCard(second)
            const start = card.mapToItem(app.contentItem, -4, 4)
            const end = next.mapToItem(app.contentItem, next.width + 4, next.height + 4)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, end.x, end.y, 30)
            verify(findChild(app, "overviewSelectionBox").visible)
            compare(app.selectedTabViews, [first, second])
            verify(!app.selectedTabViews.includes(app.homeView))
            compare(app.overviewDraggedView, null)
            mouseRelease(app.contentItem, end.x, end.y)
            compare(findChild(app, "overviewSelectionBox").visible, false)
            compare(app.selectedTabViews, [first, second])
            const blank = card.mapToItem(app.contentItem, -4, card.height + 5)
            mouseClick(app.contentItem, blank.x, blank.y)
            tryCompare(app, "selectedTabViews", [])
            app.updateTabGroup(id, {overviewCollapsed: true}, true)
            app.selectOverviewRectangle(Qt.rect(0, 0, flick.contentWidth, flick.contentHeight), [])
            verify(!app.selectedTabViews.includes(first) && !app.selectedTabViews.includes(second))
            verify(app.selectedTabViews.includes(third))
        }

        function test_tab_pointer_click_does_not_restart_the_switch_animation() {
            const previous = app.activeView
            mouseClick(tabButton(0), 80, 20)
            compare(app.activeView, app.views[0])
            compare(app.outgoingView, previous, "The second click handler must not cancel the transition")
            tryCompare(app, "outgoingView", null)
        }

        function test_shift_selection_survives_reorder_and_box_excludes_hidden_search_results() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            first.url = "about:blank#match-one"
            third.url = "about:blank#match-two"
            app.selectFileTabs(first, Qt.ShiftModifier)
            app.selectFileTabs(third, Qt.ShiftModifier)
            app.reorderTab(0, 3)
            compare(app.selectedTabViews, [first, third], "Selection follows view identities when reordered")
            app.toggleOverview()
            findChild(app, "overviewSearch").text = "match"
            const flick = findChild(app, "overviewFlickable")
            app.selectOverviewRectangle(Qt.rect(0, 0, flick.contentWidth, flick.contentHeight), [])
            compare(app.selectedTabViews, [third, first], "Drag-box selection ignores hidden results")
            app.closeSelectedTabs(third)
            tryCompare(app, "views", [second, fourth], 5000)
        }

        function test_shift_selection_new_group_and_bulk_close() {
            appSettings.reduceMotion = true
            const targets = app.views.slice(0, 3), remaining = app.views[3]
            app.activateTab(0)
            app.toggleOverview()
            for (const target of targets) {
                const card = overviewCard(target)
                mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            }
            app.requestTabGroup(targets[1])
            findChild(app, "tabGroupNameEditor").text = "Batch"
            findChild(app, "tabGroupNameDialog").accept()
            compare(app.tabGroups.length, 1)
            for (const view of targets) compare(view.tabGroupId, app.tabGroups[0].id)
            tryCompare(findChild(app, "tabGroupNameDialog"), "visible", false)
            waitForRendering(app.contentItem)
            const selectedCard = overviewCard(targets[1])
            mouseClick(selectedCard, selectedCard.width / 2, selectedCard.height / 2, Qt.RightButton)
            const menu = findChild(selectedCard, "overviewTabMenu")
            tryCompare(menu, "visible", true)
            const close = Array.from({length: menu.count}, (_, index) => menu.itemAt(index))
                .find(item => item.text === "Close selected tabs")
            verify(close)
            tryCompare(menu, "opened", true)
            waitForRendering(app.contentItem)
            mouseClick(close, close.width / 2, close.height / 2)
            tryCompare(app, "views", [remaining])
            compare(app.tabGroups.length, 0)
            compare(app.selectedTabViews.length, 0)
            compare(app.overviewVisible, true)
        }

        function test_fullscreen_hides_toolbar_and_reveals_at_top() {
            const strip = findChild(app, "tabStrip")
            app.requestActivate()
            tryVerify(() => app.active)
            app.contentItem.forceActiveFocus()
            mouseMove(app.contentItem, 100, 150, 20)
            keyClick(Qt.Key_F11)
            compare(app.webFullscreen, true)
            tryCompare(strip, "y", -app.tabStripHeight)
            compare(app.browserHeight, app.height)
            mouseMove(app.contentItem, 100, 2, 20)
            tryCompare(strip, "y", 0)
            mouseMove(app.contentItem, 100, 150, 20)
            tryCompare(strip, "y", -app.tabStripHeight)
            keyClick(Qt.Key_F11)
            compare(app.webFullscreen, false)
            tryCompare(strip, "y", 0)
            compare(app.browserHeight, app.height - app.tabStripHeight)
        }

        function test_shift_f11_toggles_toolbar_hiding_in_fullscreen() {
            appSettings.reduceMotion = true
            app.requestActivate()
            tryVerify(() => app.active)
            app.contentItem.forceActiveFocus()
            mouseMove(app.contentItem, 100, 150, 20)
            keyClick(Qt.Key_F11)
            compare(app.visibility, Window.FullScreen)
            verify(app.toolbarAutoHidden)
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            compare(app.visibility, Window.FullScreen)
            verify(!app.toolbarAutoHidden)
            compare(findChild(app, "tabStrip").y, 0)
            compare(app.browserHeight, app.height - app.tabStripHeight)
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            verify(app.toolbarAutoHidden)
            compare(app.visibility, Window.FullScreen)
            compare(findChild(app, "tabStrip").y, -app.tabStripHeight)
            keyClick(Qt.Key_F11, Qt.ShiftModifier)
            keyClick(Qt.Key_Escape)
            verify(app.webFullscreen, "Escape must not leave fullscreen when the toolbar is pinned")
            keyClick(Qt.Key_F11)
            verify(!app.webFullscreen)
        }

        function test_fullscreen_only_exits_with_mapped_shortcut_data() {
            return [{tag: "default", remapped: false}, {tag: "remapped", remapped: true}]
        }

        function test_fullscreen_only_exits_with_mapped_shortcut(data) {
            appSettings.reduceMotion = true
            if (data.remapped) appSettings.shortcutOverrides = {fullscreen: "F10"}
            app.requestActivate()
            tryVerify(() => app.active)
            app.contentItem.forceActiveFocus()
            const fullscreenKey = data.remapped ? Qt.Key_F10 : Qt.Key_F11
            keyClick(fullscreenKey)
            verify(app.webFullscreen)
            app.selectFileTabs(app.views[0], Qt.ShiftModifier)
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            verify(app.webFullscreen, "Escape only clears selected tabs")
            const autohide = app.autoHideToolbar
            app.activeView.forceActiveFocus()
            keyClick(Qt.Key_Escape)
            verify(app.webFullscreen, "Escape in Chromium does not exit app fullscreen")
            compare(app.autoHideToolbar, autohide)
            if (data.remapped) {
                keyClick(Qt.Key_F11)
                verify(app.webFullscreen, "The old fullscreen key no longer exits")
            }
            keyClick(fullscreenKey)
            verify(!app.webFullscreen, "The configured fullscreen shortcut exits")
        }

        function test_escape_closes_overview_without_changing_window_mode_data() {
            return [{tag: "windowed"}, {tag: "autohide", autohide: true}, {tag: "fullscreen", fullscreen: true}]
        }

        function test_escape_closes_overview_without_changing_window_mode(data) {
            appSettings.reduceMotion = true
            app.requestActivate()
            tryVerify(() => app.active)
            if (data.fullscreen) app.toggleWebFullscreen()
            else if (data.autohide) app.toggleToolbarAutoHide()
            const visibility = app.visibility, autohide = app.autoHideToolbar, focused = app.activeView
            app.toggleOverview()
            app.selectFileTabs(app.views[0], Qt.ShiftModifier, true)
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            verify(app.overviewVisible, "The first Escape only clears selections")
            keyClick(Qt.Key_Escape)
            compare(app.overviewVisible, false, "Escape without a selection exits the overview")
            compare(app.activeView, focused)
            compare(app.visibility, visibility)
            compare(app.autoHideToolbar, autohide)
            keyClick(Qt.Key_Escape)
            compare(app.visibility, visibility)
            compare(app.autoHideToolbar, autohide)
        }

        function test_about_shows_version_and_build_commit() {
            app.openAbout()
            const about = findChild(app, "aboutWindow")
            compare(findChild(about, "aboutVersion").text, "Version " + Qt.application.version)
            compare(findChild(about, "aboutCommit").text, "Commit abc1234")
        }

        function test_maximize_from_fullscreen_keeps_autohide() {
            appSettings.reduceMotion = true
            appSettings.windowControlsInTabBar = true
            app.showNormal()
            app.toggleWebFullscreen()
            mouseMove(app.contentItem, 100, 2, 20)
            const strip = findChild(app, "tabStrip")
            tryCompare(strip, "y", 0)
            const maximize = findChild(app, "maximizeWindowButton")
            mouseClick(maximize, maximize.width / 2, maximize.height / 2)
            compare(app.visibility, Window.Maximized)
            compare(app.webFullscreen, false)
            verify(app.autoHideToolbar)
            mouseMove(app.contentItem, 100, 150, 20)
            tryCompare(strip, "y", -app.tabStripHeight)
            compare(app.browserHeight, app.height)
            app.showNormal()
        }

        function test_autohide_reveal_zone_does_not_cover_figma_toolbar() {
            appSettings.reduceMotion = true
            app.toggleToolbarAutoHide()
            const strip = findChild(app, "tabStrip")
            mouseMove(app.contentItem, 100, 150, 20)
            mouseMove(app.contentItem, 100, 12, 20)
            compare(strip.y, -app.tabStripHeight, "Figma's top controls must not reveal the app toolbar")
            mouseMove(app.contentItem, 100, 2, 20)
            tryCompare(strip, "y", 0)
            mouseMove(app.contentItem, 100, app.tabStripHeight - 4, 20)
            compare(strip.y, 0, "Keep the revealed toolbar open while using its controls")
            mouseMove(app.contentItem, 100, 150, 20)
            tryCompare(strip, "y", -app.tabStripHeight)
            mouseMove(app.contentItem, 100, 12, 20)
            compare(strip.y, -app.tabStripHeight)
        }

        function test_only_home_can_create_notifications_with_shared_permission() {
            appSettings.desktopNotifications = true
            appSettings.changed()
            fixture.notificationCount = 0
            const permission = testProfile.queryPermission("https://www.figma.com", CefPermission.PermissionType.Notifications)
            permission.grant()
            const home = notificationProbe.createObject(fixture, {"userScripts.collection": app.homeView.userScripts.collection})
            home.loadHtml("<html><body>Home</body></html>", "https://www.figma.com/")
            let allowed = null
            tryVerify(() => {
                home.runJavaScript("Notification.permission", value => allowed = value)
                return allowed === "granted"
            })
            home.runJavaScript("new Notification('ReSketch test', {body:'Home notification'})")
            tryCompare(fixture, "notificationCount", 1)
            const view = notificationProbe.createObject(fixture, {"userScripts.collection": app.views[0].userScripts.collection})
            view.loadHtml("<html><body>File</body></html>", "https://www.figma.com/design/Test/File")
            let result = null
            tryVerify(() => {
                view.runJavaScript("({permission:Notification.permission,ready:typeof __resketchSetNotifications === 'function' && document.body.textContent === 'File'})", value => result = value)
                return result?.ready && result?.permission === "denied"
            })
            let error = null
            view.runJavaScript("(()=>{try{new Notification('Duplicate')}catch(e){return e.name}})()", value => error = value)
            tryVerify(() => error === "NotAllowedError")
            compare(fixture.notificationCount, 1)
            home.destroy()
            view.destroy()
            appSettings.keepHomeAwake = false
            appSettings.maximumLoadedTabs = 1
            app.updateTabLifecycle()
            compare(app.homeView.lifecycleState, CefView.LifecycleState.Active)
        }

        function test_remembered_files_restore_behind_home_and_update_session_urls_data() {
            return [{tag: "on_selection", defer: true}, {tag: "immediately", defer: false}]
        }

        function test_remembered_files_restore_behind_home_and_update_session_urls(data) {
            const files = ["https://www.figma.com/design/Restore_A/First", "https://www.figma.com/board/Restore_B/Second"]
            appSettings.rememberOpenedTabs = true
            appSettings.deferRestoredTabs = data.defer
            appSettings.reduceMotion = true
            appSettings.rememberedFileTabs = files
            appSettings.rememberedTabGroups = [{title: "Restored group", color: "#4477aa", icon: "folder",
                collapsed: true, overviewCollapsed: true, tabs: [0, 1]}]
            const component = Qt.createComponent("../src/Main.qml")
            compare(component.status, Component.Ready)
            const window = component.createObject(app, {sharedProfile: testProfile})
            verify(window)
            window.homeView.stop()
            if (!data.defer)
                for (const view of window.views) view.stop()
            compare(window.views.length, 2)
            compare(window.activeView, window.homeView)
            compare(window.sessionFileUrls, files)
            compare(window.tabGroups.length, 1)
            compare(window.groupFor(window.views[0]).id, window.groupFor(window.views[1]).id)
            compare(window.sessionTabGroups, appSettings.rememberedTabGroups)
            compare(window.nextGroupNumber, 2)
            if (data.defer) {
                window.updateTabLifecycle()
                window.toggleOverview()
                wait(100)
                for (let i = 0; i < files.length; ++i) {
                    compare(String(window.views[i].deferredRestoreUrl), files[i])
                    compare(String(window.views[i].tabUrl), files[i])
                    verify(!String(window.views[i].url).includes("figma.com"))
                    compare(window.views[i].loading, false)
                    compare(window.views[i].hasLoadedFrame, false)
                    compare(window.views[i].visible, false)
                    compare(tabButton(i, window).loading, false)
                }
                window.selectOverviewView(window.views[0])
                compare(window.activeView, window.views[0])
                compare(String(window.views[0].deferredRestoreUrl), "")
                compare(String(window.views[0].url), files[0])
                window.views[0].stop()
                compare(String(window.views[1].deferredRestoreUrl), files[1])
                window.activateTab(1)
                compare(String(window.views[1].deferredRestoreUrl), "")
                compare(String(window.views[1].url), files[1])
                window.views[1].stop()
            } else {
                for (let i = 0; i < files.length; ++i) {
                    compare(String(window.views[i].deferredRestoreUrl), "")
                    compare(String(window.views[i].url), files[i])
                }
            }
            window.openTab("about:blank", null, true)
            window.views[2].stop()
            compare(window.sessionFileUrls, files)
            window.views[0].url = "about:blank"
            compare(window.sessionFileUrls, [files[1]])
            // A detached window must not restore the same session again.
            const detached = window.createDetachedWindow("", testProfile)
            verify(detached)
            detached.homeView.stop()
            compare(detached.views.length, 0)
            compare(detached.tabGroups.length, 0)
            detached.close()
            window.close()
            window.destroy()
        }

        function test_new_tabs_append_except_links_next_to_source_tab() {
            appSettings.reduceMotion = true
            appSettings.changed()
            app.activateTab(1)
            const selected = app.activeView
            app.openTab("about:blank")
            compare(app.views[1], selected)
            compare(app.activeIndex, 4)
            app.activateTab(1)
            app.openTab("about:blank", null, true, selected)
            compare(app.views[1], selected)
            compare(app.activeView, selected)
            compare(app.activeIndex, 1)
            app.openTab("about:blank", null, false, selected)
            compare(app.activeIndex, 2)
            compare(app.views[1], selected)
            app.activateTab(0)
            const first = app.activeView
            app.toggleOverview()
            app.openTab("about:blank", null, true)
            compare(app.views[0], first)
            compare(app.activeView, first)
            compare(app.overviewVisible, true)
            compare(app.views.length, 8)
            app.dismissOverview()
            app.activateHome()
            app.openTab("about:blank", null, false, app.homeView)
            compare(app.activeIndex, 8)
            app.activateHome()
            app.openTab("about:blank")
            compare(app.activeIndex, 9)
            // A delayed popup still belongs next to its original source.
            app.openTab("about:blank", null, false, selected)
            compare(app.views[1], selected)
            compare(app.activeIndex, 2)
        }

        function test_pending_popups_keep_content_when_promoted_to_tabs_or_signin() {
            const source = app.activeView
            source.runJavaScript("window.pendingTest = window.open('about:blank', '_blank'); pendingTest.keepContent = 123")
            tryVerify(() => app.pendingPopups.length === 1)
            const pending = app.pendingPopups[0]
            const count = app.views.length
            let value = null
            pending.runJavaScript("keepContent", result => value = result)
            tryCompare({get content() { return value }}, "content", 123)
            app.commitPendingPopup(pending)
            compare(app.views.length, count + 1)
            compare(app.activeView, pending)
            compare(app.activeIndex, app.views.indexOf(source) + 1)
            value = null
            pending.runJavaScript("keepContent", result => value = result)
            tryVerify(() => value === 123)

            source.runJavaScript("window.signinTest = window.open('about:blank', '_blank'); signinTest.keepSignin = 456")
            tryVerify(() => app.pendingPopups.length === 1)
            const signin = app.pendingPopups[0]
            app.openGoogleSignInWindow(null, "", signin)
            compare(app.pendingPopups.length, 0)
            compare(app.views.length, count + 1)
            compare(signin.authWindow.authView, signin)
            compare(signin.authWindow.transientParent, null)
            value = null
            signin.runJavaScript("keepSignin", result => value = result)
            tryVerify(() => value === 456)
            signin.authWindow.close()
            tryVerify(() => findChild(app, "googleSignInWindow") === null)
            compare(findChild(app, "signInRefreshTimer").running, false,
                    "Closing sign-in manually must not reload the original tab")
        }

        function test_google_signin_refreshes_its_source_after_four_seconds() {
            const source = app.activeView
            source.loadHtml("<html><body>Sign-in source</body></html>")
            tryVerify(() => !source.loading)
            source.runJavaScript("window.signinTest = window.open('about:blank', '_blank')")
            tryVerify(() => app.pendingPopups.length === 1)
            const signin = app.pendingPopups[0]
            app.openGoogleSignInWindow(null, "", signin)
            const timer = findChild(app, "signInRefreshTimer")
            compare(signin.authWindow.sourceView, source)
            compare(timer.interval, 4000)
            let marker = null
            source.runJavaScript("window.beforeSignInRefresh = 123", () => marker = true)
            tryVerify(() => marker === true)
            app.activateTab(0, false)
            const selected = app.activeView
            selected.runJavaScript("window.otherTabContent = 456", () => marker = 456)
            tryVerify(() => marker === 456)
            // Google/Figma completes OAuth by closing its popup through window.close().
            signin.windowCloseRequested()
            tryVerify(() => findChild(app, "googleSignInWindow") === null)
            compare(timer.running, true)
            compare(timer.sourceView, source)
            wait(3500)
            source.runJavaScript("window.beforeSignInRefresh", result => marker = result)
            tryVerify(() => marker === 123, 400)
            tryCompare(timer, "running", false, 2000)
            tryVerify(() => !source.loading)
            marker = 123
            source.runJavaScript("typeof window.beforeSignInRefresh", result => marker = result)
            tryVerify(() => marker === "undefined")
            selected.runJavaScript("window.otherTabContent", result => marker = result)
            tryVerify(() => marker === 456, 1000, "Only the sign-in source is refreshed")
            compare(app.activeView, selected)
        }

        function test_external_links_leave_the_webview_and_do_not_create_tabs() {
            const view = app.activeView
            const count = app.views.length
            view.url = "https://example.com/resketch-external-link"
            tryCompare(app, "externalLinks", ["https://example.com/resketch-external-link"])
            compare(app.views.length, count)
            compare(app.activeView, view)
            view.runJavaScript("window.open('https://example.com/start_google_sso', '_blank')")
            tryCompare(app, "externalLinks", ["https://example.com/resketch-external-link",
                                             "https://example.com/start_google_sso"])
            compare(app.views.length, count)
            compare(app.activeView, view)
            view.runJavaScript("var externalPopup = window.open('about:blank', '_blank'); externalPopup.location = 'https://example.com/blank-popup'")
            tryCompare(app, "externalLinks", ["https://example.com/resketch-external-link",
                                             "https://example.com/start_google_sso",
                                             "https://example.com/blank-popup"])
            tryCompare(app, "pendingPopups", [])
            compare(app.views.length, count)
            compare(app.activeView, view)
            compare(findChild(app, "googleSignInWindow"), null)
        }

        function cleanup() {
            findChild(app, "tabGroupContextMenu").close()
            findChild(app, "tabGroupNameDialog").reject()
            for (const group of app.tabGroups.slice()) app.ungroupTabs(group.id)
            app.nextGroupNumber = 1
            appSettings.desktopNotifications = false
            if (app.webFullscreen) app.toggleWebFullscreen()
            if (app.autoHideToolbar) app.toggleToolbarAutoHide()
            app.selectedTabViews = []
            appSettings.shortcutOverrides = {}
            app.width = 1280
            app.height = 800
            appSettings.rememberOpenedTabs = false
            appSettings.deferRestoredTabs = true
            appSettings.rememberedFileTabs = []
            appSettings.rememberedTabGroups = []
            nativeDropEvents.stop()
            nativeDropEvents.callback = null
            appSettings.nativeTabDragSupported = false
            app.cancelItemDrag()
            appSettings.sleepingTabPreviews = false
            appSettings.keepHomeAwake = true
            appSettings.translucentSidebars = false
            appSettings.floatingSidebars = false
            appSettings.useSystemCursor = false
            appSettings.sidebarCornerRadius = 12
            appSettings.sidebarMargin = 8
            appSettings.hideFloatingScrollbars = true
            appSettings.toolbarOpacity = 100
            appSettings.toolbarItems = appSettings.defaultToolbarItems()
            appSettings.sidebarBackdrop = "desktop"
            appSettings.sidebarCanvasBlur = 0
            appSettings.sidebarCanvasOpacity = 100
            appSettings.memoryLimitMiB = 0
            appSettings.sleepMinutes = 5
            appSettings.maximumLoadedTabs = 5
            appSettings.minimumLoadedTabs = 5
            appSettings.releaseClosedWindows = true
            appSettings.cullOffscreenOverviewEffects = true
            appSettings.compactPreviewTextures = true
            appSettings.overviewPreviewQuality = 100
            appSettings.figmaCustomCss = ""
            appSettings.gpuAccelerationWarning = ""
            appSettings.changed()
            for (const name of ["settingsWindow", "aboutWindow", "exportHistoryWindow"]) {
                const window = findChild(app, name)
                if (window) window.close()
            }
            transferLoads.target = null
            for (const window of app.detachedWindows.slice()) window.close()
            app.dismissOverview()
            app.show()
        }

        function test_hidden_canvas_scrollbars_preserve_edge_pixels() {
            appSettings.reduceMotion = true
            const view = app.activeView
            let ready = false
            view.runJavaScript('document.body.innerHTML="<style>body{margin:0}.gpu-view-content{position:absolute;inset:0;background:#444}</style><div class=gpu-view-content><canvas></canvas></div>";'
                + 'const c=document.querySelector("canvas");c.width=innerWidth;c.height=innerHeight;'
                + 'const p=c.getContext("2d");p.fillStyle="#00ff00";p.fillRect(0,0,c.width,c.height);'
                + 'p.fillStyle="#ff0000";p.fillRect(c.width-12,0,12,c.height);p.fillRect(0,c.height-12,c.width,12);'
                + '(()=>{const location={pathname:"/design/Test/File"};' + FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                + ';sidebarAppearance({theme:"dark",floatingSidebars:true,hideFloatingScrollbars:true,sidebarBackdrop:"desktop",opacity:85,sidebarMargin:8,sidebarCornerRadius:8},(id,css)=>{'
                + 'let s=document.createElement("style");s.id=id;s.textContent=css;document.head.appendChild(s)})})()', () => ready = true)
            tryVerify(() => ready)
            view.hasLoadedFrame = true
            tryVerify(() => {
                const image = grabImage(app.contentItem)
                const right = view.mapToItem(app.contentItem, view.width - 2, view.height / 2)
                const bottom = view.mapToItem(app.contentItem, view.width / 2, view.height - 2)
                return String(image.pixel(Math.floor(right.x), Math.floor(right.y))) === "#ff0000"
                    && String(image.pixel(Math.floor(bottom.x), Math.floor(bottom.y))) === "#ff0000"
            }, 5000, "The right and bottom canvas pixels must remain visible with scrollbar hiding enabled")
        }

        function test_canvas_scrollbar_toggle_reloads_files_and_defers_sleeping_tabs() {
            appSettings.floatingSidebars = true
            appSettings.hideFloatingScrollbars = true
            let reloads = 0
            const view = {url:"https://www.figma.com/design/Test/File", loading:false,
                lifecycleState:CefView.LifecycleState.Active, hasLoadedFrame:true,
                canvasScrollbarsHiddenAtLoad:false, reload:() => ++reloads,
                runJavaScript:() => {}, syncNotifications:() => {}}
            app.syncFigmaTheme(view)
            compare(reloads, 1, "Awake file tabs apply scrollbar changes automatically")
            app.syncFigmaTheme(view)
            compare(reloads, 1, "The same setting does not reload again")
            view.lifecycleState = CefView.LifecycleState.Frozen
            appSettings.hideFloatingScrollbars = false
            app.syncFigmaTheme(view)
            compare(reloads, 1, "Changing visibility does not wake sleeping tabs")
            view.lifecycleState = CefView.LifecycleState.Active
            app.syncFigmaTheme(view)
            compare(reloads, 2, "Waking a tab applies its pending scrollbar preference")
            view.url = "https://www.figma.com/files/recent"
            appSettings.hideFloatingScrollbars = true
            app.syncFigmaTheme(view)
            compare(reloads, 2, "Home stays running when canvas scrollbar visibility changes")
        }

        function test_floating_sidebars_clip_comment_pins_data() {
            return [{tag:"comments", className:"comments_view--outerAnchorContainer--fixture"},
                    {tag:"collaborator-cursors", className:"multiplayer_cursors--root--fixture"},
                    {tag:"viewport-overlay", className:"viewport_overlay--overflowContainer--fixture"}]
        }

        function test_floating_sidebars_clip_comment_pins(data) {
            const view = app.activeView
            const fixture = '<style>body{margin:0;--color-bg:#eee;--color-border:#8899aa}'
                + '.gpu-view-content{position:absolute;inset:0;background:#444}'
                + 'aside,nav{position:absolute;top:0;width:200px;height:400px}aside{right:0}nav{left:0}'
                + '#pins{position:absolute;left:220px;right:220px;top:0;bottom:0;z-index:999;pointer-events:none}'
                + '#pin,#leftPin{position:absolute;top:80px;width:30px;height:30px;background:red;pointer-events:auto}#pin{right:-120px}#leftPin{left:-120px}'
                + '</style><div class="gpu-view-content"></div><nav data-onboarding-key="unified-design-onboarding-left-panel"></nav><aside data-testid="properties-panel"></aside>'
                + '<div id="pins" class="' + data.className + '"><div id="pin"></div><div id="leftPin"></div></div>'
            let ready = false, result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture), () => ready = true)
            tryVerify(() => ready)
            const options = {theme:"light", floatingSidebars:true, sidebarCornerRadius:22, sidebarMargin:8,
                             translucentSidebars:false, opacity:60, sidebarBackdrop:"desktop"}
            function apply() {
                view.runJavaScript('(()=>{const location={pathname:"/design/Test/File"};'
                    + FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                    + ';sidebarAppearance(' + JSON.stringify(options) + ',(id,css)=>{'
                    + 'let s=document.getElementById(id);if(!css){s?.remove();return}'
                    + 'if(!s){s=document.createElement("style");s.id=id;document.head.appendChild(s)}s.textContent=css;});})()')
            }
            function inspect() {
                view.runJavaScript('(()=>{const pin=document.getElementById("pin"),r=pin.getBoundingClientRect();'
                    + 'const left=document.getElementById("leftPin"),l=left.getBoundingClientRect();'
                    + 'return {clip:getComputedStyle(document.getElementById("pins")).clipPath,leftVisible:document.elementFromPoint(l.x+15,l.y+15)===left,'
                    + 'pinVisible:document.elementFromPoint(r.x+15,r.y+15)===pin}})()', value => result = value)
            }
            apply()
            tryVerify(() => { inspect(); return result?.clip.startsWith("path(evenodd,") && !result.pinVisible })
            compare(result.leftVisible, false, "Pins overflowing an inset layer stay behind the left sidebar")
            options.sidebarCornerRadius = 0
            apply()
            tryVerify(() => { inspect(); return result?.clip.startsWith("polygon(evenodd,") && !result.pinVisible && !result.leftVisible })
            options.sidebarCornerRadius = 22
            // Mask comment pins for both backdrop modes, including opaque panels.
            options.sidebarBackdrop = "canvas"
            options.opacity = 100
            apply()
            tryVerify(() => { inspect(); return result?.clip.startsWith("path(evenodd,") && !result.pinVisible })
            view.runJavaScript('document.getElementById("pin").style.right="300px"')
            tryVerify(() => { inspect(); return result?.pinVisible })
            view.runJavaScript('document.getElementById("leftPin").style.left="80px"')
            tryVerify(() => { inspect(); return result?.leftVisible })
            // Resized/replaced comment overlays must keep the cutout aligned.
            const originalClip = result.clip
            view.runJavaScript('document.getElementById("pins").style.left="40px";document.getElementById("pin").style.right="-120px"')
            tryVerify(() => { inspect(); return result?.clip.startsWith("path(evenodd,") && result.clip !== originalClip && !result.pinVisible })
            options.floatingSidebars = false
            apply()
            tryVerify(() => { inspect(); return result?.clip === "none" && result.pinVisible })
        }

        function test_floating_sidebars_keep_backdrops_and_restore_layout() {
            const view = app.activeView
            const fixture = '<style>body{margin:0;--color-bg:#eee;--color-border:#8899aa}'
                + '.gpu-view-content{position:absolute;inset:0;background:#444}'
                + '#nativeCanvasLayout{position:absolute;inset:0}.comments_sidebar--container--fixture{width:200px}'
                + '#home{position:absolute;left:0;top:0;width:200px;height:400px;background:white}'
                + '#home>div,.fb-sidebar{width:200px;height:400px}'
                + '#sidebarScroll{height:40px;overflow-y:scroll}#sidebarScroll>div{height:200px}'
                + '[data-testid=properties-panel]{position:absolute;right:0;top:0;width:200px;height:400px;background:white}'
                + '.properties_panel--panelPosition--fixture{position:absolute;inset:0;width:200px;height:400px;background:var(--color-bg)}'
                + '.properties_panel--panelContainer--fixture{border-left:1px solid #8899aa}</style>'
                + '<div id="nativeCanvasLayout"><div class="gpu-view-content"></div></div><nav id="home" class="sidebar--navDefault--fixture"><div><div class="fb-sidebar"><div id="sidebarScroll"><div></div></div></div></div></nav>'
                + '<aside data-testid="properties-panel"><div class="properties_panel--panelPosition--fixture"><div class="properties_panel--panelContainer--fixture"></div><div class="comments_sidebar--container--fixture"></div></div></aside>'
            let result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture), () => result = true)
            tryVerify(() => result === true)
            const options = {theme: "light", floatingSidebars: true, sidebarCornerRadius: 22, sidebarMargin: 8, hideFloatingScrollbars: true,
                             translucentSidebars: false, opacity: 60, sidebarBackdrop: "desktop"}
            let fixturePath = "/design/Test/File"
            function apply() {
                view.runJavaScript('window.sidebarFixturePath=' + JSON.stringify(fixturePath)
                    + ';(()=>{const location={get pathname(){return window.sidebarFixturePath}};' + FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                    + ';sidebarAppearance(' + JSON.stringify(options) + ',(id,css)=>{'
                    + 'let s=document.getElementById(id);if(!css){s?.remove();return}'
                    + 'if(!s){s=document.createElement("style");s.id=id;document.head.appendChild(s)}s.textContent=css;});})()')
            }
            function inspect() {
                view.runJavaScript('(()=>{const p=document.getElementById("home"),s=getComputedStyle(p),r=p.getBoundingClientRect();'
                    + 'const right=document.querySelector("[data-testid=properties-panel]"),child=right.firstElementChild;'
                    + 'return {x:r.x,y:r.y,width:r.width,height:r.height,radius:s.borderRadius,overflow:s.overflow,bg:s.backgroundColor,blur:s.backdropFilter,'
                    + 'rightWidth:right.getBoundingClientRect().width,childWidth:child.getBoundingClientRect().width,'
                    + 'commentsWidth:document.querySelector("[class*=comments_sidebar--container--]").getBoundingClientRect().width,'
                    + 'canvasLeft:document.querySelector(".gpu-view-content").getBoundingClientRect().left,'
                    + 'canvasWidth:document.querySelector(".gpu-view-content").getBoundingClientRect().width,'
                    + 'scrollbarWidth:getComputedStyle(document.getElementById("sidebarScroll")).scrollbarWidth,'
                    + 'scrollTop:document.getElementById("sidebarScroll").scrollTop,'
                    + 'homeChildWidth:document.querySelector(".fb-sidebar").getBoundingClientRect().width,'
                    + 'borders:[s.borderTopWidth,s.borderRightWidth,s.borderBottomWidth,s.borderLeftWidth],'
                    + 'innerBorder:getComputedStyle(document.querySelector("[class*=properties_panel--panelContainer--]")).borderLeftWidth,'
                    + 'underlayBg:document.getElementById("resketch-sidebar-underlay")?getComputedStyle(document.getElementById("resketch-sidebar-underlay")).backgroundColor:"",'
                    + 'clip:getComputedStyle(document.querySelector(".gpu-view-content")).clipPath,'
                    + 'floating:p.hasAttribute("data-resketch-floating-sidebar"),marked:p.hasAttribute("data-resketch-sidebar")}})()',
                    value => result = value)
            }
            apply()
            tryVerify(() => { inspect(); return result && result.floating })
            compare(result.scrollbarWidth, "auto", "Canvas scrollbar hiding leaves sidebar scrollbars alone")
            view.runJavaScript('document.getElementById("sidebarScroll").scrollTop=100')
            tryVerify(() => { inspect(); return result.scrollTop === 100 })
            options.hideFloatingScrollbars = false
            apply()
            tryVerify(() => { inspect(); return result.scrollbarWidth === "auto" })
            compare(result.scrollTop, 100, "Restoring scrollbars retains scroll position")
            options.hideFloatingScrollbars = true
            apply()
            tryVerify(() => { inspect(); return result.scrollbarWidth === "auto" })
            compare(result.x, 8); compare(result.y, 8)
            compare(result.width, 184); compare(result.height, 384)
            compare(result.radius, "22px"); compare(result.overflow, "hidden")
            compare(result.childWidth, result.rightWidth - 2, "Inner file panels fit inside the floating card's border")
            compare(result.commentsWidth, result.childWidth, "Comments fit the floating panel instead of retaining the original width")
            compare(result.homeChildWidth, result.width - 2, "Home's nested sidebar also fits its floating card's border")
            compare(result.borders, ["1px", "1px", "1px", "1px"], "The outline surrounds the whole sidebar")
            compare(result.innerBorder, "0px", "The old side border does not double the new outline")
            compare(result.bg, "rgba(0, 0, 0, 0)")
            verify(result.clip.startsWith("path(evenodd,"), "Transparency follows the rounded sidebar shape")
            verify(/H\s*170\b/.test(result.clip), "The mask uses the inset sidebar's bounds and 22 px corners")
            compare(result.underlayBg, "rgb(68, 68, 68)", "The surrounding space uses the opaque Figma canvas background")
            // Figma may change a native canvas ancestor after the mask was measured.
            const fullWidth = result.canvasWidth
            view.runJavaScript('document.getElementById("nativeCanvasLayout").style.left="60px"')
            tryVerify(() => {
                inspect()
                return result.canvasLeft === 60 && result.canvasWidth === fullWidth - 60
                    && new RegExp("H\\s*" + result.canvasWidth + "\\b").test(result.clip)
            })
            verify(/M\s*-30\s*8/.test(result.clip), "The rounded hole is rebased to the new canvas origin")
            view.runJavaScript('document.getElementById("nativeCanvasLayout").style.left="0px"')
            tryVerify(() => { inspect(); return result.canvasLeft === 0 && /H\s*170\b/.test(result.clip) })
            options.sidebarMargin = 16
            apply()
            tryVerify(() => { inspect(); return result.x === 16 && result.y === 16 })
            compare(result.width, 168); compare(result.height, 368)
            verify(/H\s*162\b/.test(result.clip), "The transparency mask follows the adjusted margin")
            options.sidebarMargin = 0
            apply()
            tryVerify(() => { inspect(); return result.x === 0 && result.y === 0 })
            compare(result.width, 200); compare(result.height, 400)
            options.sidebarMargin = 8
            options.sidebarCornerRadius = 0
            apply()
            tryVerify(() => { inspect(); return result.radius === "0px" })
            compare(result.width, 184, "Updating settings does not shrink the sidebar repeatedly")
            view.runJavaScript('document.getElementById("home").style.width="260px"')
            tryVerify(() => { inspect(); return result.width === 244 })
            options.sidebarBackdrop = "canvas"
            apply()
            tryVerify(() => { inspect(); return result.bg.includes("0.6") && result.clip === "none" })
            options.translucentSidebars = false
            options.opacity = 100
            apply()
            tryVerify(() => { inspect(); return result.bg === "rgb(238, 238, 238)" })
            compare(result.floating, true, "Floating layout also works with opaque sidebars")
            // The same controller follows SPA routes and restores ordinary Home layout.
            for (const path of ["/files/recent", "/desktop_new_tab", "/community", "/login"]) {
                fixturePath = path
                view.runJavaScript('window.sidebarFixturePath=' + JSON.stringify(path)
                    + ';window.__resketchSidebars.schedule()')
                tryVerify(() => { inspect(); return !result.marked })
                compare(result.width, 260)
                compare(result.x, 0); compare(result.y, 0)
                compare(result.clip, "none")
                compare(result.scrollbarWidth, "auto", "Home and other pages retain their scrollbars")
            }
            options.opacity = 60
            options.translucentSidebars = true
            options.sidebarCanvasBlur = 16
            apply()
            tryVerify(() => { inspect(); return result.marked && !result.floating })
            compare(result.bg, "rgb(238, 238, 238)", "Home has a flat sidebar with the canvas backdrop")
            compare(result.blur, "none", "Home does not blur the canvas backdrop")
            options.sidebarBackdrop = "desktop"
            apply()
            tryVerify(() => { inspect(); return result.bg === "rgba(0, 0, 0, 0)" })
            compare(result.blur, "none", "Desktop backdrop keeps its existing transparency")
            options.translucentSidebars = false
            options.floatingSidebars = false
            apply()
            tryVerify(() => { inspect(); return !result.marked })
            compare(result.width, 260); compare(result.height, 400)
            compare(result.x, 0); compare(result.y, 0)
            compare(result.radius, "0px"); compare(result.clip, "none")
            compare(result.innerBorder, "1px", "Disabling floating mode restores the original Figma border")

            // In files, the navigation rail and layer panel form one floating card.
            const joinedFixture = '<style>body{margin:0;--color-bg:#eee;--color-border:#8899aa}'
                + '.gpu-view-content{position:absolute;inset:0;background:#444}'
                + '#rail{position:absolute;left:0;top:0;width:49px;height:400px}'
                + '#positioner{position:absolute;left:49px;top:0}'
                + '#layers{width:200px;height:400px}'
                + '#right{position:absolute;right:0;top:0;width:200px;height:400px}</style>'
                + '<div class="gpu-view-content"></div><nav id="rail" data-testid="navigation-bar"></nav>'
                + '<div id="positioner"><div id="layers" data-onboarding-key="unified-design-onboarding-left-panel"></div></div>'
                + '<aside id="right" data-testid="properties-panel"></aside>'
            result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(joinedFixture), () => result = true)
            tryVerify(() => result === true)
            fixturePath = "/design/Test/File"
            options.floatingSidebars = true
            options.sidebarCornerRadius = 22
            options.opacity = 60
            options.sidebarBackdrop = "desktop"
            apply()
            tryVerify(() => {
                view.runJavaScript('(()=>{const rail=document.getElementById("rail"),layers=document.getElementById("layers");'
                    + 'return {railRight:rail.getBoundingClientRect().right,left:layers.getBoundingClientRect().left,'
                    + 'start:rail.getAttribute("data-resketch-sidebar-join"),end:layers.getAttribute("data-resketch-sidebar-join"),'
                    + 'railInner:getComputedStyle(rail).borderTopRightRadius,layerInner:getComputedStyle(layers).borderTopLeftRadius,'
                    + 'railBorder:getComputedStyle(rail).borderTopWidth,layerBorder:getComputedStyle(layers).borderBottomWidth,'
                    + 'railSeam:getComputedStyle(rail).borderRightWidth,layerSeam:getComputedStyle(layers).borderLeftWidth,'
                    + 'mask:document.getElementById("resketch-sidebar-underlay").style.clipPath}})()', value => result = value)
                return result && result.start === "start" && result.end === "end"
            })
            compare(result.railRight, result.left, "There is no gap between the two sections")
            compare(result.railInner, "0px"); compare(result.layerInner, "0px")
            compare(result.railBorder, "1px"); compare(result.layerBorder, "1px")
            compare(result.railSeam, "1px"); compare(result.layerSeam, "0px")
            compare((result.mask.match(/M/g) || []).length, 3, "One outer path and exactly two floating sidebar holes")

            // Slides uses a size container instead of Design's onboarding panel.
            const slidesFixture = '<style>body{margin:0;--color-bg:#eee;--color-border:#8899aa}'
                + '.gpu-view-content{position:absolute;inset:0;background:#444}'
                + '.left_panel_container--positionContainer--fixture{position:absolute;left:0;top:0;width:240px;height:400px}'
                + '.left_panel_container--sizeContainer--fixture{width:240px;height:400px}'
                + '.left_panel_container--panel--fixture{position:absolute;inset:0;width:241px;height:400px;background:var(--color-bg);border-right:1px solid #8899aa}'
                + '#slidesRight{position:absolute;right:0;top:0;width:240px;height:400px}</style>'
                + '<div class="gpu-view-content"></div><div class="left_panel_container--positionContainer--fixture">'
                + '<div id="slidesLeft" class="left_panel_container--sizeContainer--fixture"><div class="left_panel_container--panel--fixture">'
                + '<div id="slidePreview" style="width:100px;height:60px;background:white"></div></div></div></div>'
                + '<aside id="slidesRight" data-testid="properties-panel"></aside>'
            result = null
            view.runJavaScript('window.__resketchSidebars.dispose();delete window.__resketchSidebars;document.body.innerHTML=' + JSON.stringify(slidesFixture), () => result = true)
            tryVerify(() => result === true)
            fixturePath = "/slides/Test/Presentation"
            apply()
            tryVerify(() => {
                view.runJavaScript('(()=>{const p=document.getElementById("slidesLeft"),r=p.getBoundingClientRect(),s=getComputedStyle(p);'
                    + 'return {floating:p.hasAttribute("data-resketch-floating-sidebar"),x:r.x,y:r.y,width:r.width,height:r.height,'
                    + 'radius:s.borderRadius,bg:s.backgroundColor,borders:[s.borderTopWidth,s.borderRightWidth,s.borderBottomWidth,s.borderLeftWidth],'
                    + 'childWidth:p.firstElementChild.getBoundingClientRect().width,childBorder:getComputedStyle(p.firstElementChild).borderRightWidth,'
                    + 'previewBg:getComputedStyle(document.getElementById("slidePreview")).backgroundColor,'
                    + 'mask:document.getElementById("resketch-sidebar-underlay").style.clipPath}})()', value => result = value)
                return result && result.floating
            })
            compare(result.x, 8); compare(result.y, 8)
            compare(result.width, 224); compare(result.height, 384)
            compare(result.radius, "22px"); compare(result.bg, "rgba(0, 0, 0, 0)")
            compare(result.borders, ["1px", "1px", "1px", "1px"])
            compare(result.childWidth, 222); compare(result.childBorder, "0px")
            compare(result.previewBg, "rgb(255, 255, 255)", "The slide artwork keeps its original colors")
            compare((result.mask.match(/M/g) || []).length, 3, "Both Slides sidebars have transparency holes")
            options.floatingSidebars = false
            apply()

            app.openSettings()
            const window = findChild(app, "settingsWindow")
            const toggle = findChild(window, "floatingSidebarsToggle")
            const radius = findChild(window, "sidebarCornerRadiusControl")
            const scrollbars = findChild(window, "hideFloatingScrollbarsToggle")
            verify(scrollbars && !scrollbars.enabled && scrollbars.checked)
            const margin = findChild(window, "sidebarMarginControl")
            verify(toggle && radius && margin)
            compare(margin.enabled, false)
            compare(radius.enabled, false)
            toggle.toggle(); toggle.toggled()
            compare(appSettings.floatingSidebars, true)
            tryCompare(radius, "enabled", true)
            radius.value = 24; radius.valueModified()
            compare(appSettings.sidebarCornerRadius, 24)
            tryCompare(margin, "enabled", true)
            margin.value = 16; margin.valueModified()
            compare(appSettings.sidebarMargin, 16)
            tryCompare(scrollbars, "enabled", true)
            scrollbars.toggle(); scrollbars.toggled()
            compare(appSettings.hideFloatingScrollbars, false)
            window.close()
        }

        function test_canvas_backdrop_extends_behind_docked_panels_and_blurs() {
            const view = app.activeView
            const html = '<style>body{margin:0;--color-bg:#eee;--color-border:#8899aa}'
                + '.gpu-view-content{position:absolute;inset:0 200px;background:linear-gradient(90deg,red 100px,blue 100px)}'
                + 'nav,aside{position:absolute;top:0;width:200px;height:400px;background:var(--color-bg)}'
                + 'nav{left:0}aside{right:0}</style><div class="gpu-view-content"></div>'
                + '<nav data-onboarding-key="unified-design-onboarding-left-panel"></nav><aside data-testid="properties-panel"></aside>'
                + '<div class="comments_view--outerAnchorContainer--fixture" style="position:absolute;inset:0;pointer-events:none"></div>'
            let ready = false, result = null
            view.runJavaScript('window.__resketchSidebars?.dispose();delete window.__resketchSidebars;document.body.innerHTML='
                + JSON.stringify(html) + ';window.sidebarOriginalAppearance=window.__resketchAppearance;'
                + '(()=>{const flags={left:false,right:true};const field=key=>({getCopy:()=>flags[key],set:v=>flags[key]=v});'
                + 'const state={leftPanelCollapsed:field("left"),showPropertiesPanel:field("right")};'
                + 'class UI{getLeftRailWidth(){return 0}}'
                + 'const api={updateLayoutForMinimizeUI(){const c=document.querySelector(".gpu-view-content");'
                + 'c.style.left=(flags.left?0:200)+"px";c.style.right=(flags.right?200:0)+"px"}};'
                + 'const engine={uiState:()=>state,editorPreferences:()=>({})};'
                + 'const runtime=id=>id==="17"?{engine}:{api};'
                + 'runtime.m={17:function(){return "__getProperty_leftPanelCollapsed"},'
                + '23:function(e,x,r){r(29).api.updateLayoutForMinimizeUI()},29:function(){}};'
                + 'window.__resketchAppearance={runtime};window._fullscreen_={_getTsApisForWasm:()=>({FigmaAppUi:()=>new UI()})};})()',
                () => ready = true)
            tryVerify(() => ready)
            const options = {theme:"light",floatingSidebars:false,translucentSidebars:true,sidebarBackdrop:"canvas",
                sidebarCanvasOpacity:0,sidebarCanvasBlur:0,opacity:100,sidebarMargin:8,sidebarCornerRadius:12}
            function apply() {
                view.runJavaScript('(()=>{const location={pathname:"/design/Test/File"};'
                    + FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                    + ';sidebarAppearance(' + JSON.stringify(options) + ',(id,css)=>{'
                    + 'let s=document.getElementById(id);if(!css){s?.remove();return}'
                    + 'if(!s){s=document.createElement("style");s.id=id;document.head.appendChild(s)}s.textContent=css;});})()')
            }
            function inspect() {
                view.runJavaScript('(()=>{const p=document.querySelector("nav"),s=getComputedStyle(p),'
                    + 'c=document.querySelector(".gpu-view-content"),r=c.getBoundingClientRect();'
                    + 'return {left:r.left,right:r.right,fullWidth:innerWidth,panelWidth:p.getBoundingClientRect().width,'
                    + 'bg:s.backgroundColor,blur:s.backdropFilter,floating:p.hasAttribute("data-resketch-floating-sidebar"),'
                    + 'clip:getComputedStyle(c).clipPath,pins:getComputedStyle(document.querySelector("[class*=comments_view--]")).clipPath}})()',
                    value => result = value)
            }
            apply()
            tryVerify(() => { inspect(); return result && result.left === 0 && result.right === result.fullWidth })
            compare(result.panelWidth, 200, "Docked sidebars retain their normal dimensions")
            compare(result.floating, false)
            verify(["rgba(0, 0, 0, 0)", "color(srgb 0 0 0 / 0)"].includes(result.bg),
                   "Canvas opacity is independent of the opaque toolbar")
            compare(result.clip, "none", "The canvas stays visible under docked sidebars")
            verify(result.pins.startsWith("polygon"), "Comment pins remain clipped out of docked panels")
            view.hasLoadedFrame = true
            function pixel() {
                const point = view.mapToItem(app.contentItem, 95, 200)
                return grabImage(app.contentItem).pixel(Math.floor(point.x), Math.floor(point.y))
            }
            tryVerify(() => String(pixel()) === "#ff0000", 5000, "Actual canvas content shows through the docked sidebar")
            options.sidebarCanvasBlur = 16
            apply()
            tryVerify(() => { inspect(); return result.blur === "blur(16px)" })
            tryVerify(() => { const color = pixel(); return color.r < 0.95 && color.b > 0.05 }, 5000,
                      "Backdrop blur softens the actual canvas pixels")
            options.sidebarCanvasOpacity = 35
            apply()
            tryVerify(() => { inspect(); return result.bg.includes("0.35") })
            options.floatingSidebars = true
            apply()
            tryVerify(() => { inspect(); return result.floating && result.blur === "blur(16px)" })
            verify(result.bg.includes("0.35"), "Floating panels share canvas blur and opacity")
            options.floatingSidebars = false
            options.sidebarCanvasOpacity = 100
            apply()
            tryVerify(() => { inspect(); return result.left === 200 && result.blur === "none" })
            compare(result.bg, "rgb(238, 238, 238)")
            options.sidebarCanvasOpacity = 35
            apply()
            tryVerify(() => { inspect(); return result.left === 0 })
            options.sidebarBackdrop = "desktop"
            options.opacity = 60
            apply()
            tryVerify(() => { inspect(); return result.left === 200 && result.blur === "none" })
            compare(result.bg, "rgba(0, 0, 0, 0)")
            view.runJavaScript('window.__resketchSidebars?.dispose();delete window.__resketchSidebars;'
                + 'window.__resketchAppearance=window.sidebarOriginalAppearance;delete window._fullscreen_')

            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            const blur = findChild(settings, "sidebarCanvasBlurControl")
            const opacity = findChild(settings, "sidebarCanvasOpacityControl")
            verify(blur && opacity)
            appSettings.sidebarBackdrop = "canvas"
            appSettings.translucentSidebars = true
            tryCompare(blur, "enabled", true)
            blur.value = 24; blur.moved()
            opacity.value = 45; opacity.moved()
            compare(appSettings.sidebarCanvasBlur, 24)
            compare(appSettings.sidebarCanvasOpacity, 45)
            settings.close()
        }

        function test_sidebar_transparency_uses_native_tint_once() {
            appSettings.reduceMotion = true
            appSettings.translucentSidebars = true
            appSettings.toolbarOpacity = 85
            app.activateTab(0)
            const view = app.activeView
            const fixture = '<style>body { --color-bg:#eeeeee; margin:0 }'
                          + '.fb-sidebar { position:absolute; left:0; top:0; width:200px; height:100vh; background:white }'
                          + '.gpu-view-content { position:absolute; inset:0; background:#444 }'
                          + '.ublptt9 { --ublptt0:var(--color-bg) }'
                          + '.ublpttv,.ublptty {background:linear-gradient(90deg,rgb(from var(--ublptt0) r g b / 0) 0,rgb(from var(--ublptt0) r g b / 1) 10px)}</style>'
                          + '<div class="gpu-view-content"></div><nav class="fb-sidebar">'
                          + '<div data-testid="facetedSearchModal" style="background:var(--color-bg)">'
                          + '<div data-preferred-theme="light" style="background:var(--color-bg)">Suggestions</div>'
                          + '</div><div class="user_notifications_dropdown--dropdownContainer--fixture" style="--color-border:#8899aa;background:var(--color-bg)">'
                          + '<div id="notification-row" data-preferred-theme="light" style="background:var(--color-bg)">Notification</div></div>'
                          + '<div class="ublptt9"><div class="ublpttv"></div><div class="ublptty"></div></div></nav>'
            let initialized = false
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture), () => initialized = true)
            tryVerify(() => initialized)
            function applySidebar() {
                const options = {theme:"light", translucentSidebars:appSettings.translucentSidebars,
                                 opacity:appSettings.toolbarOpacity, sidebarBackdrop:appSettings.sidebarBackdrop}
                // Exercise the real sidebar controller against a local DOM fixture.
                view.runJavaScript('(()=>{const location={pathname:"/design/Test/File"};' + FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                    + ';sidebarAppearance(' + JSON.stringify(options) + ', (id,css)=>{'
                    + 'let s=document.getElementById(id);if(!css){s?.remove();return}'
                    + 'if(!s){s=document.createElement("style");s.id=id;document.head.appendChild(s)}'
                    + 's.textContent=css;});})()')
            }
            applySidebar()
            let result = null
            function inspect() {
                view.runJavaScript('(()=>{const p=document.querySelector(".fb-sidebar");'
                    + 'return p ? {bg:getComputedStyle(p).backgroundColor,'
                    + 'marked:p.hasAttribute("data-resketch-sidebar"),'
                    + 'search:getComputedStyle(document.querySelector("[data-testid=facetedSearchModal]")).backgroundColor,'
                    + 'suggestions:getComputedStyle(document.querySelector("[data-preferred-theme]")).backgroundColor,'
                    + 'notifications:getComputedStyle(document.querySelector("[class*=user_notifications_dropdown--dropdownContainer--]")).backgroundColor,'
                    + 'notificationRow:getComputedStyle(document.getElementById("notification-row")).backgroundColor,'
                    + 'notificationBorder:getComputedStyle(document.querySelector("[class*=user_notifications_dropdown--dropdownContainer--]")).borderTopWidth,'
                    + 'actions:[...document.querySelectorAll(".ublpttv,.ublptty")].map(e=>getComputedStyle(e).backgroundImage),'
                    + 'clip:getComputedStyle(document.querySelector(".gpu-view-content")).clipPath}:null})()',
                    value => { result = value })
            }
            tryVerify(() => { inspect(); return result && result.marked })
            compare(result.bg, "rgba(0, 0, 0, 0)")
            compare(result.search, "rgb(238, 238, 238)")
            compare(result.suggestions, result.search)
            compare(result.notifications, result.search)
            compare(result.notificationRow, result.search)
            compare(result.notificationBorder, "1px")
            for (const gradient of result.actions)
                verify(gradient.includes("rgba(0, 0, 0, 0) 10px"), "Hidden-layer action fades must stay transparent: " + gradient)
            verify(result.clip.indexOf("polygon") === 0)
            compare(view.backgroundColor.a, 0)
            const background = findChild(app.contentItem, "browserBackground")
            fuzzyCompare(background.color.a, 0.85, 0.01)

            appSettings.sidebarBackdrop = "canvas"
            applySidebar()
            tryVerify(() => { inspect(); return result && result.bg.indexOf("0.85") >= 0 })
            compare(result.clip, "none")
            compare(view.backgroundColor.a, 0)
            compare(result.search, "rgb(238, 238, 238)")
            compare(result.notifications, result.search)
            compare(result.notificationRow, result.search)
            for (const gradient of result.actions)
                verify(gradient.includes("rgba(0, 0, 0, 0) 10px"), "Canvas-backed sidebars must also avoid black action fades")

            view.runJavaScript('document.body.style.setProperty("--color-bg", "#222222")')
            applySidebar()
            tryVerify(() => { inspect(); return result && result.search === "rgb(34, 34, 34)" })
            compare(result.suggestions, result.search)
            compare(result.notifications, result.search)
            compare(result.notificationRow, result.search)

            appSettings.translucentSidebars = false
            applySidebar()
            tryVerify(() => { inspect(); return result && !result.marked })
            compare(result.bg, "rgb(255, 255, 255)")
            compare(result.clip, "none")
        }

        function test_figma_palette_themes_surfaces_and_sidebar_selection() {
            const view = app.activeView
            const palette = {window: "#f1d4cf", base: "#ffffff", text: "#6d5b58",
                             accent: "#8c4940", accentText: "#ffffff"}
            const fixture = '<style>body{--color-bg-secondary:white;--color-bgtoolbarmodeswitcher:white}'
                + '#input {background:var(--color-bg-secondary)}'
                + '#mode {background:var(--color-bgtoolbarmodeswitcher)}'
                + '#page {background:white;color:black}'
                + '[data-fpl-version=ui3] .legacy_pages_panel--pageRowActive--fixture {outline:1px solid transparent}'
                + '#active,#inactive {--color-icon:#000}'
                + '#card-title,#outside-title {color:var(--color-text)}'
                + '#card-edited {color:var(--color-text-secondary)}'
                + '#separator {border-right:1px solid var(--color-border)}'
                + '#canvas-separator {border-right:1px solid var(--color-bordertranslucent)}</style>'
                + '<div id="input"></div><fieldset id="mode"></fieldset>'
                + '<button id="page" class="legacy_pages_panel--pageRowActive--fixture">Page</button>'
                + '<button id="recents" class="sidebar_row--sidebarRowSelected--fixture">Recents</button>'
                + '<nav data-testid="navigation-bar"><button aria-expanded="true">'
                + '<div id="active">File</div></button><button aria-expanded="false">'
                + '<div id="inactive">Assets</div></button></nav>'
                + '<div class="tiles_view--container--fixture"><div data-fpl-component="primitive">'
                + '<button data-card-main-action></button><span id="card-title">File</span>'
                + '<span id="card-edited">Edited yesterday</span></div></div>'
                + '<span id="outside-title">Unrelated text</span>'
                + '<div id="separator"></div><div id="canvas-separator"></div>'
            let result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture)
                + ';document.body.setAttribute("data-fpl-version","ui3")'
                + ';const s=document.createElement("style");s.textContent='
                + JSON.stringify(FigmaTheme.paletteCss(palette)) + ';document.head.appendChild(s)',
                () => result = true)
            tryVerify(() => result === true)
            view.runJavaScript('(()=>{const s=id=>getComputedStyle(document.getElementById(id));'
                + 'return {input:s("input").backgroundColor,mode:s("mode").backgroundColor,'
                + 'page:s("page").backgroundColor,pageText:s("page").color,'
                + 'outline:s("page").outlineColor,active:s("active").backgroundColor,'
                + 'recents:s("recents").backgroundColor,recentsText:s("recents").color,'
                + 'recentsOutline:s("recents").outlineColor,recentsOutlineWidth:s("recents").outlineWidth,'
                + 'icon:s("active").getPropertyValue("--color-icon").trim(),'
                + 'inactive:s("inactive").backgroundColor,title:s("card-title").color,'
                + 'edited:s("card-edited").color,outside:s("outside-title").color,'
                + 'border:s("separator").borderRightColor,canvasBorder:s("canvas-separator").borderRightColor}})()',
                value => result = value)
            tryVerify(() => result && result.input !== undefined)
            compare(result.input, "rgb(245, 223, 219)")
            verify(result.mode !== "rgb(255, 255, 255)")
            verify(result.page !== "rgb(255, 255, 255)")
            compare(result.active, "rgb(140, 73, 64)")
            compare(result.outline, result.active)
            compare(result.recents, result.page, "Home sidebar uses the same selected surface as pages")
            compare(result.recentsText, result.pageText)
            compare(result.recentsOutline, result.outline)
            compare(result.recentsOutlineWidth, "1px")
            compare(result.icon, "#ffffff")
            compare(result.inactive, "rgba(0, 0, 0, 0)")
            verify(result.pageText !== "rgb(0, 0, 0)", "Selected page text follows the palette")
            verify(result.title !== result.outside, "Home cards have stronger title contrast")
            verify(result.edited !== result.title, "Edit timestamps retain secondary emphasis")
            compare(result.border, result.canvasBorder)
            verify(result.border !== "rgb(0, 0, 0)", "Borders follow the theme palette")
        }

        function test_figma_palette_file_controls_and_notifications_data() {
            return [{tag: "dark", window: "#20170f", text: "#baa89a", accent: "#eeb98c", accentText: "#5b3815"},
                    {tag: "light", window: "#f1d4cf", text: "#6d5b58", accent: "#8c4940", accentText: "#ffffff"}]
        }

        function test_figma_palette_file_controls_and_notifications(data) {
            const view = app.activeView
            const fixture = '<style>@layer reset,css-modules;body{color-scheme:' + data.tag + ';color:var(--color-text)}'
                + '@layer css-modules{ :where(.share){color:var(--color-text-onbrand);background:var(--color-bg-brand)}'
                + ':where(.secondary){color:var(--color-text-secondary)}'
                + ':where(.disabled){color:var(--color-text-disabled)} }'
                + '.wrapper{background:var(--color-loading-progress-wrapper)}'
                + '.bar{background:var(--color-loading-progress-bar)}'
                + '.shimmer{background:linear-gradient(to right,var(--color-loading-progress-bar) 20%,var(--color-loading-progress-accent) 50%,var(--color-loading-progress-bar) 80%)}'
                + '[class*=progressPartial]{background:var(--color-bg-design)}'
                + '[class*=progressCompleteWarning]{background:#ffcc00}'
                + '[class*=progressCompleteDanger]{background:#ff0000}'
                + '[class*=unreadDotStructuredView]{background:var(--color-bg-design)}'
                + '[class*=markAllReadButton]{color:blue}</style>'
                + '<button id="page">Page</button><button id="frame">Frame</button>'
                + '<button id="effect">Inner shadow</button><button id="zoom">18%</button>'
                + '<button id="sidebar"><span id="folder">Team folder</span></button>'
                + '<button id="notification"><span id="notification-title">Notification</span></button>'
                + '<button id="share" class="share">Share</button>'
                + '<button id="secondary" class="secondary">Secondary</button>'
                + '<button id="disabled" class="disabled" disabled>Disabled</button>'
                + '<button id="default-disabled" disabled>Disabled fallback</button>'
                + '<div id="wrapper" class="wrapper"><div id="bar" class="bar"><div id="shimmer" class="shimmer"></div></div></div>'
                + '<div id="quota" class="page_tracker_upsell--progressPartial--fixture"></div>'
                + '<div id="warning" class="page_tracker_upsell--progressPartial--fixture page_tracker_upsell--progressCompleteWarning--fixture"></div>'
                + '<div id="danger" class="page_tracker_upsell--progressPartial--fixture page_tracker_upsell--progressCompleteDanger--fixture"></div>'
                + '<div id="unread" class="block_kit_row--unreadDotStructuredView--fixture"></div>'
                + '<button id="mark-read" class="user_notifications_dropdown--markAllReadButton--fixture">Mark all as read</button>'
                + '<div id="swatch" style="background:white;color:blue"></div>'
            let result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture)
                + ';const s=document.createElement("style");s.textContent='
                + JSON.stringify(FigmaTheme.paletteCss(data)) + ';document.head.appendChild(s)', () => result = true)
            tryVerify(() => result === true)
            view.runJavaScript('(()=>{const s=id=>getComputedStyle(document.getElementById(id));'
                + 'const text=getComputedStyle(document.body).color;return {text,'
                + 'controls:["page","frame","effect","zoom","folder","notification-title"].map(id=>s(id).color),'
                + 'share:s("share").color,secondary:s("secondary").color,disabled:s("disabled").color,'
                + 'defaultDisabled:s("default-disabled").color,bar:s("bar").backgroundColor,wrapper:s("wrapper").backgroundColor,'
                + 'shimmer:s("shimmer").backgroundImage,quota:s("quota").backgroundColor,'
                + 'warning:s("warning").backgroundColor,danger:s("danger").backgroundColor,'
                + 'unread:s("unread").backgroundColor,markRead:s("mark-read").color,'
                + 'swatch:s("swatch").backgroundColor,swatchText:s("swatch").color}})()', value => result = value)
            tryVerify(() => result && result.controls !== undefined)
            for (const color of result.controls) compare(color, result.text, "File and Home labels follow the palette")
            verify(result.share !== result.text, "The fallback preserves even zero-specificity on-brand colors")
            verify(result.secondary !== result.text)
            verify(result.disabled !== result.text)
            compare(result.defaultDisabled, result.disabled)
            compare(result.bar, result.quota)
            compare(result.unread, result.quota)
            verify(result.wrapper !== result.bar, "Loading progress retains a separate track")
            verify(result.shimmer.includes(result.bar), "Shimmer uses the themed progress color")
            verify(result.markRead !== "rgb(0, 0, 255)")
            compare(result.warning, "rgb(255, 204, 0)")
            compare(result.danger, "rgb(255, 0, 0)")
            compare(result.swatch, "rgb(255, 255, 255)")
            compare(result.swatchText, "rgb(0, 0, 255)")
        }

        function test_figma_loader_background_is_transparent_without_hiding_graphics() {
            appSettings.translucentSidebars = false
            appSettings.toolbarOpacity = 50
            const view = app.activeView
            const fixture = '<style>body,#app,#resketch-sidebar-underlay {background:#eee}'
                + '.gpu-view-content {background:#444}'
                + '[class*=progressBarPageCover] {background:#ddd}'
                + '#progress {background:#0099ff}'
                + '@keyframes figma-spinner {to {transform:rotate(360deg)}}'
                + '#spinner {animation:figma-spinner 1s linear infinite}'
                + '.filebrowser-loading-page-layout,.navbar {background:#fff}'
                + '.hidden {display:none}</style>'
                + '<div id="resketch-sidebar-underlay"></div><div id="app">'
                + '<div class="gpu-view-content"></div>'
                + '<div id="loader" class="progress_bar--progressBarPageCover--fixture">'
                + '<div id="spinner">Figma</div><div id="progress"></div></div></div>'
            let result = null
            view.runJavaScript('document.body.innerHTML=' + JSON.stringify(fixture)
                + ';let s=document.createElement("style");s.textContent='
                + JSON.stringify(FigmaTheme.loadingCss(50)) + ';document.head.appendChild(s)',
                () => result = true)
            tryVerify(() => result === true)
            function inspect() {
                result = null
                view.runJavaScript('(()=>{const bg=id=>getComputedStyle(document.getElementById(id)).backgroundColor;'
                    + 'return {body:getComputedStyle(document.body).backgroundColor,app:bg("app"),'
                    + 'underlay:bg("resketch-sidebar-underlay"),cover:bg("loader"),bar:bg("progress"),'
                    + 'canvas:getComputedStyle(document.querySelector(".gpu-view-content")).visibility,'
                    + 'animation:getComputedStyle(document.getElementById("spinner")).animationName}})()',
                    value => result = value)
                tryVerify(() => result !== null)
            }
            inspect()
            for (const name of ["body", "app", "underlay", "cover"])
                compare(result[name], "rgba(0, 0, 0, 0)")
            compare(result.canvas, "hidden")
            compare(result.bar, "rgb(0, 153, 255)")
            compare(result.animation, "figma-spinner")
            compare(view.backgroundColor.a, 0)
            view.runJavaScript('document.getElementById("loader").className="filebrowser-loading-page-layout";'
                + 'document.getElementById("loader").id="filebrowser-loading-page";'
                + 'document.getElementById("filebrowser-loading-page").insertAdjacentHTML("beforeend",'
                + '\'<div class="navbar" id="loader"></div>\')')
            inspect()
            compare(result.cover, "rgba(0, 0, 0, 0)")
            compare(result.body, "rgba(0, 0, 0, 0)")
            view.runJavaScript('document.getElementById("filebrowser-loading-page").classList.add("hidden")')
            inspect()
            compare(result.body, "rgb(238, 238, 238)")
            compare(result.app, "rgb(238, 238, 238)")
            compare(result.underlay, "rgb(238, 238, 238)")
            compare(result.canvas, "visible")
        }

        function test_memory_limit_slider_commits_on_release() {
            app.openSettings()
            const window = findChild(app, "settingsWindow")
            window.selectedSection = 2
            const slider = findChild(window, "memoryLimitSlider")
            tryVerify(() => slider.visible && slider.width > 0)
            waitForRendering(window.contentItem)
            const handle = slider.handle.mapToItem(slider, slider.handle.width / 2, slider.handle.height / 2)
            mousePress(slider, handle.x, handle.y)
            compare(slider.pressed, true)
            compare(appSettings.memoryLimitMiB, 0, "Dragging must not apply intermediate limits")
            mouseMove(slider, slider.width / 2, slider.height / 2)
            mouseRelease(slider, slider.width / 2, slider.height / 2)
            verify(appSettings.memoryLimitMiB > 0)
            compare(appSettings.memoryLimitMiB, Math.round(slider.value))
            compare(appSettings.memoryLimitMiB % 512, 0)
            appSettings.memoryLimitMiB = 0
            compare(slider.value, 0)
            window.close()
        }

        function test_memory_unloading_stays_unloaded_until_selected_data() {
            return [{tag: "previews-on", previews: true}, {tag: "previews-off", previews: false}]
        }

        function test_memory_unloading_stays_unloaded_until_selected(data) {
            appSettings.reduceMotion = true
            appSettings.sleepingTabPreviews = data.previews
            appSettings.maximumLoadedTabs = 100
            const first = app.views[0]
            app.activateTab(0, false)
            first.hasLoadedFrame = true
            waitForRendering(app.contentItem)
            app.activateTab(2, false)
            const selected = app.activeView
            verify(!app.unloadTabForMemory(selected), "Do not unload a current tab")
            verify(!app.unloadTabForMemory(app.homeView), "Keep Home running")
            verify(app.unloadTabForMemory(first))
            app.toggleOverview()
            app.syncOverviewFrames()
            compare(first.visible, false, "Overview must not interrupt a pending memory unload")
            tryCompare(first, "lifecycleState", CefView.LifecycleState.Discarded)
            verify(first.memoryUnloaded)
            if (data.previews) verify(first.sleepPreview)
            app.updateTabLifecycle()
            compare(first.lifecycleState, CefView.LifecycleState.Discarded,
                    "The minimum loaded count must not undo memory unloading")
            compare(first.lifecycleState, CefView.LifecycleState.Discarded,
                    "Opening overview must not reload a memory-unloaded tab")
            compare(app.activeView, selected)
            verify(!app.memoryTabCandidates.some(tab => tab.view === first))
            app.selectOverviewView(first)
            compare(app.activeView, first)
            compare(first.lifecycleState, CefView.LifecycleState.Active)
            compare(first.memoryUnloaded, false)
        }

        function test_maximum_loaded_tabs_sleeps_oldest_without_waiting() {
            appSettings.keepHomeAwake = false
            appSettings.reduceMotion = true
            appSettings.sleepMinutes = 240
            appSettings.maximumLoadedTabs = 2
            app.homeView.lastUsedAt = Date.now() - 4000
            for (let i = 0; i < app.views.length; ++i)
                app.views[i].lastUsedAt = Date.now() - (4 - i) * 500
            const selected = app.activeView
            app.updateTabLifecycle()
            tryCompare(app.views[0], "lifecycleState", CefView.LifecycleState.Frozen)
            tryCompare(app.views[1], "lifecycleState", CefView.LifecycleState.Frozen)
            compare(selected.lifecycleState, CefView.LifecycleState.Active)
            compare(app.views[3].lifecycleState, CefView.LifecycleState.Active)
            compare(app.homeView.lifecycleState, CefView.LifecycleState.Frozen)
            appSettings.sleepingTabPreviews = true
            app.toggleOverview()
            wait(100)
            const awake = [app.homeView].concat(app.views).filter(view =>
                view.lifecycleState === CefView.LifecycleState.Active)
            compare(awake.length, 2)
            compare(findChild(app.views[0].frameContainer.parent, "sleepingTabIcon").visible, true)
            compare(app.activeView, selected)
            appSettings.maximumLoadedTabs = 1
            appSettings.changed()
            tryCompare(app.views[3], "lifecycleState", CefView.LifecycleState.Frozen)
            compare(selected.lifecycleState, CefView.LifecycleState.Active)
        }

        function test_home_stays_awake_until_toggle_is_disabled() {
            appSettings.reduceMotion = true
            appSettings.sleepingTabPreviews = true
            appSettings.maximumLoadedTabs = 1
            appSettings.minimumLoadedTabs = 1
            appSettings.sleepMinutes = 1
            const home = app.homeView
            home.lastUsedAt = Date.now() - 120000
            app.updateTabLifecycle()
            compare(home.lifecycleState, CefView.LifecycleState.Active)
            app.sleepTab(home, CefView.LifecycleState.Discarded)
            compare(home.lifecycleState, CefView.LifecycleState.Active)
            app.freezeAllTabs()
            compare(home.lifecycleState, CefView.LifecycleState.Active)
            tryCompare(app.activeView, "lifecycleState", CefView.LifecycleState.Frozen)
            app.wakeCurrentTab()

            appSettings.keepHomeAwake = false
            appSettings.changed()
            tryCompare(home, "lifecycleState", CefView.LifecycleState.Frozen)
            appSettings.keepHomeAwake = true
            appSettings.changed()
            compare(home.lifecycleState, CefView.LifecycleState.Active)
            app.toggleOverview()
            compare(home.visible, true)
            compare(findChild(home.frameContainer.parent, "sleepingTabIcon").visible, false)
        }

        function test_titlebar_double_click_does_not_start_window_move() {
            // Keep blank titlebar space on the smaller offscreen test display too.
            appSettings.reduceMotion = true
            for (const view of app.views.slice(1)) app.closeTab(app.views.indexOf(view))
            tryCompare(app.views, "length", 1)
            appSettings.reduceMotion = false
            const titlebar = findChild(app, "blankTabStripDrag")
            verify(titlebar && titlebar.width > 0)
            const oldWidth = app.width
            const oldHeight = app.height
            app.systemMoveRequests = 0
            mouseDoubleClickSequence(titlebar, titlebar.width / 2, titlebar.height / 2)
            tryCompare(app, "visibility", Window.Maximized)
            compare(app.systemMoveRequests, 0)
            wait(500) // Separate the next double-click from the previous tap sequence.
            mouseDoubleClickSequence(titlebar, titlebar.width / 2, titlebar.height / 2)
            tryCompare(app, "visibility", Window.Windowed)
            tryCompare(app, "width", oldWidth)
            tryCompare(app, "height", oldHeight)
            compare(app.systemMoveRequests, 0)
            mousePress(titlebar, 20, titlebar.height / 2)
            mouseMove(titlebar, 55, titlebar.height / 2, 20)
            mouseRelease(titlebar, 55, titlebar.height / 2)
            compare(app.systemMoveRequests, 1, "An actual drag must still move the window")
        }

        function test_sleeping_tab_keeps_blurred_snapshot_in_overview_data() {
            return [{tag: "frozen", state: CefView.LifecycleState.Frozen},
                    {tag: "unloaded", state: CefView.LifecycleState.Discarded}]
        }

        function test_sleeping_tab_keeps_blurred_snapshot_in_overview(data) {
            appSettings.sleepingTabPreviews = true
            appSettings.sleepMinutes = 1
            appSettings.minimumLoadedTabs = 1
            appSettings.reduceMotion = true
            const view = app.views[0]
            app.activateTab(0, false)
            let painted = false
            view.runJavaScript("document.body.style.background='#2a7fdb'; document.documentElement.style.background='#2a7fdb'",
                               result => painted = true)
            tryVerify(() => painted)
            view.hasLoadedFrame = true
            waitForRendering(app.contentItem)
            wait(100)
            app.activateTab(2, false)
            view.lastUsedAt = Date.now() - 120000
            app.updateTabLifecycle()
            tryCompare(view, "lifecycleState", CefView.LifecycleState.Frozen)
            verify(view.sleepPreview)
            verify(view.sleepPreview.url)
            if (data.state === CefView.LifecycleState.Discarded) {
                app.sleepTab(view, data.state)
                compare(view.hasLoadedFrame, false)
            }
            transferLoads.target = view
            transferLoads.clear()
            app.toggleOverview()
            compare(view.lifecycleState, data.state)
            compare(view.visible, false, "Overview must not wake the sleeping page")
            const snapshot = findChild(view.frameContainer, "sleepingTabPreview")
            verify(snapshot)
            tryCompare(snapshot, "status", Image.Ready)
            compare(snapshot.visible, true)
            compare(snapshot.parent, view.frameContainer)
            const sleepIcon = findChild(view.frameContainer.parent, "sleepingTabIcon")
            verify(sleepIcon)
            compare(sleepIcon.visible, true)
            // A hidden webview must still provide its last rendered content.
            const pixels = grabImage(snapshot)
            verify(pixels.pixel(20, 20).b > pixels.pixel(20, 20).r)
            compare(transferLoads.count, 0, "Opening overview must not reload sleeping tabs")
            app.selectOverviewView(view)
            compare(app.activeView, view)
            compare(view.lifecycleState, CefView.LifecycleState.Active)
            compare(view.sleepPreview, null)
            compare(snapshot.visible, false)
            compare(sleepIcon.visible, false)
        }

        function test_sleeping_previews_can_be_disabled() {
            appSettings.sleepingTabPreviews = false
            appSettings.maximumLoadedTabs = 1
            const view = app.views[0]
            view.hasLoadedFrame = true
            app.sleepTab(view, CefView.LifecycleState.Discarded)
            compare(view.lifecycleState, CefView.LifecycleState.Discarded)
            compare(view.sleepCapturePending, false)
            compare(view.sleepPreview, null)
            app.toggleOverview()
            compare(view.lifecycleState, CefView.LifecycleState.Active)
            compare(findChild(view.frameContainer, "sleepingTabPreview").visible, false)
            for (const page of [app.homeView].concat(app.views)) {
                compare(page.lifecycleState, CefView.LifecycleState.Active)
                compare(page.visible, true)
                compare(findChild(page.frameContainer.parent, "sleepingTabIcon").visible, false)
            }
            appSettings.sleepingTabPreviews = true
            appSettings.changed()
            tryCompare(view, "lifecycleState", CefView.LifecycleState.Frozen)
            appSettings.sleepingTabPreviews = false
            appSettings.changed()
            compare(view.lifecycleState, CefView.LifecycleState.Active)
            compare(view.visible, true)
            compare(findChild(view.frameContainer.parent, "sleepingTabIcon").visible, false)
            app.dismissOverview()
            tryCompare(view, "lifecycleState", CefView.LifecycleState.Frozen)
        }

        function test_pending_sleep_does_not_unload_reselected_tab() {
            appSettings.sleepingTabPreviews = true
            const view = app.views[0]
            view.hasLoadedFrame = true
            app.sleepTab(view, CefView.LifecycleState.Discarded)
            verify(view.sleepCapturePending)
            app.activateTab(0, false)
            tryCompare(view, "sleepCapturePending", false)
            compare(app.activeView, view)
            compare(view.lifecycleState, CefView.LifecycleState.Active)
            compare(view.sleepPreview, null)
        }

        function test_native_menu_integration_can_be_disabled() {
            const bar = findChild(app, "nativeMenuBar")
            verify(bar)
            compare(bar.window, null)
            appSettings.menuIntegration = true
            appSettings.changed()
            compare(bar.window, app)
            appSettings.menuIntegration = false
            appSettings.changed()
            compare(bar.window, null)
        }

        function test_overview_transparency_changes_immediately_then_fades_after_scaling() {
            appSettings.translucentSidebars = true
            appSettings.toolbarOpacity = 50
            app.activeView.hasLoadedFrame = true
            const background = findChild(app, "browserBackground")
            compare(app.overviewSidebarBackdrop, 0)
            app.toggleOverview()
            compare(app.overviewVisible, true)
            compare(app.overviewSidebarBackdrop, 1)
            tryCompare(app, "overviewProgress", 1)
            app.selectOverviewView(app.activeView)
            wait(150)
            compare(app.overviewVisible, true)
            compare(app.overviewSidebarBackdrop, 1, "Keep the backdrop until scaling finishes")
            tryCompare(app, "overviewVisible", false)
            verify(app.overviewSidebarBackdrop > 0, "Fade starts after scaling finishes")
            verify(background.color.a > 0.5, "The restored frame retains the fading backdrop")
            tryCompare(app, "overviewSidebarBackdrop", 0, 300)
            fuzzyCompare(background.color.a, 0.5, 0.01)
            // Reopening interrupts the fade and restores the backdrop immediately.
            app.toggleOverview()
            app.dismissOverview()
            wait(50)
            verify(app.overviewSidebarBackdrop > 0 && app.overviewSidebarBackdrop < 1)
            app.toggleOverview()
            compare(app.overviewSidebarBackdrop, 1)
            appSettings.reduceMotion = true
            app.dismissOverview()
            compare(app.overviewSidebarBackdrop, 0)
        }

        function test_overview_hover_tints_card_and_uses_palette_border() {
            appSettings.translucentSidebars = true
            appSettings.toolbarOpacity = 50
            const view = app.views[0]
            view.hasLoadedFrame = true
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            const card = overviewCard(view)
            const background = findChild(card, "overviewCardBackground")
            const border = findChild(card, "overviewCardBorder")
            const hover = findChild(card, "overviewCardMouse")
            mouseMove(app.contentItem, app.width - 10, app.height - 10)
            tryCompare(hover, "containsMouse", false)
            const idleBorder = String(border.border.color)
            const backgroundColor = String(background.color)
            mouseMove(card, card.width / 2, card.height / 2)
            tryCompare(hover, "containsMouse", true)
            verify(border.hoverAmount < 1, "Hover tint starts below its final opacity")
            tryVerify(() => border.hoverAmount > 0 && border.hoverAmount < 1)
            compare(background.opacity, 1)
            compare(String(background.color), backgroundColor)
            compare(app.overviewSidebarBackdrop, 1)
            compare(view.opacity, 1)
            tryCompare(border, "color", app.selectionTint)
            compare(border.border.width, 1)
            verify(String(border.border.color) !== idleBorder)
            fuzzyCompare(border.border.color.a, 0.55, 0.01)
            mouseMove(app.contentItem, app.width - 10, app.height - 10)
            tryCompare(hover, "containsMouse", false)
            tryCompare(border, "color", "#00000000")
            app.selectedTabViews = [view]
            compare(border.color, app.selectionTint)
            mouseMove(app.contentItem, app.width - 10, app.height - 10)
            tryCompare(hover, "containsMouse", false)
            tryVerify(() => String(border.border.color) === idleBorder)
        }

        function test_export_uses_originating_file_and_cancel() {
            const owner = ({})
            const request = {
                id: 77,
                view: {url: "https://www.figma.com/design/BackgroundFile/Name", title: "Source file — Figma", ownerWindow: owner},
                suggestedFileName: "Frame.png", downloadDirectory: "", accepted: false, cancelled: false,
                accept() { this.accepted = true },
                cancel() { this.cancelled = true }
            }
            app.handleDownload(request)
            compare(appSettings.requestedExportKey, "BackgroundFile")
            compare(appSettings.requestedExportOwner, owner)
            compare(request.downloadDirectory, appSettings.exportFolderResult)
            compare(request.accepted, true)
            request.view.title = "A different file — Figma"
            request.state = CefDownload.DownloadCompleted
            request.downloadFileName = "Frame.png"
            app.completeDownload(request)
            compare(appSettings.recordedOrigin, "Source file")
            verify(!app.exportOrigins[77])
            appSettings.exportFolderResult = ""
            request.accepted = false
            request.downloadDirectory = ""
            app.handleDownload(request)
            compare(request.accepted, false)
            compare(request.cancelled, true)
            compare(request.downloadDirectory, "")
            appSettings.exportFolderResult = "/tmp/resketch-exports"
        }

        function test_only_completed_exports_enter_history() {
            appSettings.recordedExport = ""
            const request = {state: CefDownload.DownloadCancelled,
                             downloadDirectory: "/tmp", downloadFileName: "Frame.png"}
            app.completeDownload(request)
            compare(appSettings.recordedExport, "")
            request.state = CefDownload.DownloadCompleted
            app.completeDownload(request)
            compare(appSettings.recordedExport, "/tmp/Frame.png")
            app.openExportHistory()
            const window = findChild(app, "exportHistoryWindow")
            verify(window && window.visible)
            window.close()
        }

        function test_export_history_origin_and_context_menu() {
            appSettings.exportHistory = [{name: "Frame.png", fileType: "PNG", path: "/tmp/Frame.png",
                                          originName: "A long Figma file name ".repeat(30),
                                          exportedAt: "2026-10-11T12:00:00Z",
                                          url: Qt.resolvedUrl("../Branding/SketchbookPNG/Folder-48.png")}]
            app.openExportHistory()
            const window = findChild(app, "exportHistoryWindow")
            window.width = 500
            const list = findChild(window, "exportsList")
            tryCompare(list, "count", 1)
            tryVerify(() => list.itemAtIndex(0)?.width > 0 && list.itemAtIndex(0)?.height > 0)
            waitForRendering(window.contentItem)
            const entry = list.itemAtIndex(0)
            const origin = findChild(entry, "exportOriginLabel")
            verify(origin.width < origin.implicitWidth, "Long origin must fit within the export row")
            compare(origin.elide, Text.ElideRight)
            mouseClick(entry, 40, 40, Qt.RightButton)
            const menu = findChild(entry, "exportItemMenu")
            tryCompare(menu, "visible", true)
            menu.itemAt(0).triggered()
            compare(appSettings.copiedText, "/tmp/Frame.png")
            menu.close()
            const search = findChild(window, "exportSearch")
            search.text = "long figma"
            tryCompare(list, "count", 1)
            search.text = "svg"
            tryCompare(list, "count", 0)
            search.text = "PNG"
            tryCompare(list, "count", 1)
            search.text = ""
            appSettings.clearExports()
            tryCompare(list, "count", 0)
            window.close()
        }

        function test_export_history_removal_animations() {
            appSettings.exportHistory = Array.from({length: 20}, (_, i) => ({
                name: "Export" + i + ".png", fileType: "PNG", path: "/tmp/Export" + i + ".png",
                originName: "Design", exportedAt: "2026-10-11T12:00:00Z",
                url: Qt.resolvedUrl("../Branding/SketchbookPNG/Folder-48.png")
            }))
            app.openExportHistory()
            const window = findChild(app, "exportHistoryWindow")
            const list = findChild(window, "exportsList")
            tryCompare(list, "count", 20)
            tryVerify(() => list.itemAtIndex(0)?.height > 0)
            waitForRendering(window.contentItem)
            const first = list.itemAtIndex(0)
            const second = list.itemAtIndex(1)
            const deleteButton = findChild(first, "deleteExportButton")
            appSettings.exportDeletionSucceeds = false
            mouseClick(deleteButton)
            compare(list.count, 20)
            compare(first.slideOffset, 0, "A failed deletion must stay in place")
            appSettings.exportDeletionSucceeds = true
            mouseClick(deleteButton)
            tryCompare(list, "count", 19)
            waitForRendering(window.contentItem)
            compare(list.itemAtIndex(0), second, "Other rows must keep their delegate")
            tryVerify(() => first.slideOffset > 0, 200)
            const secondPosition = second.mapToItem(list, 0, 0).y
            wait(180)
            fuzzyCompare(second.mapToItem(list, 0, 0).y, secondPosition, 1, "Older rows must wait for the slide to finish")
            tryCompare(window, "activeRemovals", 0)
            wait(200)
            list.positionViewAtIndex(5, ListView.Beginning)
            waitForRendering(window.contentItem)
            const visible = list.contentItem.children.filter(entry =>
                entry.objectName === "exportHistoryEntry" && entry.y + entry.height > list.contentY && entry.y < list.contentY + list.height)
            visible.sort((a, b) => a.y - b.y)
            verify(visible.length > 1 && visible.length < list.count)
            const offscreen = list.contentItem.children.filter(entry =>
                entry.objectName === "exportHistoryEntry" && (entry.y + entry.height <= list.contentY || entry.y >= list.contentY + list.height))
            const positions = visible.map(entry => entry.mapToItem(list, 0, 0).y)
            window.clearHistory()
            const placeholder = findChild(window, "exportsPlaceholder")
            compare(appSettings.exportHistory.length, 0)
            tryCompare(window, "activeRemovals", visible.length)
            compare(placeholder.visible, false)
            for (let i = 0; i < visible.length; ++i) {
                compare(visible[i].animateRemoval, true)
                compare(visible[i].removalDelay, i * 50)
            }
            for (const entry of offscreen)
                verify(!entry || !entry.animateRemoval, "Cached offscreen rows must not animate")
            waitForRendering(window.contentItem)
            for (let i = 0; i < visible.length; ++i)
                fuzzyCompare(visible[i].mapToItem(list, 0, 0).y, positions[i], 1, "Clearing must slide visible rows from their original positions")
            tryVerify(() => visible[0].slideOffset > 0, 200)
            wait(window.removalDuration + 10)
            verify(window.activeRemovals > 0, "Later staggered rows must still be exiting")
            compare(placeholder.visible, false)
            for (let i = 0; i < visible.length; ++i)
                fuzzyCompare(visible[i].mapToItem(list, 0, 0).y, positions[i], 1, "Completed exits must not shift the remaining rows")
            tryCompare(window, "activeRemovals", 0)
            compare(list.count, 0)
            tryCompare(placeholder, "visible", true)
            appSettings.reduceMotion = true
            appSettings.exportHistory = [{name: "NoMotion.png", path: "/tmp/NoMotion.png", fileType: "PNG",
                                          originName: "Design", exportedAt: "2026-10-11T12:00:00Z", url: ""}]
            tryCompare(list, "count", 1)
            waitForRendering(window.contentItem)
            window.clearHistory()
            tryCompare(list, "count", 0)
            wait(50)
            compare(list.contentItem.children.filter(entry => entry.objectName === "exportHistoryEntry").length, 0)
            appSettings.reduceMotion = false
            window.close()
        }

        function test_middle_click_does_not_close() {
            const selected = app.activeView
            const button = tabButton(0)
            const point = button.mapToItem(app.contentItem, 80, 20)
            mouseClick(app.contentItem, point.x, point.y, Qt.MiddleButton)
            wait(20)
            mouseClick(app.contentItem, point.x, point.y, Qt.MiddleButton)
            verifySelection(selected)
            wait(800)
            compare(app.views.length, 4)
            verifySelection(selected)
        }

        function test_neighbors_keep_selected_view() {
            const selected = app.activeView
            mouseClick(tabButton(0), app.tabWidth - app.tabStripHeight / 2, 20)
            wait(20)
            mouseClick(tabButton(3), app.tabWidth - app.tabStripHeight / 2, 20)
            verifySelection(selected)
            wait(800)
            compare(app.views.length, 2)
            verifySelection(selected)
        }

        function test_pending_tab_cannot_be_selected() {
            const selected = app.activeView
            mouseClick(tabButton(0), app.tabWidth - app.tabStripHeight / 2, 20)
            tryVerify(() => app.views.length === 3)
            verify(app.animatingCloseGap)
            const pending = app.views[0]
            app.closeTab(app.views.indexOf(pending))
            verify(app.pendingCloseViews.indexOf(pending) >= 0)
            mouseClick(tabButton(0), 80, 20)
            app.activateTab(0)
            verifySelection(selected)
            wait(800)
            verifySelection(selected)
        }

        function test_selected_close_plays_slide() {
            const selected = app.activeView
            mouseClick(tabButton(app.activeIndex), app.tabWidth - app.tabStripHeight / 2, 20)
            wait(20)
            verify(app.activeView !== selected)
            compare(app.outgoingView, selected)
            const replacement = app.activeView
            wait(900)
            verifySelection(replacement)
        }

        function test_selected_bar_follows_drag() {
            function findBar(item) {
                if (item.startOffset !== undefined && item.targetWidth !== undefined)
                    return item
                for (const child of item.children || []) {
                    const result = findBar(child)
                    if (result) return result
                }
                return null
            }
            const bar = findBar(app.contentItem)
            const selected = app.activeView
            const button = tabButton(app.activeIndex)
            const start = button.mapToItem(app.contentItem, 80, 20)
            function verifyBar() {
                verifySelection(selected)
                const position = button.mapToItem(bar.parent, 0, 0)
                verify(Math.abs(bar.x - position.x) < 1,
                       "Selection bar at " + bar.x + ", selected tab at " + position.x)
                compare(bar.width, button.width)
            }
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x - 30, start.y, 20)
            mouseMove(app.contentItem, start.x - 160, start.y, 20)
            wait(20)
            verify(app.draggedTabIndex >= 0)
            verifyBar()
            mouseMove(app.contentItem, start.x - 260, start.y, 20)
            verifyBar()
            mouseRelease(app.contentItem, start.x - 260, start.y)
            wait(20)
            verifyBar()
            wait(250)
            compare(app.activeIndex, 1)
            verifyBar()
        }

        function overviewCard(view, window) {
            function find(item) {
                if (item.objectName === "overviewCard" && item.previewView === view) return item
                for (const child of item.children || []) {
                    const result = find(child)
                    if (result) return result
                }
                return null
            }
            return find((window || app).contentItem)
        }

        function test_toolbar_press_feedback_keeps_action_working() {
            const button = visualChild(app.contentItem, "toolbarButton-overview")
            const icon = findChild(button, "tabBarButtonIcon")
            verify(button && icon)
            mousePress(button, button.width / 2, button.height / 2)
            tryCompare(button, "pressedFeedback", true)
            tryCompare(icon, "scale", 0.85)
            compare(button.background.color, app.selectionTint)
            compare(app.overviewVisible, false, "The action fires on release")
            mouseRelease(button, button.width / 2, button.height / 2)
            tryCompare(button, "pressedFeedback", false)
            tryCompare(icon, "scale", 1)
            compare(app.overviewVisible, true)
            verify(button.background.color !== app.selectionTint)
        }

        function test_toolbar_buttons_toggle_reorder_and_open_export_history() {
            appSettings.reduceMotion = true
            const toolbar = findChild(app, "toolbarActions")
            compare(toolbar.width, 160)
            const area = app.tabAreaWidth
            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            settings.selectedSection = settings.sections.findIndex(section => section.title === "Toolbar")
            waitForRendering(settings.contentItem)
            const toggle = visualChild(settings.contentItem, "toolbarToggle-export-history")
            verify(!toggle.checked)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            tryCompare(toolbar, "width", 200)
            compare(app.tabAreaWidth, area - 40)
            const up = visualChild(settings.contentItem, "toolbarMoveUp-export-history")
            mouseClick(up, up.width / 2, up.height / 2)
            compare(appSettings.toolbarItems[3].id, "export-history")
            waitForRendering(app.contentItem)
            const exports = visualChild(app.contentItem, "toolbarButton-export-history")
            compare(exports.x, 120)
            compare(visualChild(app.contentItem, "toolbarButton-menu").x, 160)
            mouseClick(exports, exports.width / 2, exports.height / 2)
            verify(findChild(app, "exportHistoryWindow").visible)
            const overview = visualChild(settings.contentItem, "toolbarToggle-overview")
            mouseClick(overview, overview.width / 2, overview.height / 2)
            tryCompare(toolbar, "width", 160)
            verify(!visualChild(app.contentItem, "toolbarButton-overview"))
            compare(visualChild(settings.contentItem, "toolbarToggle-overview").checked, false)
            const menu = visualChild(app.contentItem, "toolbarButton-menu")
            mouseClick(menu, menu.width / 2, menu.height / 2)
            const popup = findChild(app, "applicationPopupMenu")
            tryCompare(popup, "visible", true)
            popup.close()
        }

        function test_toolbar_drag_reorders_settings_and_hidden_menu_can_be_recovered() {
            appSettings.reduceMotion = true
            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            settings.selectedSection = 4
            waitForRendering(settings.contentItem)
            const handle = visualChild(settings.contentItem, "toolbarDragHandle-new-tab")
            const start = handle.mapToItem(settings.contentItem, handle.width / 2, handle.height / 2)
            const end = Qt.point(start.x, start.y + 96)
            mousePress(settings.contentItem, start.x, start.y)
            mouseMove(settings.contentItem, start.x, start.y + 30, 20)
            mouseMove(settings.contentItem, end.x, end.y, 20)
            tryCompare(settings, "toolbarDraggedIndex", 0)
            compare(settings.toolbarDropIndex, 2)
            mouseRelease(settings.contentItem, end.x, end.y)
            compare(appSettings.toolbarItems[2].id, "new-tab")
            compare(settings.toolbarDraggedIndex, -1)
            waitForRendering(app.contentItem)
            compare(visualChild(app.contentItem, "toolbarButton-new-tab").x, 80)
            appSettings.toolbarItems = appSettings.toolbarItems.map(item => Object.assign({}, item, {enabled: false}))
            tryCompare(findChild(app, "toolbarActions"), "width", 0)
            verify(!visualChild(app.contentItem, "toolbarButton-menu"))
            settings.close()
            tryVerify(() => !findChild(app, "settingsWindow"))
            const home = findChild(app, "homeButton")
            mouseClick(home, home.width / 2, home.height / 2, Qt.RightButton)
            const menu = findChild(app, "toolbarContextMenu")
            tryCompare(menu, "opened", true)
            const configure = menu.itemAt(0)
            mouseClick(configure, configure.width / 2, configure.height / 2)
            const reopened = findChild(app, "settingsWindow")
            verify(reopened && reopened.visible)
            compare(reopened.selectedSection, 4)
            const toggle = visualChild(reopened.contentItem, "toolbarToggle-menu")
            toggle.checked = true
            toggle.toggled()
            tryVerify(() => !!visualChild(app.contentItem, "toolbarButton-menu"))
        }

        function test_settings_notification_toggle_changes_home_source_immediately() {
            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            verify(settings && settings.visible)
            settings.selectedSection = settings.sections.findIndex(section => section.title === "Notifications")
            verify(settings.selectedSection >= 0)
            const toggle = findChild(settings, "desktopNotifications")
            verify(toggle && toggle.visible)
            toggle.checked = true
            toggle.toggled()
            compare(appSettings.desktopNotifications, true)
            compare(app.homeView.notificationSource, true)
            compare(app.homeMustStayAwake, true)
            toggle.checked = false
            toggle.toggled()
            compare(appSettings.desktopNotifications, false)
            compare(app.homeView.notificationSource, false)
        }

        function test_secondary_windows_release_and_reopen_without_losing_settings() {
            verify(!findChild(app, "settingsWindow"))
            verify(!findChild(app, "aboutWindow"))
            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            verify(settings && settings.visible)
            compare(settings.transientParent, null)
            settings.width = 620
            const editor = findChild(settings, "customCssEditor")
            editor.text = "body { color: red; }"
            const slider = findChild(settings, "overviewPreviewQuality")
            slider.value = 60
            slider.moved()
            compare(appSettings.overviewPreviewQuality, 60)
            settings.close()
            compare(appSettings.figmaCustomCss, "body { color: red; }", "Closing must flush pending CSS edits")
            tryVerify(() => !findChild(app, "settingsWindow"))
            app.openSettings()
            const reopened = findChild(app, "settingsWindow")
            compare(reopened.width, 620)
            compare(findChild(reopened, "customCssEditor").text, appSettings.figmaCustomCss)
            compare(findChild(reopened, "overviewPreviewQuality").value, 60)
            reopened.close()
            app.openSettings() // A queued release from close must not destroy a reopened window.
            wait(50)
            verify(findChild(app, "settingsWindow").visible)
            findChild(app, "settingsWindow").close()
            tryVerify(() => !findChild(app, "settingsWindow"))

            appSettings.releaseClosedWindows = false
            appSettings.changed()
            app.openAbout()
            const about = findChild(app, "aboutWindow")
            compare(about.transientParent, null)
            about.close()
            wait(50)
            compare(findChild(app, "aboutWindow"), about, "Disabling release keeps closed windows ready")
            appSettings.releaseClosedWindows = true
            appSettings.changed()
            tryVerify(() => !findChild(app, "aboutWindow"))
            app.openExportHistory()
            const history = findChild(app, "exportHistoryWindow")
            verify(history && history.visible)
            compare(history.transientParent, null)
            history.close()
            tryVerify(() => !findChild(app, "exportHistoryWindow"))
        }

        function test_gpu_warning_is_shown_only_when_acceleration_is_missing() {
            const warning = findChild(app, "gpuAccelerationWarning")
            compare(warning.visible, false)
            appSettings.gpuAccelerationWarning = "GPU acceleration could not be detected."
            tryCompare(warning, "visible", true)
            compare(warning.text, appSettings.gpuAccelerationWarning)
            compare(warning.showCloseButton, true)
            appSettings.gpuAccelerationWarning = ""
            tryCompare(warning, "visible", false)
        }

        function test_overview_close_also_animates_visible_strip_tabs_data() {
            return [{tag: "unselected", selected: false, offscreen: false, reduceMotion: false},
                    {tag: "selected", selected: true, offscreen: false, reduceMotion: false},
                    {tag: "offscreen", selected: false, offscreen: true, reduceMotion: false},
                    {tag: "reduced-motion", selected: false, offscreen: false, reduceMotion: true}]
        }

        function test_overview_close_also_animates_visible_strip_tabs(data) {
            appSettings.reduceMotion = true
            if (data.offscreen) {
                appSettings.maximumLoadedTabs = 100
                for (let i = 0; i < 8; ++i) {
                    app.openTab("about:blank", null, true)
                    app.views[app.views.length - 1].stop()
                }
                const viewport = findChild(app, "tabsViewport")
                viewport.contentX = 0
                tryVerify(() => tabButton(app.views.length - 1).mapToItem(viewport, 0, 0).x >= viewport.width)
            }
            app.toggleOverview()
            appSettings.reduceMotion = data.reduceMotion
            const selected = app.activeView
            const index = data.offscreen ? app.views.length - 1 : data.selected ? app.activeIndex : 0
            const view = app.views[index]
            const tab = tabButton(index)
            const count = app.views.length
            app.closeTab(index)
            if (!data.reduceMotion) {
                if (data.selected) {
                    const bar = findChild(app, "selectionBar")
                    verify(Math.abs(bar.startOffset) > 0 || Math.abs(bar.endOffset) > 0,
                           "Closing the selected card glides the selection bar to its replacement")
                }
                compare(view.overviewClosingCard, true)
                compare(tab.closing, !data.offscreen)
                app.finishOverviewClose(view)
                verify(app.views.includes(view), "Removal waits for both closing animations")
                if (!data.offscreen)
                    tryVerify(() => tab.closeDrop > 0)
            }
            tryVerify(() => !app.views.includes(view))
            compare(app.views.length, count - 1)
            compare(app.overviewClosingCardCount, 0)
            compare(app.overviewVisible, true)
            if (!data.selected) compare(app.activeView, selected)
            verify(!app.pendingCloseViews.includes(view))
            verify(!app.closingViews.includes(view))
            verify(!app.readyCloseViews.includes(view))
        }

        function test_closing_tabs_smoothly_fills_strip_gap_data() {
            return [{tag: "tab-strip", overview: false, reduceMotion: false},
                    {tag: "overview", overview: true, reduceMotion: false},
                    {tag: "reduced-motion", overview: true, reduceMotion: true}]
        }

        function test_closing_tabs_smoothly_fills_strip_gap(data) {
            appSettings.reduceMotion = true
            if (data.overview) app.toggleOverview()
            appSettings.reduceMotion = data.reduceMotion
            const selected = app.activeView
            const left = tabButton(0)
            const right = tabButton(2)
            const target = app.views[1]
            const viewport = findChild(app, "tabsViewport")
            const leftX = left.mapToItem(viewport, 0, 0).x
            app.closeTab(1)
            tryVerify(() => !app.views.includes(target))
            compare(tabButton(1), right, "Keep the surviving tab delegate")
            if (!data.reduceMotion) {
                verify(right.fillingClose)
                verify(right.fillOffset > 0 && right.fillOffset <= app.tabWidth)
                const bar = findChild(app, "selectionBar")
                fuzzyCompare(bar.x, right.mapToItem(bar.parent, 0, 0).x, 1,
                             "Selection bar follows the selected tab while the gap closes")
                const offset = right.fillOffset
                tryVerify(() => right.fillOffset < offset)
                tryCompare(right, "fillingClose", false)
            }
            compare(right.fillOffset, 0)
            fuzzyCompare(left.mapToItem(viewport, 0, 0).x, leftX, 1,
                         "Tabs to the left stay in place")
            compare(app.activeView, selected)
        }

        function test_overview_multiple_closes_keep_both_strip_animations() {
            appSettings.reduceMotion = true
            app.toggleOverview()
            appSettings.reduceMotion = false
            const selected = app.activeView
            const targets = app.views.slice(0, 2)
            const tabs = targets.map(view => tabButton(app.views.indexOf(view)))
            const survivor = tabButton(2)
            let largestOffset = 0
            function observeOffset() { largestOffset = Math.max(largestOffset, survivor.fillOffset) }
            survivor.fillOffsetChanged.connect(observeOffset)
            for (const view of targets) app.closeTab(app.views.indexOf(view))
            for (const tab of tabs) compare(tab.closing, true)
            tryVerify(() => tabs.every(tab => tab.closeDrop > 0))
            tryVerify(() => targets.every(view => !app.views.includes(view)))
            survivor.fillOffsetChanged.disconnect(observeOffset)
            verify(largestOffset >= app.tabWidth * 2 - 1,
                   "Rapid closes extend the existing fill animation without jumping")
            tryCompare(survivor, "fillingClose", false)
            compare(app.views.length, 2)
            compare(app.overviewClosingCardCount, 0)
            compare(app.activeView, selected)
        }

        function test_overview_selection_smoothly_reveals_strip_tab_data() {
            return [{tag: "right", left: false, reduceMotion: false},
                    {tag: "left", left: true, reduceMotion: false},
                    {tag: "reduced-motion", left: false, reduceMotion: true}]
        }

        function test_overview_selection_smoothly_reveals_strip_tab(data) {
            appSettings.reduceMotion = true
            appSettings.maximumLoadedTabs = 100
            for (let i = 0; i < 8; ++i) {
                app.openTab("about:blank", null, true)
                app.views[app.views.length - 1].stop()
            }
            const viewport = findChild(app, "tabsViewport")
            const lastIndex = app.views.length - 1
            tryVerify(() => tabButton(lastIndex).x > viewport.width)
            app.activateTab(data.left ? lastIndex : 0)
            app.toggleOverview()
            appSettings.reduceMotion = data.reduceMotion
            const targetIndex = data.left ? 0 : lastIndex
            const target = app.views[targetIndex]
            const start = viewport.contentX
            app.selectOverviewView(target)
            compare(app.activeView, target)
            const bar = findChild(app, "selectionBar")
            if (!data.reduceMotion) {
                compare(app.overviewClosing, true)
                verify(viewport.wheelTargetX !== start)
                compare(viewport.contentX, start, "The strip must start scrolling without jumping")
                verify(Math.abs(bar.startOffset) > 0 || Math.abs(bar.endOffset) > 0)
                wait(30)
                verify(viewport.contentX !== start)
                verify(Math.abs(viewport.contentX - start) < Math.abs(viewport.wheelTargetX - start),
                       "Scroll moves through intermediate positions during the card animation")
            }
            tryCompare(app, "overviewVisible", false)
            tryVerify(() => Math.abs(viewport.contentX - viewport.wheelTargetX) < 1)
            const tab = tabButton(targetIndex)
            const position = tab.mapToItem(viewport, 0, 0).x
            verify(position >= -1 && position + tab.width <= viewport.width + 1)
            tryVerify(() => Math.abs(bar.startOffset) < 1 && Math.abs(bar.endOffset) < 1)
            fuzzyCompare(bar.x, tab.mapToItem(bar.parent, 0, 0).x, 1)
        }

        function test_overview_opens_with_selected_card_visible_data() {
            return [{tag: "three-columns", width: 1200, reduceMotion: false},
                    {tag: "four-columns", width: 1500, reduceMotion: false},
                    {tag: "reduced-motion", width: 1200, reduceMotion: true}]
        }

        function test_overview_opens_with_selected_card_visible(data) {
            const originalWidth = app.width
            try {
                app.width = data.width
                const flickable = findChild(app, "overviewFlickable")
                tryCompare(flickable, "width", data.width)
                appSettings.maximumLoadedTabs = 100
                appSettings.reduceMotion = true
                for (let i = 0; i < 8; ++i) {
                    app.openTab("about:blank", null, true)
                    app.views[app.views.length - 1].stop()
                }
                const selected = app.views[app.views.length - 1]
                app.activateTab(app.views.indexOf(selected))
                appSettings.reduceMotion = data.reduceMotion
                app.toggleOverview()
                const card = overviewCard(selected)
                verify(flickable.contentY > 0, "Opening must scroll to the selected card")
                if (!data.reduceMotion)
                    fuzzyCompare(card.y - flickable.contentY, 0, 1,
                                 "Scaling starts at the viewport despite its scroll offset")
                tryCompare(app, "overviewProgress", 1)
                verify(card.y >= flickable.contentY)
                verify(card.y + card.height <= flickable.contentY + flickable.height,
                       "Card bottom " + (card.y + card.height) + ", viewport bottom "
                       + (flickable.contentY + flickable.height))
                compare(app.activeView, selected)
                app.dismissOverview()
                appSettings.reduceMotion = true
                app.activateView(app.homeView, -1)
                app.toggleOverview()
                compare(flickable.contentY, 0, "Opening Home returns to the first row")
            } finally {
                app.dismissOverview()
                app.width = originalWidth
            }
        }

        function test_overview_releases_only_offscreen_effects() {
            appSettings.reduceMotion = true
            appSettings.maximumLoadedTabs = 100
            for (let i = 0; i < 8; ++i) {
                app.openTab("about:blank", null, true)
                app.views[app.views.length - 1].stop()
            }
            const first = overviewCard(app.homeView)
            compare(first.layer.enabled, false)
            compare(findChild(first, "overviewCardMask").layer.enabled, false,
                    "Closed overview must not retain mask textures")
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            const last = overviewCard(app.views[app.views.length - 1])
            const flickable = findChild(app, "overviewFlickable")
            compare(first.layer.enabled, true)
            compare(last.layer.enabled, false)
            const owner = last.previewView.ownerWindow
            const frame = last.previewView.frameContainer
            flickable.contentY = flickable.contentHeight - flickable.height
            tryCompare(last.layer, "enabled", true)
            compare(first.layer.enabled, false)
            compare(last.previewView.ownerWindow, owner)
            compare(last.previewView.frameContainer, frame, "Culling effects must keep the live frame")
            appSettings.cullOffscreenOverviewEffects = false
            appSettings.changed()
            compare(first.layer.enabled, true, "Disabling culling retains offscreen effects")
            appSettings.cullOffscreenOverviewEffects = true
            appSettings.changed()
            last.dragOffsetY = -flickable.contentHeight
            compare(last.layer.enabled, false)
            last.dragOffsetY = flickable.contentY - last.y + 20
            compare(last.layer.enabled, true, "Dragging into the viewport must restore clipping")
            last.dragOffsetY = 0
            app.dismissOverview()
            compare(last.layer.enabled, false)
        }

        function test_overview_quality_changes_textures_without_recreating_frames() {
            appSettings.reduceMotion = true
            const view = app.activeView
            const frame = view.frameContainer
            const card = overviewCard(view)
            appSettings.overviewPreviewQuality = 50
            appSettings.changed()
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            const halfSize = card.layer.textureSize
            const halfWidth = halfSize.width
            const halfHeight = halfSize.height
            verify(halfSize.width > 0 && halfSize.height > 0)
            compare(findChild(card, "overviewCardMask").layer.textureSize, Qt.size(0, 0),
                    "Rounded clipping must retain display resolution at every preview quality")
            appSettings.overviewPreviewQuality = 25
            appSettings.changed()
            fuzzyCompare(card.layer.textureSize.width, halfWidth / 2, 1)
            fuzzyCompare(card.layer.textureSize.height, halfHeight / 2, 1)
            compare(view.frameContainer, frame)
            compare(frame.parent, card)
            appSettings.overviewPreviewQuality = 100
            appSettings.changed()
            compare(card.layer.textureSize, Qt.size(0, 0), "Full quality uses the native display resolution")
            appSettings.overviewPreviewQuality = 25
            app.dismissOverview()
            compare(card.layer.enabled, false)
            compare(frame.parent, app.browserContent)
            compare(frame.width, app.browserWidth)
            compare(view.frameContainer, frame)
        }

        function test_overview_web_content_is_clipped_at_rounded_corners() {
            if (!fixture.gpuMasking) skip("Rounded masks require a GPU renderer")
            appSettings.reduceMotion = true
            const view = app.activeView
            let ready = false
            view.runJavaScript("document.documentElement.style.background='#ff00ff';"
                + "document.body.style.cssText='margin:0;background:#ff00ff;height:100vh';", () => ready = true)
            tryVerify(() => ready)
            view.hasLoadedFrame = true
            app.toggleOverview()
            const card = overviewCard(view)
            function checkCorners() {
                waitForRendering(app.contentItem)
                const image = grabImage(app.contentItem)
                const point = card.mapToItem(app.contentItem, 0, 0)
                const left = Math.floor(point.x), top = Math.floor(point.y)
                const right = Math.ceil(point.x + card.width) - 1
                const bottom = Math.ceil(point.y + card.height) - 1
                compare(image.pixel(left, top), image.pixel(5, app.height - 5))
                compare(image.pixel(right, top), image.pixel(5, app.height - 5))
                compare(image.pixel(left, bottom), image.pixel(5, app.height - 5))
                compare(image.pixel(right, bottom), image.pixel(5, app.height - 5))
                compare(image.pixel(Math.floor((left + right) / 2), bottom - 20), "#ff00ff",
                        "The check must contain a live webview")
                compare(view.frameContainer.parent, card)
            }
            for (const quality of [25, 50, 100]) {
                appSettings.overviewPreviewQuality = quality
                wait(150)
                checkCorners()
            }
            card.dragOriginX = card.viewportX
            card.dragOriginY = card.viewportY
            app.overviewDraggedView = view
            card.dragOffsetX = 60
            card.dragOffsetY = 50
            wait(150)
            checkCorners()
            app.cancelItemDrag()
            app.overviewDraggedView = null
            card.dragOffsetX = 0
            card.dragOffsetY = 0
            app.overviewProgress = 0.5
            wait(150)
            checkCorners()
        }

        function test_overview_search_only_includes_home_when_its_name_matches() {
            app.activateHome()
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            const search = findChild(app, "overviewSearch")
            const home = overviewCard(app.homeView)
            compare(home.visible, true)
            compare(app.overviewFilteredCount(), app.views.length + 1)
            search.text = "about:blank"
            compare(home.visible, false)
            compare(app.overviewFilteredCount(), app.views.length)
            compare(overviewCard(app.views[0]).gridSlot, 0, "No empty space for hidden Home")
            search.text = " HoMe "
            compare(home.visible, true)
            search.text = "ho"
            compare(home.visible, true)
            search.text = "no matching tab"
            compare(home.visible, false)
            compare(app.overviewFilteredCount(), 0)
            search.text = ""
            compare(home.visible, true)
            compare(app.overviewFilteredCount(), app.views.length + 1)
            compare(overviewCard(app.views[0]).gridSlot, 1)
        }

        function test_overview_arrow_navigation_and_enter_data() {
            return [{tag: "three-columns", width: 1280, columns: 3},
                    {tag: "four-columns", width: 1600, columns: 4},
                    {tag: "animated", width: 1280, columns: 3, motion: true}]
        }

        function test_overview_arrow_navigation_and_enter(data) {
            appSettings.reduceMotion = !data.motion
            app.width = data.width
            app.height = 400
            waitForRendering(app.contentItem)
            app.activateHome()
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            tryCompare(app, "overviewAnimationRunning", false)
            app.requestActivate()
            tryVerify(() => app.active)
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            compare(app.overviewNavigationTarget, app.homeView)
            compare(findChild(overviewCard(app.homeView), "overviewCardBorder").color.a, 0,
                    "The focused card starts with a border and no selection tint")
            verify(findChild(overviewCard(app.homeView), "overviewCardFocusRing").visible)
            keyClick(Qt.Key_Down)
            compare(app.overviewNavigationTarget, app.views[data.columns - 1])
            const flick = findChild(app, "overviewFlickable")
            const card = overviewCard(app.overviewNavigationTarget)
            tryVerify(() => Math.abs(flick.contentY - flick.wheelTargetY) < 0.5)
            verify(flick.contentY > 0, "Navigating below the viewport scrolls the overview")
            const point = card.mapToItem(flick, 0, 0)
            verify(point.y + card.height <= flick.height - app.overviewMargin + 1,
                   "Keyboard navigation scrolls the highlighted card into view")
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            compare(app.overviewNavigationTarget, app.views[data.columns - 2],
                    "Left from the row's first card selects the previous row's last card")
            verify(app.selectedTabViews.includes(app.views[data.columns - 1]))
            verify(app.selectedTabViews.includes(app.views[data.columns - 2]),
                   "Shift selection continues across row boundaries")
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, app.views[data.columns - 1],
                    "Right from the row's last card selects the next row's first card")
            compare(app.selectedTabViews, [app.views[data.columns - 1]],
                    "Plain arrows replace selection when wrapping between rows")
            keyClick(Qt.Key_Up)
            compare(app.overviewNavigationTarget, app.homeView)
            compare(findChild(overviewCard(app.homeView), "overviewCardBorder").color, app.selectionTint,
                    "Returning with an arrow explicitly selects and tints the focused card")
            compare(app.selectedTabViews, [app.homeView])
            keyClick(Qt.Key_Left)
            compare(app.overviewNavigationTarget, app.homeView, "Navigation stops at grid edges")
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, app.views[0])
            compare(findChild(overviewCard(app.views[0]), "overviewCardBorder").color, app.selectionTint)
            compare(findChild(overviewCard(app.views[0]), "overviewCardBorder").border.width, 1)
            verify(!findChild(overviewCard(app.views[0]), "overviewCardFocusRing").visible)
            verify(findChild(overviewCard(app.homeView), "overviewCardFocusRing").visible,
                   "The focused Home tab keeps its blue border while keyboard navigation moves")
            compare(findChild(overviewCard(app.homeView), "overviewCardBorder").color, Qt.rgba(0, 0, 0, 0))
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, app.views[1])
            keyClick(Qt.Key_Left)
            compare(app.overviewNavigationTarget, app.views[0])
            compare(app.activeView, app.homeView, "Arrow navigation does not switch the live tab")
            compare(app.selectedTabViews, [app.views[0]])
            const ordered = app.overviewNavigationCards()
            for (let index = 2; index < ordered.length; ++index) {
                keyClick(Qt.Key_Right)
                compare(app.overviewNavigationTarget, ordered[index].target)
            }
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, ordered[ordered.length - 1].target,
                    "Right stops at the last card, including an incomplete final row")
            for (let index = ordered.length - 2; index >= 0; --index) {
                keyClick(Qt.Key_Left)
                compare(app.overviewNavigationTarget, ordered[index].target)
            }
            keyClick(Qt.Key_Left)
            compare(app.overviewNavigationTarget, app.homeView, "Left stops at the very first card")
            keyClick(Qt.Key_Right)
            keyClick(Qt.Key_Return)
            tryCompare(app, "overviewVisible", false)
            compare(app.activeView, app.views[0])
            compare(app.overviewNavigationTarget, null)
        }

        function test_overview_shift_arrows_extend_and_shrink_selection() {
            appSettings.reduceMotion = true
            app.width = 1600
            app.activateTab(0)
            app.toggleOverview()
            app.requestActivate()
            tryVerify(() => app.active)
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            keyClick(Qt.Key_Right, Qt.ShiftModifier)
            compare(app.overviewNavigationTarget, app.views[1])
            compare(app.selectedTabViews, app.views.slice(0, 2))
            compare(findChild(overviewCard(app.views[1]), "overviewCardBorder").border.width, 1)
            verify(!findChild(overviewCard(app.views[1]), "overviewCardFocusRing").visible)
            verify(findChild(overviewCard(app.views[0]), "overviewCardFocusRing").visible,
                   "Only the focused tab has a blue border, even when multiple tabs are selected")
            keyClick(Qt.Key_Right, Qt.ShiftModifier)
            compare(app.selectedTabViews, app.views.slice(0, 3))
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            compare(app.selectedTabViews, app.views.slice(0, 2), "Reversing removes the card beyond the range")
            compare(findChild(overviewCard(app.views[2]), "overviewCardBorder").color.a, 0)
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            compare(app.selectedTabViews, [app.views[0]], "Returning to the anchor leaves only that card selected")
            keyClick(Qt.Key_Right, Qt.ShiftModifier)
            compare(app.selectedTabViews, app.views.slice(0, 2), "The range can be extended again")
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, app.views[2])
            compare(app.selectedTabViews, [app.views[2]], "Plain arrows replace the previous selection")
            compare(findChild(overviewCard(app.views[2]), "overviewCardBorder").border.width, 1)
            compare(findChild(overviewCard(app.views[2]), "overviewCardBorder").color, app.selectionTint)
            compare(app.activeView, app.views[0])
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            compare(app.selectedTabViews, app.views.slice(1, 3), "A new Shift range starts at the plain-arrow destination")
            keyClick(Qt.Key_Right, Qt.ShiftModifier)
            compare(app.selectedTabViews, [app.views[2]], "Reversing a leftward range also shrinks it")
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            compare(findChild(overviewCard(app.views[2]), "overviewCardBorder").color.a, 0,
                    "Escape clears the tint without moving the keyboard cursor")
            keyClick(Qt.Key_Left)
            compare(app.selectedTabViews, [app.views[1]])
            mouseClick(findChild(app, "overviewSearch"), 80, 15)
            compare(app.selectedTabViews, [])
            compare(findChild(overviewCard(app.views[1]), "overviewCardBorder").color.a, 0,
                    "A mouse click clears the keyboard selection tint")
            app.overviewNavigationTarget = app.views[0]
            compare(findChild(overviewCard(app.views[0]), "overviewCardBorder").color.a, 0)
            const id = app.createTabGroup(app.views[0], "Focused group")
            app.updateTabGroup(id, {overviewCollapsed: true}, true)
            app.overviewNavigationTarget = id
            const groupHighlight = findChild(app.overviewGroupContainer(id), "overviewGroupNavigationHighlight")
            compare(groupHighlight.color.a, 0, "A collapsed focused group also has no selection tint")
            compare(groupHighlight.border.width, 2)
            app.selectFileTabs(app.views[0], Qt.ShiftModifier, true)
            compare(groupHighlight.color, app.selectionTint, "Explicit selection still tints the focused group")
        }

        function test_overview_navigation_survives_tab_focus_changes() {
            appSettings.reduceMotion = true
            app.activateHome()
            app.toggleOverview()
            app.requestActivate()
            tryVerify(() => app.active)
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget === app.views[0], true)
            keyClick(Qt.Key_Tab)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget === app.views[1], true, "Arrows work after Tab changes focus")
            keyClick(Qt.Key_Tab, Qt.ShiftModifier)
            keyClick(Qt.Key_Left, Qt.ShiftModifier)
            compare(app.overviewNavigationTarget === app.views[0], true, "Shift arrows work after backward focus traversal")
            compare(app.selectedTabViews, app.views.slice(0, 2))
            const options = findChild(overviewCard(app.views[0]), "overviewTabOptions")
            options.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget === app.views[1], true, "Focused card controls do not capture overview arrows")
            const menu = findChild(overviewCard(app.views[0]), "overviewTabMenu")
            menu.popup(options, 0, options.height)
            tryCompare(menu, "visible", true)
            const target = app.overviewNavigationTarget
            keyClick(Qt.Key_Down)
            compare(app.overviewNavigationTarget === target, true, "An open context menu keeps its own arrow navigation")
            menu.close()
            tryCompare(menu, "visible", false)
            keyClick(Qt.Key_Tab)
            keyClick(Qt.Key_Return)
            compare(app.overviewVisible, false, "Enter still opens the card after focus traversal")
            compare(app.activeView, app.views[1])
        }

        function test_selection_delete_shortcuts_data() {
            return [{tag: "tabs", group: false}, {tag: "group", group: true},
                    {tag: "group-and-tab", group: true, mixed: true},
                    {tag: "close-group", group: true, closeGroup: true},
                    {tag: "group-in-strip", group: true, strip: true}]
        }

        function test_selection_delete_shortcuts(data) {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2]
            let id = ""
            if (data.group) {
                id = app.createTabGroup(first, "Delete test")
                app.assignTabGroup(second, id)
                app.updateTabGroup(id, {overviewCollapsed: true}, true)
            }
            app.activateHome()
            app.requestActivate()
            tryVerify(() => app.active)
            if (data.strip) {
                const header = app.tabGroupHeaderItem(id)
                mouseClick(header, 50, header.height / 2, Qt.LeftButton, Qt.ShiftModifier)
                compare(app.selectedGroupIds, [id])
                compare(app.groupFor(first).collapsed, false, "Selecting a group does not collapse it")
            } else {
                app.toggleOverview()
                findChild(app, "overviewSearch").forceActiveFocus()
                waitForRendering(app.contentItem)
                keyClick(Qt.Key_Right)
                if (!data.group || data.mixed) keyClick(Qt.Key_Right, Qt.ShiftModifier)
                compare(app.selectedGroupIds, data.group ? [id] : [])
            }
            keyClick(Qt.Key_Delete, data.closeGroup ? Qt.AltModifier : Qt.NoModifier)
            const expected = data.closeGroup || !data.group ? 2 : data.mixed ? 3 : 4
            tryCompare({get count() { return app.views.length }}, "count", expected)
            compare(app.tabGroups.length, 0)
            compare(app.views.includes(first), data.group && !data.closeGroup)
            compare(app.views.includes(second), data.group && !data.closeGroup)
            if (data.mixed) verify(!app.views.includes(third))
            compare(app.selectedTabViews, [])
            compare(app.selectedGroupIds, [])
            verify(app.homeView, "Home is never closed by selection actions")
        }

        function test_ctrl_g_selection_actions_data() {
            return [{tag: "create", action: "create"}, {tag: "join", action: "join"},
                    {tag: "ungroup", action: "ungroup"}]
        }

        function test_ctrl_g_selection_actions(data) {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2]
            let id = ""
            if (data.action !== "create") {
                id = app.createTabGroup(first, "Target")
                app.assignTabGroup(second, id)
                app.updateTabGroup(id, {overviewCollapsed: true}, true)
            }
            app.activateHome()
            app.toggleOverview()
            app.requestActivate()
            tryVerify(() => app.active)
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            keyClick(Qt.Key_Right)
            if (data.action !== "ungroup") keyClick(Qt.Key_Right, Qt.ShiftModifier)
            keyClick(Qt.Key_G, Qt.ControlModifier)
            if (data.action === "create") {
                const dialog = findChild(app, "tabGroupNameDialog")
                tryCompare(dialog, "visible", true)
                compare(app.tabGroups.length, 0, "New groups still require a name before creation")
                const name = findChild(app, "tabGroupNameEditor")
                name.forceActiveFocus()
                name.selectAll()
                keyClick(Qt.Key_Delete)
                compare(app.views.length, 4, "Delete edits the name field while the naming popup is open")
                name.text = "Keyboard group"
                dialog.accept()
                compare(app.tabGroups.length, 1)
                compare(first.tabGroupId, second.tabGroupId)
                verify(first.tabGroupId !== "")
                compare(third.tabGroupId, "")
            } else if (data.action === "join") {
                compare(app.tabGroups.length, 1)
                compare(first.tabGroupId, id)
                compare(second.tabGroupId, id)
                compare(third.tabGroupId, id)
            } else {
                compare(app.tabGroups.length, 0)
                compare(first.tabGroupId, "")
                compare(second.tabGroupId, "")
            }
            compare(app.views.length, 4)
        }

        function test_shortcut_settings_edit_reset_and_live_binding() {
            appSettings.reduceMotion = true
            app.openSettings()
            const settings = findChild(app, "settingsWindow")
            settings.selectedSection = settings.sections.findIndex(section => section.title === "Shortcuts")
            verify(settings.selectedSection >= 0)
            waitForRendering(settings.contentItem)
            const editor = visualChild(settings.contentItem, "shortcutEditor-new-tab")
            verify(editor)
            settings.requestActivate()
            tryVerify(() => settings.active)
            editor.startCapturing()
            keyClick(Qt.Key_Y, Qt.ControlModifier)
            tryCompare({get sequence() { return appSettings.shortcutOverrides["new-tab"] }}, "sequence", "Ctrl+Y")
            compare(String(editor.keySequence), "Ctrl+Y")
            settings.setShortcut("new-tab", "Ctrl+W")
            verify(!!settings.shortcutError, "Duplicate app shortcuts are rejected")
            compare(appSettings.shortcutOverrides["new-tab"], "Ctrl+Y")
            app.requestActivate()
            tryVerify(() => app.active)
            app.activateHome()
            keyClick(Qt.Key_T, Qt.ControlModifier)
            compare(app.views.length, 4, "The previous shortcut no longer creates a tab")
            keyClick(Qt.Key_Y, Qt.ControlModifier)
            compare(app.views.length, 5, "The edited shortcut applies immediately")
            const clear = editor.children.find(child => child.icon && child.icon.name.startsWith("edit-clear"))
            verify(clear)
            clear.clicked()
            compare(appSettings.shortcutOverrides["new-tab"], "")
            keyClick(Qt.Key_Y, Qt.ControlModifier)
            compare(app.views.length, 5, "Clearing a shortcut disables it")
            const reset = visualChild(settings.contentItem, "resetShortcut-new-tab")
            verify(reset.enabled)
            reset.clicked()
            verify(!Object.prototype.hasOwnProperty.call(appSettings.shortcutOverrides, "new-tab"))
            compare(String(editor.keySequence), "Ctrl+T")
            keyClick(Qt.Key_T, Qt.ControlModifier)
            compare(app.views.length, 6, "The individual reset restores the default binding")
            settings.setShortcut("overview-right", "L")
            settings.setShortcut("overview-left", "H")
            app.activateHome()
            app.toggleOverview()
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, app.homeView, "Remapped arrows are not handled by a hard-coded fallback")
            keyClick(Qt.Key_L)
            compare(app.overviewNavigationTarget === app.views[0], true)
            keyClick(Qt.Key_H)
            compare(app.overviewNavigationTarget, app.homeView)
            visualChild(settings.contentItem, "resetAllShortcuts").clicked()
            compare(Object.keys(appSettings.shortcutOverrides).length, 0)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget === app.views[0], true)
        }

        function test_overview_accepts_early_keyboard_selection() {
            const target = app.views[0]
            app.activateHome()
            app.requestActivate()
            tryVerify(() => app.active)
            app.toggleOverview()
            compare(app.overviewAnimationRunning, true)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, target)
            keyClick(Qt.Key_Return)
            compare(app.pendingOverviewSelection, target)
            compare(app.overviewSelectedView, app.homeView,
                    "Opening continues to scale the original card without a jump")
            tryCompare(app, "overviewVisible", false, 1500)
            compare(app.activeView, target)
            compare(app.pendingOverviewSelection, null)
        }

        function test_overview_accepts_early_card_click() {
            app.activateHome()
            app.toggleOverview()
            tryVerify(() => app.overviewProgress > 0.8 && app.overviewProgress < 0.95)
            const target = app.views[app.views.length - 1]
            const card = overviewCard(target)
            const mouse = findChild(card, "overviewCardMouse")
            compare(mouse.enabled, true)
            mouseClick(card, card.width / 2, card.height / 2)
            compare(app.pendingOverviewSelection, target)
            tryCompare(app, "overviewVisible", false, 1500)
            compare(app.activeView, target)
            app.toggleOverview()
            app.selectOverviewView(app.homeView)
            compare(app.pendingOverviewSelection, app.homeView)
            app.dismissOverview()
            compare(app.pendingOverviewSelection, null, "Dismissal cancels queued input")
        }

        function test_overview_keyboard_navigation_search_and_no_results() {
            appSettings.reduceMotion = true
            const first = app.views[0], third = app.views[2]
            first.url = "about:blank#keyboard-one"
            third.url = "about:blank#keyboard-two"
            app.activateHome()
            app.toggleOverview()
            app.requestActivate()
            tryVerify(() => app.active)
            const search = findChild(app, "overviewSearch")
            search.forceActiveFocus()
            waitForRendering(app.contentItem)
            for (const character of "keyboard") keyClick(character)
            compare(search.text, "keyboard", "Typing still edits the search field")
            compare(app.overviewNavigationTarget, first)
            keyClick(Qt.Key_Right)
            compare(app.overviewNavigationTarget, third, "Arrows skip filtered-out cards and Home")
            compare(search.text, "keyboard")
            keyClick(Qt.Key_Left, Qt.ControlModifier)
            compare(app.overviewNavigationTarget, third, "Modified editing keys stay with the search field")
            search.text = "no-matching-card"
            compare(app.overviewNavigationTarget, null)
            keyClick(Qt.Key_Return)
            compare(app.overviewVisible, true, "Enter with no search results does not open a hidden tab")
            search.text = "Home"
            compare(app.overviewNavigationTarget, app.homeView)
            keyClick(Qt.Key_Enter, Qt.KeypadModifier)
            compare(app.overviewVisible, false)
            compare(app.activeView, app.homeView)
        }

        function test_overview_keyboard_navigates_group_cards_and_expanded_contents() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Keyboard group")
            app.assignTabGroup(second, id)
            app.updateTabGroup(id, {overviewCollapsed: true}, true)
            app.activateHome()
            app.toggleOverview()
            app.requestActivate()
            tryVerify(() => app.active)
            findChild(app, "overviewSearch").forceActiveFocus()
            waitForRendering(app.contentItem)
            keyClick(Qt.Key_Right, Qt.ShiftModifier)
            compare(app.overviewNavigationTarget, id)
            compare(app.selectedTabViews, [first, second], "Shift navigation selects a collapsed group's tabs")
            const highlight = findChild(app.overviewGroupContainer(id), "overviewGroupNavigationHighlight")
            verify(highlight.visible)
            compare(highlight.color, app.selectionTint)
            compare(highlight.border.width, 0)
            keyClick(Qt.Key_Escape)
            compare(app.selectedTabViews, [])
            compare(highlight.color.a, 0, "Escape also clears a group selection tint")
            keyClick(Qt.Key_Return)
            compare(app.groupFor(first).overviewCollapsed, false)
            compare(app.overviewVisible, true)
            keyClick(Qt.Key_Return)
            compare(app.groupFor(first).overviewCollapsed, true)
            keyClick(Qt.Key_Return)
            keyClick(Qt.Key_Down)
            compare(app.overviewNavigationTarget, second, "Down follows the group's card column")
            compare(app.activeView, app.homeView)
            keyClick(Qt.Key_Return)
            compare(app.overviewVisible, false)
            compare(app.activeView, second)
        }

        function test_home_card_drag_returns_to_its_slot_data() {
            return [{tag: "with-files", onlyHome: false, outside: false},
                    {tag: "only-home-outside", onlyHome: true, outside: true}]
        }

        function test_home_card_drag_returns_to_its_slot(data) {
            if (data.onlyHome) {
                appSettings.reduceMotion = true
                for (const view of app.views.slice()) app.closeTab(app.views.indexOf(view))
                tryVerify(() => app.views.length === 0)
                appSettings.reduceMotion = false
            }
            const selected = app.activeView
            const order = app.views.slice()
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            tryCompare(app, "overviewAnimationRunning", false)
            waitForRendering(app.contentItem)
            const card = overviewCard(app.homeView)
            const frame = app.homeView.frameContainer
            const origin = Qt.point(card.x, card.y)
            const start = card.mapToItem(app.contentItem, card.width / 2, card.height / 2)
            const end = Qt.point(data.outside ? app.width + 50 : start.x + 150, start.y + 80)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            mouseMove(app.contentItem, end.x, end.y, 20)
            tryCompare(app, "overviewDraggedView", app.homeView)
            verify(card.dragOffsetX > 0)
            compare(frame.parent, card)
            compare(app.dragView, null, "Home does not start a transferable tab drag")
            compare(app.overviewDropIndex, -1)
            mouseRelease(app.contentItem, end.x, end.y)
            tryCompare(app, "overviewDraggedView", null)
            verify(card.settling)
            verify(card.dragOffsetX > 0, "Home animates back instead of snapping")
            tryCompare(card, "settling", false)
            compare(card.dragOffsetX, 0)
            compare(card.dragOffsetY, 0)
            compare(card.x, origin.x)
            compare(card.y, origin.y)
            compare(frame.parent, card)
            compare(app.overviewVisible, true)
            compare(app.activeView, selected)
            compare(app.views.length, order.length)
            for (let i = 0; i < order.length; ++i) compare(app.views[i], order[i])
            compare(app.detachedWindows.length, 0)
        }

        function test_overview_drag_reorders_whole_card() {
            const selected = app.activeView
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            wait(260)
            const view = app.views[0]
            const card = overviewCard(view)
            const destination = overviewCard(app.views[2])
            verify(card && destination)
            const frame = view.frameContainer
            const start = card.mapToItem(app.contentItem, card.width / 2, card.height / 2)
            const end = destination.mapToItem(app.contentItem, destination.width / 2, destination.height / 2)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            mouseMove(app.contentItem, end.x, end.y, 20)
            tryCompare(app, "overviewDraggedView", view)
            tryVerify(() => !!app.dragSnapshot)
            compare(findChild(app, "tabDragPreview").visible, false)
            app.nativeTabDragRequested = true
            app.startNativeTabDrag()
            wait(20)
            compare(app.nativeTabDragRunning, false, "Native previews must not start inside the window")
            app.updateItemDrag(Qt.point(app.width + 1, end.y))
            tryCompare(findChild(app, "tabDragPreview"), "visible", true)
            app.updateItemDrag(Qt.point(end.x, end.y))
            compare(findChild(app, "tabDragPreview").visible, false)
            compare(app.overviewDropIndex, 2)
            const stripTab = tabButton(1)
            tryVerify(() => stripTab.visualOffset < -1)
            tryVerify(() => Math.abs(stripTab.visualOffset + app.tabWidth) < 1)
            const stripX = stripTab.mapToItem(app.contentItem, 0, 0).x
            compare(frame.parent, card)
            compare(frame.previewCard, card)
            mouseRelease(app.contentItem, end.x, end.y)
            tryCompare(app, "overviewDraggedView", null)
            compare(app.views[2], view)
            fuzzyCompare(stripTab.mapToItem(app.contentItem, 0, 0).x, stripX, 2,
                         "The strip keeps its animated position when the card is dropped")
            compare(overviewCard(view), card, "Reordering must keep the same card")
            compare(frame.parent, card, "The preview must stay inside its card")
            wait(260)
            compare(card.dragOffsetX, 0)
            compare(card.dragOffsetY, 0)
            compare(app.activeView, selected)
            app.selectOverviewView(view)
            tryCompare(app, "overviewVisible", false)
            compare(app.activeView, view)
        }

        function test_overview_background_keeps_configured_transparency() {
            appSettings.translucentSidebars = true
            appSettings.toolbarOpacity = 50
            app.activeView.hasLoadedFrame = true
            const background = findChild(app, "browserBackground")
            compare(background.opacity, 1)
            fuzzyCompare(background.color.a, 0.5, 0.01)
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            app.selectOverviewView(app.activeView)
            wait(150)
            compare(background.opacity, 1)
            tryCompare(app, "overviewVisible", false)
            wait(180)
            compare(background.opacity, 1)
            fuzzyCompare(background.color.a, 0.5, 0.01)
            appSettings.translucentSidebars = false
            appSettings.toolbarOpacity = 100
        }

        SignalSpy { id: transferLoads; signalName: "loadStateChanged" }

        function test_transfer_preserves_page_and_survives_source_window() {
            const view = app.activeView
            view.runJavaScript("document.open(); document.write(\"<html><title>Transfer test</title><body style='height:5000px'><input id='field'></body></html>\"); document.close(); window.keepMe = {value: 123};")
            tryCompare(view, "title", "Transfer test")
            tryCompare(view, "loading", false)
            let prepared = false
            view.runJavaScript("document.getElementById('field').value = 'unsaved'; window.scrollTo(0, 700); true", result => prepared = result)
            tryVerify(() => prepared)
            transferLoads.target = view
            transferLoads.clear()
            const frame = view.frameContainer
            const profile = view.profile
            const window = app.moveTabToNewWindow(app.activeIndex)
            verify(window)
            window.homeView.stop()
            compare(window.activeView, view)
            compare(window.views.length, 1)
            compare(app.views.includes(view), false)
            compare(view.ownerWindow, window)
            compare(view.profile, profile)
            compare(view.frameContainer, frame)
            compare(frame.parent, window.browserContent)
            let state = ""
            view.runJavaScript("JSON.stringify([keepMe.value, document.getElementById('field').value, scrollY])", result => state = result)
            tryVerify(() => state !== "")
            compare(state, '[123,"unsaved",700]')
            wait(200)
            compare(transferLoads.count, 0, "Moving the live view must not start another load")
            window.openTab("about:blank")
            const childView = window.activeView
            tryCompare(childView, "title", "about:blank")
            tryCompare(childView, "loading", false)
            childView.runJavaScript("document.open(); document.write('<html><title>Child tab</title></html>'); document.close(); window.keepChild = 456;")
            tryCompare(childView, "title", "Child tab")
            tryCompare(childView, "loading", false)
            const other = window.moveTabToNewWindow(window.activeIndex)
            verify(other)
            window.close()
            wait(100)
            let childState = 0
            childView.runJavaScript("document.title = 'Still alive'; keepChild", result => childState = result)
            tryVerify(() => childState === 456)
            compare(childView.ownerWindow, other)
            tryCompare(childView, "title", "Still alive")
            childView.url = "https://www.figma.com/design/TransferTest/Test"
            childView.stop()
            tryCompare(tabButton(0, other), "filePage", true)
            other.width = 900
            tryCompare(childView, "width", other.browserWidth)
            transferLoads.target = null
            other.close()
        }

        function test_drag_out_tabs_and_cards_transfers_views() {
            const view = app.views[0]
            const button = tabButton(0)
            const start = button.mapToItem(app.contentItem, 80, 20)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            mouseMove(app.contentItem, start.x + 30, -50, 20)
            mouseRelease(app.contentItem, start.x + 30, -50)
            tryVerify(() => app.detachedWindows.length === 1)
            const window = app.detachedWindows[0]
            compare(window.activeView, view)
            compare(app.views.includes(view), false)
            window.close()
            tryVerify(() => app.detachedWindows.length === 0)
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            wait(260)
            const cardView = app.views[0]
            const card = overviewCard(cardView)
            const cardStart = card.mapToItem(app.contentItem, card.width / 2, card.height / 2)
            mousePress(app.contentItem, cardStart.x, cardStart.y)
            mouseMove(app.contentItem, cardStart.x + 30, cardStart.y, 20)
            mouseMove(app.contentItem, app.width + 1, cardStart.y, 20)
            mouseRelease(app.contentItem, app.width + 1, cardStart.y)
            tryVerify(() => app.detachedWindows.length === 1)
            compare(app.detachedWindows[0].activeView, cardView)
            compare(cardView.ownerWindow, app.detachedWindows[0])
            compare(app.overviewVisible, true)
            app.detachedWindows[0].close()
            app.dismissOverview()
        }

        function test_single_tab_cannot_detach_but_can_drop_in_existing_window() {
            const view = app.views[0]
            const source = app.moveTabToNewWindow(0)
            verify(source)
            source.homeView.stop()
            compare(source.views.length, 1)
            compare(source.moveTabToNewWindow(0), null)
            compare(app.detachedWindows.length, 1)
            source.x = app.x + app.width + 100
            source.y = app.y
            waitForRendering(source.contentItem)
            wait(100)
            const button = tabButton(0, source)
            const start = button.mapToItem(source.contentItem, 80, 20)
            const globalEnd = app.contentItem.mapToGlobal(150, 100)
            const end = source.contentItem.mapFromGlobal(globalEnd.x, globalEnd.y)
            transferLoads.target = view
            transferLoads.clear()
            mousePress(source.contentItem, start.x, start.y)
            mouseMove(source.contentItem, start.x + 30, start.y, 20)
            mouseMove(source.contentItem, start.x + 60, start.y, 20)
            tryCompare(source, "dragView", view)
            compare(findChild(source, "tabDragPreview").visible, false)
            mouseMove(source.contentItem, end.x, end.y, 20)
            tryCompare(findChild(source, "tabDragPreview"), "visible", true)
            mouseRelease(source.contentItem, end.x, end.y)
            tryCompare(view, "ownerWindow", app)
            tryVerify(() => app.detachedWindows.length === 0)
            compare(app.activeView, view)
            compare(app.views.length, 4)
            compare(view.frameContainer.parent, app.browserContent)
            compare(transferLoads.count, 0)
        }

        function test_single_card_can_drop_into_existing_overview() {
            const view = app.views[0]
            const source = app.moveTabToNewWindow(0)
            verify(source)
            source.homeView.stop()
            source.x = app.x + app.width + 100
            source.y = app.y
            app.toggleOverview()
            source.toggleOverview()
            tryCompare(source, "overviewProgress", 1)
            tryCompare(app, "overviewProgress", 1)
            wait(260)
            const card = overviewCard(view, source)
            const start = card.mapToItem(source.contentItem, card.width / 2, card.height / 2)
            const globalEnd = app.contentItem.mapToGlobal(400, 200)
            const end = source.contentItem.mapFromGlobal(globalEnd.x, globalEnd.y)
            mousePress(source.contentItem, start.x, start.y)
            mouseMove(source.contentItem, start.x + 30, start.y, 20)
            tryVerify(() => !!source.dragSnapshot)
            compare(findChild(source, "tabDragPreview").visible, false)
            mouseMove(source.contentItem, end.x, end.y, 20)
            mouseRelease(source.contentItem, end.x, end.y)
            tryCompare(view, "ownerWindow", app)
            tryVerify(() => app.detachedWindows.length === 0)
            compare(app.overviewVisible, true)
            compare(view.frameContainer.parent, overviewCard(view))
            compare(view.frameContainer.previewCard, overviewCard(view))
        }

        function test_native_drop_session_validates_and_transfers_last_tab() {
            const view = app.views[0]
            const source = app.moveTabToNewWindow(0)
            verify(source)
            source.homeView.stop()
            source.beginItemDrag(view, tabButton(0, source), Qt.point(80, 20))
            compare(source.canAcceptTabDrop(source.dragToken), true)
            compare(app.canAcceptTabDrop("unrelated-drag"), false)
            compare(app.canAcceptTabDrop(source.dragToken), true)
            compare(app.acceptTabDrop(source.dragToken), true)
            source.finishNativeTabDrag(Qt.MoveAction)
            tryCompare(view, "ownerWindow", app)
            tryVerify(() => app.detachedWindows.length === 0)
            compare(app.tabDragSession, null)
            compare(app.activeView, view)
        }

        function test_native_drop_back_in_source_keeps_tab() {
            const view = app.views[0]
            app.beginItemDrag(view, tabButton(0), Qt.point(80, 20))
            compare(app.acceptTabDrop(app.dragToken), true)
            app.finishNativeTabDrag(Qt.MoveAction)
            wait(100)
            compare(app.detachedWindows.length, 0)
            compare(app.views.length, 4)
            compare(view.ownerWindow, app)
            compare(app.tabDragSession, null)
        }

        Timer {
            id: nativeDropEvents
            interval: 60
            property var callback: null
            onTriggered: if (callback) callback()
        }

        SignalSpy { id: nativeDragStarted; signalName: "dragStarted" }
        SignalSpy { id: nativeDragFinished; signalName: "dragFinished" }

        function test_native_card_drop_without_app_target_detaches() {
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            wait(260)
            const view = app.views[1]
            app.beginItemDrag(view, overviewCard(view), Qt.point(app.width + 1, 200))
            tryVerify(() => !!app.dragSnapshot)
            tryCompare(findChild(app, "tabDragPreview"), "visible", true)
            // A desktop drop can report MoveAction without a ReSketch destination.
            app.finishNativeTabDrag(Qt.MoveAction)
            tryVerify(() => app.detachedWindows.length === 1)
            compare(app.detachedWindows[0].activeView, view)
            compare(view.ownerWindow, app.detachedWindows[0])
        }

        function test_native_card_drag_out_detaches_correct_view() {
            app.toggleOverview()
            tryCompare(app, "overviewProgress", 1)
            wait(260)
            const view = app.views[1]
            const card = overviewCard(view)
            const start = card.mapToItem(app.contentItem, card.width / 2, card.height / 2)
            mousePress(app.contentItem, start.x, start.y)
            mouseMove(app.contentItem, start.x + 30, start.y, 20)
            tryCompare(app, "dragView", view)
            tryVerify(() => !!app.dragSnapshot)
            const proxy = findChild(app, "nativeDragProxy")
            nativeDragStarted.target = proxy.Drag
            nativeDragFinished.target = proxy.Drag
            nativeDragStarted.clear()
            nativeDragFinished.clear()
            appSettings.nativeTabDragSupported = true
            nativeDropEvents.callback = () => mouseRelease(app.contentItem, app.width + 60, start.y)
            nativeDropEvents.start()
            mouseMove(app.contentItem, app.width + 60, start.y, 20)
            tryVerify(() => app.detachedWindows.length === 1)
            compare(app.detachedWindows[0].activeView, view)
            compare(view.ownerWindow, app.detachedWindows[0])
            compare(nativeDragStarted.count, 1)
            compare(nativeDragFinished.count, 1)
        }

        function test_native_drag_starts_with_preview() {
            const view = app.views[0]
            const source = app.moveTabToNewWindow(0)
            verify(source)
            source.homeView.stop()
            source.x = app.x + app.width + 100
            source.y = app.y
            waitForRendering(source.contentItem)
            wait(100)
            const button = tabButton(0, source)
            const start = button.mapToItem(source.contentItem, 80, 20)
            const globalEnd = app.contentItem.mapToGlobal(150, 100)
            const end = source.contentItem.mapFromGlobal(globalEnd.x, globalEnd.y)
            mousePress(source.contentItem, start.x, start.y)
            source.beginItemDrag(view, button, Qt.point(start.x, start.y))
            tryVerify(() => !!source.dragSnapshot)
            const proxy = findChild(source, "nativeDragProxy")
            nativeDragStarted.target = proxy.Drag
            nativeDragFinished.target = proxy.Drag
            nativeDragStarted.clear()
            nativeDragFinished.clear()
            appSettings.nativeTabDragSupported = true
            nativeDropEvents.callback = () => {
                mouseMove(source.contentItem, end.x, end.y, 10)
                mouseRelease(source.contentItem, end.x, end.y)
            }
            nativeDropEvents.start()
            source.updateItemDrag(Qt.point(-50, 20))
            tryCompare(view, "ownerWindow", app)
            tryVerify(() => app.detachedWindows.length === 0)
            compare(app.tabDragSession, null)
            compare(nativeDragStarted.count, 1)
            compare(nativeDragFinished.count, 1)
            // Offscreen has no desktop drag backend, but must start and finish without errors.
            verify([Qt.IgnoreAction, Qt.MoveAction].includes(nativeDragFinished.signalArguments[0][0]))
        }
    }
}
