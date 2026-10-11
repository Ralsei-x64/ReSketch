import QtQuick
import QtTest
import QtWebEngine
import "../src" as App

Item {
    width: 1280
    height: 800
    property QtObject appSettings: QtObject {
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
        property int sleepMinutes: 5
        property int maxMemoryGb: 5
        property bool highRefreshRate: true
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
        signal changed()
        signal effectiveThemeChanged()
        signal figmaAppearanceChanged()
        function refreshWindowBlur(window) {}
        function registerMainWindow(window) {}
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
        function openExport(path, folder) { return true }
        function deleteExport(path) {
            if (!exportDeletionSucceeds) return false
            exportHistory = exportHistory.filter(item => item.path !== path)
            return true
        }
    }

    WebEngineProfile { id: testProfile; offTheRecord: true }
    App.Main { id: app; sharedProfile: testProfile }

    TestCase {
        name: "TabCloseSelection"
        when: windowShown && app.visible

        function tabButton(index) {
            function find(item) {
                if (item.index === index && item.closePending !== undefined)
                    return item
                for (const child of item.children || []) {
                    const result = find(child)
                    if (result) return result
                }
                return null
            }
            return find(app.contentItem)
        }

        function init() {
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

        function test_overview_sidebar_background_fades() {
            compare(app.overviewSidebarBackdrop, 0)
            app.toggleOverview()
            compare(app.overviewVisible, true)
            verify(app.overviewSidebarBackdrop < 1, "Overview background must not appear instantly")
            tryCompare(app, "overviewSidebarBackdrop", 1, 300)
            app.dismissOverview()
            tryCompare(app, "overviewSidebarBackdrop", 0, 300)
            appSettings.reduceMotion = true
            app.toggleOverview()
            compare(app.overviewSidebarBackdrop, 1)
            app.dismissOverview()
            compare(app.overviewSidebarBackdrop, 0)
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
    }
}
