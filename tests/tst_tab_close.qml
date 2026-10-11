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
        property string chromiumFlags: ""
        property string profileStoragePath: ""
        signal changed()
        signal effectiveThemeChanged()
        function refreshWindowBlur(window) {}
        function registerMainWindow(window) {}
        function copyToClipboard(text) {}
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
