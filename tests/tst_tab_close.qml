import QtQuick
import QtTest
import QtWebEngine
import "../src" as App
import "../src/FigmaTheme.js" as FigmaTheme

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
        property int maximumLoadedTabs: 5
        property int sleepMinutes: 5
        property bool sleepingTabPreviews: false
        property bool keepHomeAwake: true
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
        function cursorPosition() { return Qt.point(0, 0) }
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
    App.Main {
        id: app
        sharedProfile: testProfile
        property int systemMoveRequests: 0
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

        function cleanup() {
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
                          + '.gpu-view-content { position:absolute; inset:0; background:#444 }</style>'
                          + '<div class="gpu-view-content"></div><nav class="fb-sidebar">'
                          + '<div data-testid="facetedSearchModal" style="background:var(--color-bg)">'
                          + '<div data-preferred-theme="light" style="background:var(--color-bg)">Suggestions</div>'
                          + '</div></nav>'
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
                    + 'clip:getComputedStyle(document.querySelector(".gpu-view-content")).clipPath}:null})()',
                    value => { result = value })
            }
            tryVerify(() => { inspect(); return result && result.marked })
            compare(result.bg, "rgba(0, 0, 0, 0)")
            compare(result.search, "rgb(238, 238, 238)")
            compare(result.suggestions, result.search)
            verify(result.clip.indexOf("polygon") === 0)
            compare(view.backgroundColor.a, 0)
            const background = findChild(app.contentItem, "browserBackground")
            fuzzyCompare(background.color.a, 0.85, 0.01)

            appSettings.sidebarBackdrop = "canvas"
            applySidebar()
            tryVerify(() => { inspect(); return result && result.bg.indexOf("0.85") >= 0 })
            compare(result.clip, "none")
            compare(view.backgroundColor.a, 1)
            compare(result.search, "rgb(238, 238, 238)")

            view.runJavaScript('document.body.style.setProperty("--color-bg", "#222222")')
            applySidebar()
            tryVerify(() => { inspect(); return result && result.search === "rgb(34, 34, 34)" })
            compare(result.suggestions, result.search)

            appSettings.translucentSidebars = false
            applySidebar()
            tryVerify(() => { inspect(); return result && !result.marked })
            compare(result.bg, "rgb(255, 255, 255)")
            compare(result.clip, "none")
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
            compare(findChild(card, "overviewCardMask").layer.textureSize, halfSize)
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
            compare(frame.parent, card)
            compare(frame.previewCard, card)
            mouseRelease(app.contentItem, end.x, end.y)
            tryCompare(app, "overviewDraggedView", null)
            compare(app.views[2], view)
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
