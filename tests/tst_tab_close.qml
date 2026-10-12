// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtTest
import QtWebEngine
import "../src" as App
import "../src/FigmaTheme.js" as FigmaTheme

Item {
    id: fixture
    property int notificationCount: 0
    readonly property bool gpuMasking: GraphicsInfo.api !== GraphicsInfo.Software
    width: 1280
    height: 800
    property QtObject appSettings: QtObject {
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
        property string sidebarBackdrop: "desktop"
        property bool reduceMotion: false
        property int toolbarOpacity: 100
        property bool windowControlsInTabBar: false
        property bool keepWindowDecorations: true
        property bool ignoreToolbarBlur: false
        property int minimumLoadedTabs: 5
        property int maximumLoadedTabs: 5
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
        function resetSettings() { figmaCustomCss = "" }
        function openExport(path, folder) { return true }
        function deleteExport(path) {
            if (!exportDeletionSucceeds) return false
            exportHistory = exportHistory.filter(item => item.path !== path)
            return true
        }
    }

    WebEngineProfile { id: testProfile; offTheRecord: true; persistentPermissionsPolicy: WebEngineProfile.StoreInMemory }
    Component {
        id: notificationProbe
        WebEngineView {
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
            verify(picker.y > editor.y + editor.height, "Color picker is below the name field")
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
            verify(first.overviewEntrance < 1)
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
            compare(container.height, 60)
            compare(card.visible, false)
            compare(String(findChild(container, "overviewGroupArrow").source), "arrow-right")
            mouseClick(container, container.width - 30, 25)
            compare(app.groupFor(first).overviewCollapsed, false)
            compare(card.visible, true)

            // The entire container, including its collapsed header, accepts membership drops.
            app.overviewDraggedView = outside
            app.overviewDropIndex = app.views.indexOf(outside)
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

        function test_overview_group_header_drags_container_and_cards_together() {
            appSettings.reduceMotion = true
            app.width = 1600
            const first = app.views[0], second = app.views[1], selected = app.activeView
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            const otherId = app.createTabGroup(app.views[2], "Other")
            app.assignTabGroup(app.views[3], otherId)
            app.toggleOverview()
            app.updateTabGroup(otherId, {overviewCollapsed: true})
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
            const end = other.mapToItem(app.contentItem, 80, other.height - 2)
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
            compare(app.groupFor(first).overviewCollapsed, undefined, "Dragging must not collapse the container")
            compare(card.parent, container.cardArea)
            compare(frame.parent, card)
            verifySelection(selected)
        }

        function test_overview_group_expand_and_collapse_animate_inside_clip() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1]
            const id = app.createTabGroup(first, "Design")
            app.assignTabGroup(second, id)
            app.activateTab(0)
            app.toggleOverview()
            findChild(app, "overviewFlickable").resetScroll(0)
            const container = app.overviewGroupContainer(id)
            const card = overviewCard(first)
            const frame = first.frameContainer
            const height = container.height
            appSettings.reduceMotion = false
            app.updateTabGroup(id, {overviewCollapsed: true})
            compare(container.collapsing, true)
            verify(!app.groupFor(first).overviewCollapsed, "Keep the container open for the exit animation")
            tryVerify(() => first.overviewEntrance > 0 && first.overviewEntrance < 1)
            verify(card.opacity < 1)
            verify(card.y < 0, "Closing cards slide up into their clipped container")
            compare(card.parent, container.cardArea)
            compare(container.cardArea.clip, true)
            compare(frame.parent, card)
            tryVerify(() => !!app.groupFor(first).overviewCollapsed)
            tryCompare(container, "height", 60)
            compare(app.views.length, 4, "Collapsing never closes Chromium tabs")
            app.updateTabGroup(id, {overviewCollapsed: false})
            compare(container.expanding, true)
            compare(card.visible, true)
            tryVerify(() => container.height > 60 && container.height < height)
            tryVerify(() => first.overviewEntrance > 0 && first.overviewEntrance < 1)
            verify(card.y < 0, "Expanding cards enter from the same offset as new cards")
            compare(card.parent, container.cardArea)
            compare(container.cardArea.clip, true)
            compare(frame.parent, card)
            tryCompare(container, "expanding", false)
            fuzzyCompare(container.height, height, 1)
            compare(first.overviewEntrance, 1)
            fuzzyCompare(card.y, 0, 1)
            verifySelection(first)
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

        function test_shift_click_selects_range_in_strip_and_overview() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            mouseClick(tabButton(0), 80, 20)
            mouseClick(tabButton(2), 80, 20, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [first, second, third])
            compare(app.tabSelectionAnchor, first)
            compare(app.activeView, third)
            verify(tabButton(0).multiSelected)
            verify(tabButton(1).multiSelected)
            verify(!tabButton(3).multiSelected)
            mouseClick(tabButton(1), 80, 20, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [first, second], "The range keeps its original anchor")
            app.toggleOverview()
            const card = overviewCard(fourth)
            mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.overviewVisible, true, "Shift selection must keep overview open")
            compare(app.selectedTabViews, [first, second, third, fourth])
            compare(app.activeView, second, "Overview range selection does not switch the webview")
            compare(findChild(overviewCard(first), "overviewCardBorder").border.width, 2)
            const id = app.createTabGroup(first, "Selected tabs", "#ab3344")
            app.assignSelectedTabGroup(second, id)
            for (const view of [first, second, third, fourth]) compare(view.tabGroupId, id)
            app.ungroupTabs(id)
            const target = overviewCard(third)
            mouseClick(target, target.width / 2, target.height / 2)
            compare(app.overviewVisible, false)
            compare(app.selectedTabViews, [third], "A plain click clears the range")
            compare(app.activeView, third)
        }

        function test_tab_pointer_click_does_not_restart_the_switch_animation() {
            const previous = app.activeView
            mouseClick(tabButton(0), 80, 20)
            compare(app.activeView, app.views[0])
            compare(app.outgoingView, previous, "The second click handler must not cancel the transition")
            tryCompare(app, "outgoingView", null)
        }

        function test_shift_selection_survives_reorder_and_excludes_hidden_search_results() {
            appSettings.reduceMotion = true
            const first = app.views[0], second = app.views[1], third = app.views[2], fourth = app.views[3]
            first.url = "about:blank#match-one"
            third.url = "about:blank#match-two"
            app.activateTab(0)
            app.selectFileTabs(third, Qt.ShiftModifier)
            app.reorderTab(0, 3)
            compare(app.selectedTabViews, [first, second, third], "Selection follows view identities when reordered")
            compare(app.tabSelectionAnchor, first)
            app.toggleOverview()
            findChild(app, "overviewSearch").text = "match"
            compare(app.overviewFilteredCount(), 2)
            const card = overviewCard(third)
            mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            compare(app.selectedTabViews, [third, first], "Shift selects only cards visible in the search results")
            app.closeSelectedTabs(third)
            tryCompare(app, "views", [second, fourth], 5000, "Hidden search results are never closed by the selection")
        }

        function test_shift_selection_new_group_and_bulk_close() {
            appSettings.reduceMotion = true
            const targets = app.views.slice(0, 3), remaining = app.views[3]
            app.activateTab(0)
            app.toggleOverview()
            const card = overviewCard(targets[2])
            mouseClick(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.ShiftModifier)
            app.requestTabGroup(targets[1])
            findChild(app, "tabGroupNameEditor").text = "Batch"
            findChild(app, "tabGroupNameDialog").accept()
            compare(app.tabGroups.length, 1)
            for (const view of targets) compare(view.tabGroupId, app.tabGroups[0].id)
            app.closeSelectedTabs(targets[1])
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

        function test_only_home_can_create_notifications_with_shared_permission() {
            appSettings.desktopNotifications = true
            appSettings.changed()
            fixture.notificationCount = 0
            const permission = testProfile.queryPermission("https://www.figma.com", WebEnginePermission.PermissionType.Notifications)
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
            compare(app.homeView.lifecycleState, WebEngineView.LifecycleState.Active)
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
            appSettings.rememberedTabGroups = [{title: "Restored group", color: "#4477aa",
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
            value = null
            signin.runJavaScript("keepSignin", result => value = result)
            tryVerify(() => value === 456)
            signin.authWindow.close()
            tryVerify(() => findChild(app, "googleSignInWindow") === null)
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
            app.tabSelectionAnchor = null
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
            appSettings.toolbarOpacity = 100
            appSettings.sidebarBackdrop = "desktop"
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
                view.runJavaScript(FigmaTheme.sidebarMaskSource + ';' + FigmaTheme.sidebarSource
                    + ';sidebarAppearance(' + JSON.stringify(options) + ', (id,css)=>{'
                    + 'let s=document.getElementById(id);if(!css){s?.remove();return}'
                    + 'if(!s){s=document.createElement("style");s.id=id;document.head.appendChild(s)}'
                    + 's.textContent=css;});')
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
            tryCompare(app.views[0], "lifecycleState", WebEngineView.LifecycleState.Frozen)
            tryCompare(app.views[1], "lifecycleState", WebEngineView.LifecycleState.Frozen)
            compare(selected.lifecycleState, WebEngineView.LifecycleState.Active)
            compare(app.views[3].lifecycleState, WebEngineView.LifecycleState.Active)
            compare(app.homeView.lifecycleState, WebEngineView.LifecycleState.Frozen)
            appSettings.sleepingTabPreviews = true
            app.toggleOverview()
            wait(100)
            const awake = [app.homeView].concat(app.views).filter(view =>
                view.lifecycleState === WebEngineView.LifecycleState.Active)
            compare(awake.length, 2)
            compare(findChild(app.views[0].frameContainer.parent, "sleepingTabIcon").visible, true)
            compare(app.activeView, selected)
            appSettings.maximumLoadedTabs = 1
            appSettings.changed()
            tryCompare(app.views[3], "lifecycleState", WebEngineView.LifecycleState.Frozen)
            compare(selected.lifecycleState, WebEngineView.LifecycleState.Active)
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
            compare(home.lifecycleState, WebEngineView.LifecycleState.Active)
            app.sleepTab(home, WebEngineView.LifecycleState.Discarded)
            compare(home.lifecycleState, WebEngineView.LifecycleState.Active)
            app.freezeAllTabs()
            compare(home.lifecycleState, WebEngineView.LifecycleState.Active)
            tryCompare(app.activeView, "lifecycleState", WebEngineView.LifecycleState.Frozen)
            app.wakeCurrentTab()

            appSettings.keepHomeAwake = false
            appSettings.changed()
            tryCompare(home, "lifecycleState", WebEngineView.LifecycleState.Frozen)
            appSettings.keepHomeAwake = true
            appSettings.changed()
            compare(home.lifecycleState, WebEngineView.LifecycleState.Active)
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
            return [{tag: "frozen", state: WebEngineView.LifecycleState.Frozen},
                    {tag: "unloaded", state: WebEngineView.LifecycleState.Discarded}]
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
            tryCompare(view, "lifecycleState", WebEngineView.LifecycleState.Frozen)
            verify(view.sleepPreview)
            verify(view.sleepPreview.url)
            if (data.state === WebEngineView.LifecycleState.Discarded) {
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
            compare(view.lifecycleState, WebEngineView.LifecycleState.Active)
            compare(view.sleepPreview, null)
            compare(snapshot.visible, false)
            compare(sleepIcon.visible, false)
        }

        function test_sleeping_previews_can_be_disabled() {
            appSettings.sleepingTabPreviews = false
            appSettings.maximumLoadedTabs = 1
            const view = app.views[0]
            view.hasLoadedFrame = true
            app.sleepTab(view, WebEngineView.LifecycleState.Discarded)
            compare(view.lifecycleState, WebEngineView.LifecycleState.Discarded)
            compare(view.sleepCapturePending, false)
            compare(view.sleepPreview, null)
            app.toggleOverview()
            compare(view.lifecycleState, WebEngineView.LifecycleState.Active)
            compare(findChild(view.frameContainer, "sleepingTabPreview").visible, false)
            for (const page of [app.homeView].concat(app.views)) {
                compare(page.lifecycleState, WebEngineView.LifecycleState.Active)
                compare(page.visible, true)
                compare(findChild(page.frameContainer.parent, "sleepingTabIcon").visible, false)
            }
            appSettings.sleepingTabPreviews = true
            appSettings.changed()
            tryCompare(view, "lifecycleState", WebEngineView.LifecycleState.Frozen)
            appSettings.sleepingTabPreviews = false
            appSettings.changed()
            compare(view.lifecycleState, WebEngineView.LifecycleState.Active)
            compare(view.visible, true)
            compare(findChild(view.frameContainer.parent, "sleepingTabIcon").visible, false)
            app.dismissOverview()
            tryCompare(view, "lifecycleState", WebEngineView.LifecycleState.Frozen)
        }

        function test_pending_sleep_does_not_unload_reselected_tab() {
            appSettings.sleepingTabPreviews = true
            const view = app.views[0]
            view.hasLoadedFrame = true
            app.sleepTab(view, WebEngineView.LifecycleState.Discarded)
            verify(view.sleepCapturePending)
            app.activateTab(0, false)
            tryCompare(view, "sleepCapturePending", false)
            compare(app.activeView, view)
            compare(view.lifecycleState, WebEngineView.LifecycleState.Active)
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

        function test_overview_hover_only_darkens_border() {
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
            compare(background.opacity, 1)
            compare(String(background.color), backgroundColor)
            compare(app.overviewSidebarBackdrop, 1)
            compare(view.opacity, 1)
            compare(border.color, "#00000000")
            compare(border.border.width, 1)
            verify(String(border.border.color) !== idleBorder)
            fuzzyCompare(border.border.color.r, 0, 0.01)
            mouseMove(app.contentItem, app.width - 10, app.height - 10)
            tryCompare(hover, "containsMouse", false)
            compare(String(border.border.color), idleBorder)
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
            request.state = WebEngineDownloadRequest.DownloadCompleted
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
            const request = {state: WebEngineDownloadRequest.DownloadCancelled,
                             downloadDirectory: "/tmp", downloadFileName: "Frame.png"}
            app.completeDownload(request)
            compare(appSettings.recordedExport, "")
            request.state = WebEngineDownloadRequest.DownloadCompleted
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
            about.close()
            wait(50)
            compare(findChild(app, "aboutWindow"), about, "Disabling release keeps closed windows ready")
            appSettings.releaseClosedWindows = true
            appSettings.changed()
            tryVerify(() => !findChild(app, "aboutWindow"))
            app.openExportHistory()
            const history = findChild(app, "exportHistoryWindow")
            verify(history && history.visible)
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

        SignalSpy { id: transferLoads; signalName: "loadingChanged" }

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
