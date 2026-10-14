// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt.labs.platform as Platform
import ReSketch.Cef
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as IconThemes
import "Policy.js" as Policy
import "FigmaMenu.js" as FigmaMenu
import "FigmaTheme.js" as FigmaTheme
import "NotificationPolicy.js" as NotificationPolicy
import "Shortcuts.js" as Shortcuts

Kirigami.ApplicationWindow {
    id: root

    readonly property url homeUrl: "https://www.figma.com/files/recent"
    readonly property url loginUrl: "https://www.figma.com/login"
    readonly property url newTabUrl: "https://www.figma.com/desktop_new_tab"
    readonly property int tabStripHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property int tabWidth: 220
    readonly property real tabAreaWidth: Math.max(0, width - homeButton.width
                                               - toolbarActions.width
                                               - windowControlGroup.width)
    readonly property real tabStripWidth: views.reduce((total, view, index) => total + tabSlotWidth(index), 0)
    readonly property bool tabStripOverflow: tabStripWidth > tabAreaWidth + 1
    readonly property int tabIconSize: Kirigami.Units.iconSizes.small
    readonly property int tabContentLeftMargin: Kirigami.Units.smallSpacing + 5
    readonly property real toolbarAlpha: appSettings.toolbarOpacity / 100
    readonly property color selectionTint: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                  Kirigami.Theme.highlightColor.g,
                                                  Kirigami.Theme.highlightColor.b, 0.14)
    readonly property bool floatingFileSidebars: appSettings.floatingSidebars && !!activeView
                                                  && Policy.isFileUrl(String(activeView.tabUrl))
    readonly property bool desktopSidebars: (appSettings.translucentSidebars || floatingFileSidebars)
                                            && appSettings.sidebarBackdrop === "desktop"
                                            && appSettings.toolbarOpacity < 100
    readonly property int overviewColumns: Math.min(width < 1360 ? 3 : 4, tabModel.count + 1)
    readonly property real overviewMargin: 24
    readonly property real overviewGap: 18
    readonly property real overviewTitleHeight: 34
    readonly property real overviewSearchHeight: 60
    readonly property real overviewCardWidth: tabModel.count === 0
                                              ? Math.max(1, Math.min(browserArea.width * 0.85,
                                                                    browserArea.width - 2 * overviewMargin,
                                                                    (browserArea.height - 2 * overviewMargin
                                                                     - overviewSearchHeight - overviewTitleHeight)
                                                                    * browserArea.width
                                                                    / Math.max(1, browserArea.height)))
                                              : Math.max(1, (browserArea.width - 2 * overviewMargin
                                                            - (overviewColumns - 1) * overviewGap)
                                                           / overviewColumns)
    readonly property real overviewScale: overviewCardWidth / Math.max(1, browserArea.width)
    readonly property real overviewCardHeight: overviewTitleHeight + browserArea.height * overviewScale
    readonly property bool framelessTabBar: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    readonly property bool homeMustStayAwake: appSettings.keepHomeAwake
                                              || appSettings.desktopNotifications && !primaryWindow
    readonly property bool chromiumFrameLoaded: !!activeView && activeView.hasLoadedFrame
                                               && !overviewVisible
    readonly property string figmaAppearanceScript: FigmaTheme.script({
        dark: appSettings.darkTheme,
        systemColors: appSettings.figmaSystemColors,
        palette: appSettings.figmaPalette,
        customCssEnabled: appSettings.figmaCustomCssEnabled,
        customCss: appSettings.figmaCustomCss,
        translucentSidebars: appSettings.translucentSidebars,
        floatingSidebars: appSettings.floatingSidebars,
        sidebarCornerRadius: appSettings.sidebarCornerRadius,
        sidebarMargin: appSettings.sidebarMargin,
        sidebarBackdrop: appSettings.sidebarBackdrop,
        opacity: appSettings.toolbarOpacity
    }, FigmaMenu.storeSource)
    property var views: []
    property var selectedTabViews: []
    property var selectedGroupIds: []
    readonly property bool keyboardPopupActive: Controls.Overlay.overlay.children.some(item => item.visible && item.activeFocus)
    readonly property bool selectionShortcutAvailable: selectedTabViews.length > 0 && !keyboardPopupActive
        && (!overviewVisible || overviewProgress >= 0.999 && !overviewAnimationRunning && !overviewClosing)
    property var rangeSelectionAnchor: null
    property var rangeSelectionBase: []
    onSelectedTabViewsChanged: {
        selectedGroupIds = selectedTabViews.length ? selectedGroupIds.filter(id =>
            views.filter(view => view.tabGroupId === id).every(view => selectedTabViews.includes(view))) : []
        if (!selectedTabViews.length) overviewRangeAnchor = null
        if (rangeSelectionAnchor && !selectedTabViews.includes(rangeSelectionAnchor)) {
            rangeSelectionAnchor = null
            rangeSelectionBase = []
        }
    }
    property var tabGroups: []
    property int nextGroupNumber: 1
    readonly property int groupHeaderWidth: 160
    readonly property bool groupAnimationRunning: views.some(view => Math.abs(view.groupExpansion - (groupFor(view)?.collapsed ? 0 : 1)) > 0.001)
    readonly property var sessionFileViews: views.filter(view => !view.overviewClosingCard
                        && !pendingCloseViews.includes(view) && !closingViews.includes(view))
                        .filter(view => Policy.isFileUrl(String(view.tabUrl)))
    readonly property list<string> sessionFileUrls: sessionFileViews.map(view => String(view.tabUrl))
    readonly property var sessionTabGroups: tabGroups.map(group => ({
        title: group.title, color: String(group.color), icon: group.icon || "folder", collapsed: group.collapsed,
        overviewCollapsed: !!group.overviewCollapsed,
        tabs: sessionFileViews.map((view, index) => view.tabGroupId === group.id ? index : -1).filter(index => index >= 0)
    })).filter(group => group.tabs.length)
    readonly property var chromiumPages: [homeView].concat(views).filter(view => !!view && !view.overviewClosingCard
        && !pendingCloseViews.includes(view) && !closingViews.includes(view)).map(view => ({
        view: view, home: view === homeView, pid: view.renderProcessPid, title: view === homeView ? qsTr("Home") : Policy.pageLabel(view.tabUrl, view.title)
    }))
    readonly property var memoryTabCandidates: [homeView].concat(views)
        .filter(view => memoryUnloadEligible(view)).map(view => ({view: view, lastUsedAt: view.lastUsedAt}))
    property var pendingPopups: []
    property var homeView: null
    property var activeView: null
    property var outgoingView: null
    readonly property int activeIndex: activeView && activeView !== homeView
                                       ? views.indexOf(activeView) : -1
    property bool allFrozen: false
    property string externalUrl: ""
    property var sharedProfile: null
    property var primaryWindow: null
    property var detachedWindows: []
    property var tabDragSession: null
    property var dragView: null
    property var dragViews: []
    property var dragSnapshot: null
    property string dragToken: ""
    property point dragScenePosition: Qt.point(0, 0)
    property size dragPreviewSize: Qt.size(220, 40)
    property bool nativeTabDragRunning: false
    property bool nativeTabDragRequested: false
    property alias browserContent: browserArea
    readonly property real browserWidth: browserArea.width
    readonly property real browserHeight: browserArea.height
    readonly property var browserProfile: sharedProfile || figmaProfile
    property url startupUrl: ""
    property int draggedTabIndex: -1
    property int tabDropIndex: -1
    property string tabDropGroupId: ""
    property bool animatingCloseGap: false
    property var heldOpenSelection: null
    property bool hideHeldSelection: false
    property bool homeSelectionGlide: false
    property var pendingCloseViews: []
    property var closingViews: []
    property var readyCloseViews: []
    property var retiredOverviewViews: []
    property var exportOrigins: ({})
    property int overviewClosingCardCount: 0
    property bool overviewVisible: false
    property real overviewSidebarBackdrop: overviewVisible ? 1 : 0
    Behavior on overviewSidebarBackdrop {
        id: overviewBackdropFade
        enabled: overviewBackdropFade.targetValue === 0 && !appSettings.reduceMotion
        NumberAnimation { duration: 150 }
    }
    property bool overviewClosing: false
    property real overviewProgress: 0
    readonly property bool overviewAnimationRunning: overviewAnimation.running
    readonly property bool overviewGroupAnimationRunning: tabGroups.some(group => overviewGroupContainer(group.id)?.transitioning)
    property var overviewSelectedView: null
    property var pendingOverviewSelection: null
    property var overviewNavigationTarget: null
    property var overviewRangeAnchor: null
    property var overviewDraggedView: null
    property int overviewDropIndex: -1
    property string overviewDropGroupId: ""
    readonly property var overviewLayout: layoutOverview()
    property string draggedGroupId: ""
    property int groupDropIndex: -1
    property real groupDragOffset: 0
    property string overviewDraggedGroupId: ""
    property int overviewGroupGeneration: 0
    property bool skipNextWebSlide: false
    readonly property bool webFullscreen: visibility === Window.FullScreen
    property bool autoHideToolbar: false
    readonly property bool toolbarAutoHidden: autoHideToolbar
    property bool fullscreenToolbarHovered: false
    property int visibilityBeforeFullscreen: Window.Windowed
    property bool autoHideBeforeFullscreen: false

    width: 1280
    height: 800
    minimumWidth: 640
    minimumHeight: 400
    flags: framelessTabBar ? Qt.Window | Qt.FramelessWindowHint : Qt.Window
    color: "transparent"
    background: Item { }
    title: Policy.windowTitle(activeView ? activeView.tabUrl : "", activeView ? activeView.title : "")
    onDesktopSidebarsChanged: appSettings.refreshWindowBlur(root)
    onChromiumFrameLoadedChanged: appSettings.refreshWindowBlur(root)
    onClosing: {
        for (const view of pendingPopups.slice()) discardPendingPopup(view)
        for (const loader of [settingsWindowLoader, aboutWindowLoader, exportHistoryWindowLoader])
            if (loader.item) loader.item.close()
        if (primaryWindow) {
            for (const view of [homeView].concat(views, retiredOverviewViews))
                if (view && view.frameContainer) view.frameContainer.destroy()
            primaryWindow.detachedWindows = primaryWindow.detachedWindows.filter(window => window !== root)
            Qt.callLater(() => root.destroy())
        }
    }

    Timer {
        id: closeGapTimer
        interval: 240
        onTriggered: {
            root.animatingCloseGap = false
            root.processPendingClose()
        }
    }

    Timer {
        id: overviewDisposalTimer
        interval: 260
        onTriggered: {
            const retired = root.retiredOverviewViews
            root.retiredOverviewViews = []
            for (const view of retired)
                view.frameContainer.destroy()
        }
    }

    FigmaMenus {
        id: figmaMenus
        page: root.activeView
        menuBar: nativeMenuBar
        popup: appMenu
        fileMenu: nativeFileMenu
        filePopup: filePopupMenu
        preferencesMenu: nativePreferencesMenu
        preferencesPopup: preferencesPopupMenu
        theme: appSettings.theme
        integrationEnabled: appSettings.menuIntegration
        onApplicationCommand: command => root.triggerHomeMenuAction(command)
        onCommandFailed: message => root.showPassiveNotification(message)
    }

    Platform.MenuBar {
        id: nativeMenuBar
        objectName: "nativeMenuBar"
        window: root
        // MenuBar resolves a null window to its parent during construction.
        // Install this binding afterwards so a saved disabled setting stays off.
        Component.onCompleted: Qt.callLater(() => {
            nativeMenuBar.window = Qt.binding(() => appSettings.menuIntegration ? root : null)
        })
        Platform.Menu {
            id: nativeFileMenu
            title: qsTr("&File")
            Platform.MenuSeparator { visible: figmaMenus.fileActionCount > 0 }
            Platform.MenuItem { text: qsTr("Home"); onTriggered: root.activateHome() }
            Platform.MenuItem { text: qsTr("New file tab"); onTriggered: root.openTab(root.newTabUrl) }
            Platform.MenuItem { text: qsTr("Export History"); onTriggered: root.openExportHistory() }
            Platform.MenuItem {
                text: qsTr("Close tab")
                enabled: root.activeIndex >= 0
                onTriggered: root.closeTab(root.activeIndex)
            }
            Platform.MenuSeparator { }
            Platform.MenuItem { text: qsTr("Quit"); onTriggered: Qt.quit() }
            Platform.MenuItem { text: qsTr("Reload page"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.triggerPageAction(CefView.Reload) }
            Platform.MenuItem { text: qsTr("About ReSketch…"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.openAbout() }
        }
        Platform.Menu {
            id: nativePreferencesMenu
            title: qsTr("&Preferences")
            Platform.MenuSeparator { visible: figmaMenus.preferencesActionCount > 0 }
            Platform.MenuItem { text: qsTr("Settings…"); onTriggered: root.openSettings() }
            Platform.MenuSeparator {}
            Platform.MenuItem { objectName: "nativeTaskManagerAction"; text: qsTr("Chromium Task Manager…"); onTriggered: root.openTaskManager() }
            Platform.MenuItem { objectName: "nativeDeveloperToolsAction"; text: qsTr("Developer Tools…"); enabled: !!root.activeView; onTriggered: root.openDeveloperTools() }
        }
    }

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.initialPage: Kirigami.Page {
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        background: Item { }

        header: Item {
            id: toolbarHost
            objectName: "toolbarHost"
            width: root.width
            height: root.toolbarAutoHidden ? 0 : root.tabStripHeight
            z: 100
            Rectangle {
                id: tabStrip
                objectName: "tabStrip"
                width: root.width
                height: root.tabStripHeight
                y: root.toolbarAutoHidden && !root.fullscreenToolbarHovered ? -height : 0
                Behavior on y {
                    enabled: !appSettings.reduceMotion
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0, 0.6, 0.15, 1, 1, 1]
                    }
                }
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b, root.toolbarAlpha)

                Row {
                    anchors.fill: parent
                    spacing: 0

                Controls.ToolButton {
                    id: homeButton
                    objectName: "homeButton"
                    width: 49
                    height: root.tabStripHeight
                    text: ""
                    Accessible.name: "Home"
                    Controls.ToolTip.text: qsTr("Home")
                    Controls.ToolTip.visible: hovered
                    readonly property bool selected: root.activeView === root.homeView
                    background: Rectangle {
                        property real hoverAmount: homeButton.hovered ? 1 : 0
                        Behavior on hoverAmount {
                            enabled: !appSettings.reduceMotion
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        color: homeButton.selected ? Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                              Kirigami.Theme.backgroundColor.g,
                                                              Kirigami.Theme.backgroundColor.b,
                                                              root.toolbarAlpha)
                                                   : hoverAmount > 0 ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                                  Kirigami.Theme.highlightColor.g,
                                                                                  Kirigami.Theme.highlightColor.b, 0.12 * hoverAmount)
                                                                        : "transparent"
                    }
                    contentItem: Item {
                        DragHandler {
                            target: null
                            acceptedButtons: Qt.LeftButton
                            onActiveChanged: {
                                if (active)
                                    root.startSystemMove()
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: homeButton.clicked()
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: toolbarContextMenu.popup(homeButton, 0, homeButton.height)
                        }

                        Kirigami.Icon {
                            width: root.tabIconSize
                            height: root.tabIconSize
                            anchors.centerIn: parent
                            source: "go-home"
                        }
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.2
                    }
                    onClicked: root.activateHome()
                }

                TabBarButton {
                    id: leftTabOverflow
                    width: root.tabStripOverflow ? 28 : 0
                    height: root.tabStripHeight - 1
                    visible: root.tabStripOverflow
                    dragWindow: root
                    dimmed: tabsViewport.contentX <= 1
                    icon.name: "go-previous"
                    icon.width: root.tabIconSize
                    icon.height: root.tabIconSize
                    Accessible.name: qsTr("More tabs to the left")
                    Controls.ToolTip.text: qsTr("More tabs to the left")
                    Controls.ToolTip.visible: hovered && !dimmed
                    onClicked: {
                        if (!dimmed)
                            tabsViewport.scrollBy(root.tabWidth)
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.2
                    }
                }

                Flickable {
                    id: tabsViewport
                    objectName: "tabsViewport"
                    property real wheelTargetX: 0
                    property bool smoothWheel: false
                    function scrollBy(distance, direct) {
                        const limit = Math.max(0, contentWidth - width)
                        const currentTarget = !direct && wheelScroll.running ? wheelTargetX : contentX
                        wheelTargetX = Math.max(0, Math.min(limit, currentTarget - distance))
                        smoothWheel = !direct && !appSettings.reduceMotion
                        if (!smoothWheel)
                            wheelScroll.stop()
                        contentX = wheelTargetX
                    }
                    width: Math.max(0, root.tabAreaWidth
                                       - leftTabOverflow.width - rightTabOverflow.width)
                    Behavior on width {
                        enabled: root.animatingCloseGap && !appSettings.reduceMotion
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                        }
                    }
                    height: root.tabStripHeight
                    contentWidth: tabBar.width
                    contentHeight: tabBar.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    onDraggingChanged: {
                        if (dragging) {
                            wheelScroll.stop()
                            smoothWheel = false
                            wheelTargetX = contentX
                        }
                    }

                    Behavior on contentX {
                        enabled: tabsViewport.smoothWheel
                        SmoothedAnimation {
                            id: wheelScroll
                            velocity: -1
                            duration: 130
                            maximumEasingTime: 75
                            onRunningChanged: {
                                if (!running)
                                    tabsViewport.smoothWheel = false
                            }
                        }
                    }

                    ScrollGestureArea {
                        enabled: tabsViewport.contentWidth > tabsViewport.width
                        flickable: tabsViewport
                        horizontal: true
                        wheelStep: root.tabWidth
                    }

                    Controls.TabBar {
                        id: tabBar
                        width: root.tabStripWidth
                        height: root.tabStripHeight
                        spacing: 0
                        padding: 0
                        background: Item { }
                        // The outer Flickable owns scrolling. KDE's default TabBar ListView
                        // applies an overlap and its own selection scrolling to variable-width slots.
                        Binding { target: tabBar.contentItem; property: "spacing"; value: 0 }
                        Binding { target: tabBar.contentItem; property: "interactive"; value: false }
                        Binding { target: tabBar.contentItem; property: "highlightRangeMode"; value: ListView.NoHighlightRange }

                        Repeater {
                            id: tabRepeater
                            model: tabModel
                            onItemAdded: Qt.callLater(root.processPendingClose)

                            Controls.TabButton {
                                id: tabButton
                                required property int index
                                required property string title
                                required property bool filePage
                                required property bool newFilePage
                                required property bool loading
                                required property int progress
                                required property bool animateOpen
                                required property var tabView
                                readonly property var group: root.groupFor(tabView)
                                readonly property real groupPrefix: root.tabGroupHeaderWidth(index)
                                readonly property bool selected: root.activeView === tabView
                                readonly property bool multiSelected: root.selectedTabViews.includes(tabView)
                                property bool closing: false
                                property bool closePending: false
                                property var closingView: null
                                property real closeDrop: 0
                                property real openRise: 0
                                property bool fillingClose: false
                                property real fillOffset: 0
                                readonly property real visualOffset: tabTranslate.x
                                width: root.tabSlotWidth(index)
                                leftPadding: groupPrefix
                                rightPadding: 0
                                height: root.tabStripHeight
                                z: closing || root.draggedGroupId === tabView.tabGroupId && tabView.tabGroupId !== ""
                                   ? 20 : tabDrag.active ? 10 : 0
                                transform: Translate {
                                    id: tabTranslate
                                    x: tabDrag.active ? tabDrag.activeTranslation.x
                                                      : tabButton.fillingClose ? tabButton.fillOffset
                                                      : root.tabPreviewOffset(tabButton.index)
                                    y: -tabButton.y + tabButton.closeDrop + tabButton.openRise

                                    Behavior on x {
                                        enabled: (root.draggedTabIndex >= 0 && root.tabDropIndex >= 0
                                                  || root.overviewDraggedView && root.overviewDropIndex >= 0
                                                  || root.draggedGroupId !== "")
                                                 && !tabDrag.active
                                                 && (!root.draggedGroupId || root.draggedGroupId !== tabButton.tabView.tabGroupId)
                                                 && !appSettings.reduceMotion
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                        }
                                    }
                                }
                                NumberAnimation {
                                    id: openToast
                                    target: tabButton
                                    property: "openRise"
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                    onFinished: root.finishTabOpening(tabButton.tabView)
                                }
                                Component.onCompleted: {
                                    tabView.tabStripItem = tabButton
                                    if (animateOpen) {
                                        tabModel.setProperty(index, "animateOpen", false)
                                        if (!appSettings.reduceMotion) {
                                            openRise = root.tabStripHeight
                                            openToast.start()
                                        } else
                                            root.finishTabOpening(tabView)
                                    }
                                }
                                Component.onDestruction: {
                                    if (tabView && tabView.tabStripItem === tabButton)
                                        tabView.tabStripItem = null
                                }
                                NumberAnimation {
                                    id: closeToast
                                    target: tabButton
                                    property: "closeDrop"
                                    to: root.tabStripHeight
                                    duration: 260
                                    easing.type: Easing.InOutQuad
                                    onFinished: {
                                        const view = tabButton.closingView
                                        Qt.callLater(() => root.finishClose(view))
                                    }
                                }
                                NumberAnimation {
                                    id: closeFill
                                    target: tabButton
                                    property: "fillOffset"
                                    to: 0
                                    duration: 220
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                    onFinished: tabButton.fillingClose = false
                                }
                                function startCloseFill(distance) {
                                    const remaining = fillingClose ? fillOffset : 0
                                    closeFill.stop()
                                    fillOffset = remaining + distance
                                    fillingClose = true
                                    closeFill.start()
                                }
                                function startReorderFill(distance) {
                                    closeFill.stop()
                                    fillOffset = distance
                                    fillingClose = true
                                    closeFill.start()
                                }
                                function startClose() {
                                    if (closing)
                                        return
                                    closingView = tabView
                                    closing = true
                                    if (appSettings.reduceMotion)
                                        root.finishClose(closingView)
                                    else
                                        closeToast.start()
                                }
                                text: ""
                                Accessible.name: title
                                checkable: false
                                checked: selected
                                opacity: selected || multiSelected ? 1 : 0.7
                                background: Rectangle {
                                    x: tabButton.groupPrefix
                                    width: Math.max(0, tabButton.width - tabButton.groupPrefix)
                                    visible: tabButton.tabView.groupExpansion > 0.001
                                    property real hoverAmount: tabButton.hovered ? 1 : 0
                                    Behavior on hoverAmount {
                                        enabled: !appSettings.reduceMotion
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                    color: tabButton.selected ? Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                                        Kirigami.Theme.backgroundColor.g,
                                                                        Kirigami.Theme.backgroundColor.b,
                                                                        root.toolbarAlpha)
                                                              : hoverAmount > 0 ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                                             Kirigami.Theme.highlightColor.g,
                                                                                             Kirigami.Theme.highlightColor.b, 0.12 * hoverAmount)
                                                                                  : "transparent"

                                    Rectangle {
                                        objectName: "tabSelectionTint"
                                        anchors.fill: parent
                                        color: root.selectionTint
                                        visible: tabButton.multiSelected
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: tabButton.selected && tabButton.index !== 0 ? 0.2 : 0
                                        Behavior on opacity {
                                            enabled: !appSettings.reduceMotion
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: Kirigami.Theme.textColor
                                        opacity: tabButton.selected ? 0.2 : 0
                                        Behavior on opacity {
                                            enabled: !appSettings.reduceMotion
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }
                                onClicked: {
                                    if (!closing && !closePending && !tabTap.pointerClick)
                                        root.selectFileTabs(tabView, Qt.NoModifier)
                                }

                                TapHandler {
                                    id: tabTap
                                    acceptedButtons: Qt.LeftButton
                                    property bool pointerClick: false
                                    onPressedChanged: {
                                        if (pressed) pointerClick = true
                                        else Qt.callLater(() => pointerClick = false)
                                    }
                                    onTapped: eventPoint => {
                                        if (!tabButton.closing && !tabButton.closePending
                                                && eventPoint.position.x < closeTabButton.mapToItem(tabButton, 0, 0).x)
                                            root.selectFileTabs(tabButton.tabView, point.modifiers)
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.MiddleButton
                                    enabled: false
                                    property var pressedView: null
                                    onPressedChanged: {
                                        if (pressed)
                                            pressedView = tabButton.tabView
                                    }
                                    onTapped: {
                                        const target = pressedView || tabButton.tabView
                                        pressedView = null
                                        Qt.callLater(() => root.closeTabByMiddleClick(target))
                                    }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: tabContextMenu.popup()
                                }

                                Controls.Menu {
                                    id: tabContextMenu
                                    TabGroupMenu { appWindow: root; tabView: tabButton.tabView }
                                    Controls.MenuItem {
                                        text: qsTr("Move to new window")
                                        enabled: !!tabButton.tabView
                                                 && root.views.length > 1
                                                 && Policy.isFigmaUrl(tabButton.tabView.tabUrl)
                                        onTriggered: {
                                            const target = tabButton.tabView
                                            Qt.callLater(() => root.moveTabToNewWindow(root.views.indexOf(target)))
                                        }
                                    }
                                    Controls.MenuItem {
                                        text: root.tabsForAction(tabButton.tabView).length > 1 ? qsTr("Close selected tabs") : qsTr("Close")
                                        onTriggered: {
                                            const target = tabButton.tabView
                                            Qt.callLater(() => root.closeSelectedTabs(target))
                                        }
                                    }
                                    Controls.MenuItem {
                                        text: qsTr("Refresh")
                                        enabled: !root.allFrozen
                                        onTriggered: root.refreshSelectedTabs(tabButton.tabView)
                                    }
                                    Controls.MenuItem {
                                        text: qsTr("Copy URL")
                                        enabled: !!tabButton.tabView
                                                 && Policy.isFigmaUrl(tabButton.tabView.tabUrl)
                                        onTriggered: appSettings.copyToClipboard(String(tabButton.tabView.tabUrl))
                                    }
                                }

                                contentItem: Item {
                                    clip: true
                                    visible: tabButton.tabView.groupExpansion > 0.001
                                    Item {
                                        width: root.tabWidth
                                        height: parent.height
                                        Kirigami.Icon {
                                            width: root.tabIconSize
                                            height: root.tabIconSize
                                            anchors.left: parent.left
                                            anchors.leftMargin: root.tabContentLeftMargin
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: tabButton.filePage ? "text-x-generic" : "go-home"
                                            visible: !tabButton.loading
                                        }

                                        Kirigami.Icon {
                                            id: loadingIcon
                                            width: root.tabIconSize
                                            height: root.tabIconSize
                                            anchors.left: parent.left
                                            anchors.leftMargin: root.tabContentLeftMargin
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "view-refresh"
                                            visible: tabButton.loading
                                            RotationAnimation on rotation {
                                                from: 0
                                                to: 360
                                                duration: 900
                                                loops: Animation.Infinite
                                                running: loadingIcon.visible && !appSettings.reduceMotion
                                                onRunningChanged: {
                                                    if (!running)
                                                        loadingIcon.rotation = 0
                                                }
                                            }
                                        }

                                        Controls.Label {
                                            anchors.left: loadingIcon.right
                                            anchors.leftMargin: Kirigami.Units.smallSpacing
                                            anchors.right: closeTabButton.left
                                            anchors.rightMargin: Kirigami.Units.smallSpacing
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Policy.tabTitle(tabButton.title)
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignLeft
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        TabBarButton {
                                            id: closeTabButton
                                            property var pressedView: null
                                            width: root.tabStripHeight
                                            height: root.tabStripHeight
                                            icon.name: "window-close"
                                            icon.width: root.tabIconSize
                                            icon.height: root.tabIconSize
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            Accessible.name: "Close " + tabButton.title
                                            Controls.ToolTip.text: Accessible.name
                                            Controls.ToolTip.visible: hovered
                                            onPressedChanged: {
                                                if (pressed)
                                                    pressedView = tabButton.tabView
                                            }
                                            onClicked: {
                                                const target = pressedView || tabButton.tabView
                                                pressedView = null
                                                root.closeTab(root.views.indexOf(target))
                                            }
                                        }

                                        Item {
                                            anchors.left: parent.left
                                            anchors.right: closeTabButton.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom

                                            DragHandler {
                                                id: tabDrag
                                                enabled: !tabButton.closing && !tabButton.closePending
                                                target: null
                                                acceptedButtons: Qt.LeftButton
                                                onActiveChanged: {
                                                    if (active) {
                                                        if (tabButton.selected) {
                                                            selectionGlide.stop()
                                                            root.homeSelectionGlide = false
                                                            selectionBar.startOffset = 0
                                                            selectionBar.endOffset = 0
                                                        }
                                                        root.draggedTabIndex = tabButton.index
                                                        root.tabDropIndex = tabButton.index
                                                        root.tabDropGroupId = tabButton.tabView.tabGroupId
                                                        root.beginItemDrag(tabButton.tabView, tabButton.contentItem, centroid.scenePosition)
                                                    } else if (root.draggedTabIndex >= 0) {
                                                        const point = centroid.scenePosition
                                                        if (root.outsideWindow(point)) {
                                                            root.draggedTabIndex = -1
                                                            root.tabDropIndex = -1
                                                            root.finishItemDrag(point)
                                                            return
                                                        }
                                                        const members = root.dragViews.slice()
                                                        root.cancelItemDrag()
                                                        const source = root.draggedTabIndex
                                                        const destination = root.tabDropIndex
                                                        const groupId = root.tabDropGroupId
                                                        const positions = root.captureTabStripPositions()
                                                        root.draggedTabIndex = -1
                                                        root.tabDropIndex = -1
                                                        root.reorderTab(source, destination, positions, false, groupId, members)
                                                    }
                                                }
                                                onActiveTranslationChanged: {
                                                    if (active) {
                                                        root.tabDropIndex = root.tabDropTarget(root.tabStripTabPosition(root.draggedTabIndex)
                                                                             + activeTranslation.x,
                                                                             tabsViewport.contentItem.mapFromItem(root.contentItem, centroid.scenePosition.x, centroid.scenePosition.y).x)
                                                        root.updateItemDrag(centroid.scenePosition)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    objectName: "tabGroupBorder"
                                    x: tabButton.groupPrefix
                                    anchors.bottom: parent.bottom
                                    width: Math.max(0, parent.width - x)
                                    height: 2
                                    visible: !!tabButton.group && tabButton.tabView.groupExpansion > 0.001
                                    color: tabButton.group ? tabButton.group.color : "transparent"
                                }

                            }
                        }
                    }

                    Repeater {
                        id: groupHeaderRepeater
                        model: root.tabGroups.length
                        TabBarButton {
                            id: groupHeader
                            required property int index
                            readonly property var group: root.tabGroups[index]
                            readonly property int firstIndex: group ? root.views.findIndex(view => view.tabGroupId === group.id) : -1
                            x: root.groupHeaderPosition(groupHeader.group?.id || "")
                            property real releaseOffset: 0
                            property bool settling: false
                            transform: Translate { x: groupHeader.releaseOffset }
                            function settleFrom(position) {
                                groupHeaderSettle.stop()
                                releaseOffset = position - x
                                if (!appSettings.reduceMotion && Math.abs(releaseOffset) > 0.5) {
                                    settling = true
                                    groupHeaderSettle.start()
                                } else {
                                    releaseOffset = 0
                                    settling = false
                                }
                            }
                            NumberAnimation {
                                id: groupHeaderSettle
                                target: groupHeader
                                property: "releaseOffset"
                                to: 0
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                onFinished: groupHeader.settling = false
                            }
                            y: 0
                            Behavior on x {
                                enabled: !appSettings.reduceMotion && !root.groupAnimationRunning
                                         && root.draggedGroupId !== groupHeader.group?.id
                                         && !groupHeader.settling
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                }
                            }
                            objectName: "tabGroupHeader"
                            width: root.groupHeaderWidth
                            height: root.tabStripHeight
                            visible: firstIndex >= 0
                            z: root.draggedGroupId === groupHeader.group?.id ? 25 : 5
                            dragWindow: root
                            Accessible.name: groupHeader.group ? groupHeader.group.title : ""
                            Controls.ToolTip.text: Accessible.name
                            Controls.ToolTip.visible: hovered
                            contentItem: Row {
                                spacing: 6
                                leftPadding: 10
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !groupHeader.group?.icon || groupHeader.group.icon === "folder"
                                    width: 8; height: 8; radius: 4
                                    color: groupHeader.group ? groupHeader.group.color : "transparent"
                                }
                                Kirigami.Icon {
                                    objectName: "tabGroupCustomIcon"
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!groupHeader.group?.icon && groupHeader.group.icon !== "folder"
                                    width: root.tabIconSize; height: width
                                    source: groupHeader.group?.icon || "folder"
                                    color: groupHeader.group?.color || Kirigami.Theme.highlightColor
                                }
                                Controls.Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.groupHeaderWidth - 54
                                    text: groupHeader.group ? groupHeader.group.title : ""
                                    elide: Text.ElideRight
                                }
                                Kirigami.Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14; height: 14
                                    objectName: "tabGroupArrow"
                                    source: groupHeader.group?.collapsed ? "arrow-right" : "arrow-left"
                                }
                            }
                            property int clickModifiers: Qt.NoModifier
                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onPressedChanged: if (pressed) groupHeader.clickModifiers = point.modifiers
                            }
                            onClicked: {
                                const modifiers = clickModifiers
                                clickModifiers = Qt.NoModifier
                                if (!groupLabelDrag.active && !suppressClick
                                        && !root.selectGroupForAction(groupHeader.group.id, modifiers))
                                    root.updateTabGroup(groupHeader.group.id, {collapsed: !groupHeader.group.collapsed})
                            }
                            background: Rectangle {
                                property real hoverAmount: groupHeader.hovered ? 1 : 0
                                Behavior on hoverAmount {
                                    enabled: !appSettings.reduceMotion
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                                color: root.selectedGroupIds.includes(groupHeader.group?.id) ? root.selectionTint
                                       : hoverAmount > 0 ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                             Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12 * hoverAmount)
                                       : "transparent"
                            }
                            property bool suppressClick: false
                            DragHandler {
                                id: groupLabelDrag
                                objectName: "tabGroupDrag"
                                target: null
                                acceptedButtons: Qt.LeftButton
                                onActiveChanged: {
                                    if (active) {
                                        groupHeaderSettle.stop()
                                        groupHeader.releaseOffset = 0
                                        selectionGlide.stop()
                                        selectionBar.startOffset = 0
                                        selectionBar.endOffset = 0
                                        root.homeSelectionGlide = false
                                        groupHeader.suppressClick = true
                                        root.draggedGroupId = groupHeader.group.id
                                        root.groupDragOffset = 0
                                        root.groupDropIndex = groupHeader.firstIndex
                                    } else if (root.draggedGroupId === groupHeader.group?.id) {
                                        const positions = root.captureTabStripPositions()
                                        const id = root.draggedGroupId
                                        const destination = root.groupDropIndex
                                        const labelPosition = groupHeader.x + groupHeader.releaseOffset
                                        groupHeader.settling = true
                                        root.draggedGroupId = ""
                                        root.groupDropIndex = -1
                                        root.groupDragOffset = 0
                                        root.moveTabGroup(id, destination, positions)
                                        groupHeader.settleFrom(labelPosition)
                                        Qt.callLater(() => groupHeader.suppressClick = false)
                                    }
                                }
                                onActiveTranslationChanged: {
                                    if (!active) return
                                    root.groupDragOffset = activeTranslation.x
                                    const point = tabsViewport.contentItem.mapFromItem(root.contentItem,
                                        centroid.scenePosition.x, centroid.scenePosition.y)
                                    root.groupDropIndex = root.groupDropTarget(point.x)
                                }
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: eventPoint => root.showGroupContextMenu(groupHeader.group.id, groupHeader, eventPoint.position)
                            }
                            Rectangle {
                                objectName: "tabGroupHeaderBorder"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                color: groupHeader.group ? groupHeader.group.color : "transparent"
                            }
                        }
                    }

                    Rectangle {
                        x: root.tabStripPosition(root.tabDropIndex + (root.tabDropIndex > root.draggedTabIndex ? 1 : 0)) - width / 2
                        width: 3
                        height: root.tabStripHeight
                        z: 20
                        visible: root.tabDropIndex >= 0 && root.tabDropIndex !== root.draggedTabIndex
                        color: Kirigami.Theme.highlightColor
                    }
                }

                TabBarButton {
                    id: rightTabOverflow
                    width: root.tabStripOverflow ? 28 : 0
                    height: root.tabStripHeight - 1
                    visible: root.tabStripOverflow
                    dragWindow: root
                    dimmed: tabsViewport.contentX >= tabsViewport.contentWidth
                                                   - tabsViewport.width - 1
                    icon.name: "go-next"
                    icon.width: root.tabIconSize
                    icon.height: root.tabIconSize
                    Accessible.name: qsTr("More tabs to the right")
                    Controls.ToolTip.text: qsTr("More tabs to the right")
                    Controls.ToolTip.visible: hovered && !dimmed
                    onClicked: {
                        if (!dimmed)
                            tabsViewport.scrollBy(-root.tabWidth)
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.2
                    }
                }

                Row {
                    id: toolbarActions
                    objectName: "toolbarActions"
                    height: root.tabStripHeight
                    Repeater {
                        model: appSettings.toolbarItems.filter(item => item.enabled)
                        TabBarButton {
                            id: toolbarButton
                            required property var modelData
                            objectName: "toolbarButton-" + modelData.id
                            animatePress: true
                            pressedTint: root.selectionTint
                            reduceMotion: appSettings.reduceMotion
                            dragWindow: root
                            width: 40
                            height: root.tabStripHeight
                            icon.name: modelData.icon
                            icon.width: root.tabIconSize
                            icon.height: root.tabIconSize
                            dimmed: modelData.id === "refresh" ? !root.activeView || root.allFrozen
                                  : modelData.id === "overview" ? !root.homeView && !root.overviewVisible
                                  : modelData.id === "developer-tools" ? !root.activeView : false
                            Accessible.name: modelData.title
                            Controls.ToolTip.text: modelData.title
                            Controls.ToolTip.visible: hovered
                            onClicked: if (!dimmed) root.triggerToolbarItem(modelData.id, toolbarButton)
                        }
                    }

                    Controls.Menu {
                        id: appMenu
                        objectName: "applicationPopupMenu"
                        onAboutToShow: figmaMenus.refresh()

                        Controls.Menu {
                            id: filePopupMenu
                            title: qsTr("File")
                            Controls.MenuSeparator { visible: figmaMenus.fileActionCount > 0 }
                            Controls.MenuItem { text: qsTr("Home"); onTriggered: root.activateHome() }
                            Controls.MenuItem { text: qsTr("New file tab"); onTriggered: root.openTab(root.newTabUrl) }
                            Controls.MenuItem { text: qsTr("Export History"); onTriggered: root.openExportHistory() }
                            Controls.MenuItem {
                                text: qsTr("Close tab")
                                enabled: root.activeIndex >= 0
                                onTriggered: root.closeTab(root.activeIndex)
                            }
                            Controls.MenuSeparator { }
                            Controls.MenuItem { text: qsTr("Quit"); onTriggered: Qt.quit() }
                            Controls.MenuItem { text: qsTr("Reload page"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.triggerPageAction(CefView.Reload) }
                            Controls.MenuItem { text: qsTr("About ReSketch…"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.openAbout() }
                        }
                        Controls.Menu {
                            id: preferencesPopupMenu
                            title: qsTr("Preferences")
                            Controls.MenuSeparator { visible: figmaMenus.preferencesActionCount > 0 }
                            Controls.MenuItem { text: qsTr("Settings…"); onTriggered: root.openSettings() }
                            Controls.MenuSeparator {}
                            Controls.MenuItem { objectName: "taskManagerAction"; text: qsTr("Chromium Task Manager…"); onTriggered: root.openTaskManager() }
                            Controls.MenuItem { objectName: "developerToolsAction"; text: qsTr("Developer Tools…"); enabled: !!root.activeView; onTriggered: root.openDeveloperTools() }
                        }
                    }
                }

                WindowControls {
                    id: windowControlGroup
                    targetWindow: root
                    buttonSize: root.tabStripHeight
                    iconSize: root.tabIconSize
                }
                }

                MouseArea {
                    id: blankTabStripDrag
                    objectName: "blankTabStripDrag"
                    x: tabsViewport.x + Math.min(tabsViewport.width,
                                                 Math.max(0, tabsViewport.contentWidth
                                                                - tabsViewport.contentX))
                    y: 0
                    z: 8
                    width: Math.max(0, tabsViewport.x + tabsViewport.width - x)
                    height: root.tabStripHeight - 1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            toolbarContextMenu.popup(blankTabStripDrag, mouse.x, mouse.y)
                    }
                    onDoubleClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) root.toggleMaximize()
                    }
                    DragHandler {
                        target: null
                        acceptedButtons: Qt.LeftButton
                        onActiveChanged: {
                            if (active)
                                root.startSystemMove()
                        }
                    }
                }

                Item {
                    width: homeButton.width + leftTabOverflow.width + tabsViewport.width
                           + rightTabOverflow.width
                    height: 3
                    z: 15
                    clip: true

                    Item {
                        id: selectionBar
                        objectName: "selectionBar"
                        property real startOffset: 0
                        property real endOffset: 0
                        readonly property var currentTab: root.activeView?.tabStripItem || null
                        readonly property var group: root.groupFor(root.activeView)
                        readonly property real expansion: group ? root.activeView.groupExpansion : 1
                        readonly property real tabX: root.tabStripTabPosition(root.activeIndex)
                                                     + (currentTab?.visualOffset || 0)
                        readonly property real groupX: group ? root.groupHeaderVisualPosition(group.id) : tabX
                        readonly property real targetX: root.activeIndex < 0 ? 0
                                                        : tabsViewport.x - tabsViewport.contentX
                                                          + tabX * expansion + groupX * (1 - expansion)
                        readonly property real targetWidth: root.activeIndex < 0 ? homeButton.width - 1
                                                            : root.tabWidth * expansion + root.groupHeaderWidth * (1 - expansion)
                        x: targetX + startOffset
                        width: Math.max(0, targetWidth + endOffset - startOffset)
                        height: 3
                        visible: !!root.activeView && !root.hideHeldSelection
                                 && (!currentTab || currentTab.index !== root.activeIndex
                                     || !currentTab.closing)
                    }

                    Item {
                        width: homeButton.width - 1
                        height: 3
                        clip: true
                        visible: root.activeIndex < 0 || root.homeSelectionGlide

                        Rectangle {
                            x: selectionBar.x
                            width: selectionBar.width
                            height: 3
                            visible: selectionBar.visible
                            color: Kirigami.Theme.highlightColor
                        }
                    }

                    Item {
                        x: tabsViewport.x
                        width: tabsViewport.width
                        height: 3
                        clip: true

                        Rectangle {
                            x: selectionBar.x - tabsViewport.x
                            width: selectionBar.width
                            height: 3
                            visible: selectionBar.visible
                            color: Kirigami.Theme.highlightColor
                        }
                    }

                    SequentialAnimation {
                        id: selectionGlide
                        onRunningChanged: {
                            if (!running)
                                root.homeSelectionGlide = false
                        }
                        onFinished: Qt.callLater(root.processPendingClose)
                        NumberAnimation {
                            id: selectionStretch
                            target: selectionBar
                            to: 0
                            duration: 150
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                        }
                        NumberAnimation {
                            id: selectionContract
                            target: selectionBar
                            to: 0
                            duration: 150
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.2
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: root.activeView
                           ? Math.max(4, parent.width * Math.min(100, root.activeView.loadProgress) / 100)
                           : 0
                    height: 2
                    z: 2
                    visible: !!root.activeView && root.activeView.loading
                    color: Kirigami.Theme.highlightColor

                    Behavior on width {
                        enabled: !appSettings.reduceMotion
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                        }
                    }
                }
            }
        }

        Item {
            id: browserArea
            anchors.fill: parent
            clip: true

            Rectangle {
                objectName: "browserBackground"
                anchors.fill: parent
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b,
                               root.desktopSidebars && root.chromiumFrameLoaded
                               ? root.toolbarAlpha + (1 - root.toolbarAlpha) * root.overviewSidebarBackdrop
                               : root.toolbarAlpha)
            }

            Rectangle {
                anchors.fill: parent
                z: 100
                visible: root.allFrozen
                color: Kirigami.Theme.backgroundColor

                Column {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing

                    Controls.Label {
                        text: appSettings.keepHomeAwake ? qsTr("File tabs are frozen") : qsTr("All tabs are frozen")
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Controls.Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Wake current tab"
                        onClicked: root.wakeCurrentTab()
                    }
                }
            }

            Item {
                id: overviewOverlay
                anchors.fill: parent
                z: 40
                visible: root.overviewVisible
                Keys.onPressed: event => root.handleOverviewInput(event)

                Flickable {
                    id: overviewFlickable
                    objectName: "overviewFlickable"
                    property real wheelTargetY: 0
                    property bool smoothWheel: false
                    function scrollBy(distance, direct) {
                        const limit = Math.max(0, contentHeight - height)
                        const currentTarget = !direct && overviewWheelScroll.running
                                              ? wheelTargetY : contentY
                        wheelTargetY = Math.max(0, Math.min(limit, currentTarget - distance))
                        smoothWheel = !direct && !appSettings.reduceMotion
                        if (!smoothWheel)
                            overviewWheelScroll.stop()
                        contentY = wheelTargetY
                    }
                    function resetScroll(position = 0) {
                        overviewWheelScroll.stop()
                        cancelFlick()
                        smoothWheel = false
                        wheelTargetY = Math.max(0, Math.min(position, contentHeight - height))
                        contentY = wheelTargetY
                    }
                    anchors.fill: parent
                    z: root.overviewDraggedView || (root.overviewSelectedView
                       && (root.overviewClosing || root.overviewProgress < 0.999)) ? 10 : 0
                    interactive: !overviewSelectionArea.pressed && !root.overviewDraggedView && !root.overviewDraggedGroupId
                    contentWidth: width
                    contentHeight: root.overviewLayout.height
                    onContentHeightChanged: {
                        const limit = Math.max(0, contentHeight - height)
                        if (contentY > limit) resetScroll(limit)
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    clip: true
                    onDraggingChanged: {
                        if (dragging) {
                            overviewWheelScroll.stop()
                            smoothWheel = false
                            wheelTargetY = contentY
                        }
                    }

                    Behavior on contentY {
                        enabled: overviewFlickable.smoothWheel
                        SmoothedAnimation {
                            id: overviewWheelScroll
                            velocity: -1
                            duration: 130
                            maximumEasingTime: 75
                            onRunningChanged: {
                                if (!running)
                                    overviewFlickable.smoothWheel = false
                            }
                        }
                    }

                    ScrollGestureArea {
                        enabled: overviewFlickable.contentHeight > overviewFlickable.height
                        flickable: overviewFlickable
                        wheelStep: Math.max(220, Math.min(320, root.overviewCardHeight + root.overviewGap))
                    }

                    MouseArea {
                        id: overviewSelectionArea
                        objectName: "overviewSelectionArea"
                        width: overviewFlickable.width
                        height: Math.max(overviewFlickable.height, overviewFlickable.contentHeight)
                        z: -1
                        enabled: root.overviewProgress >= 0.999 && !root.overviewClosing
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        property point startPoint
                        property point endPoint
                        property var initialSelection: []
                        readonly property rect selectionRectangle: Qt.rect(
                            Math.min(startPoint.x, endPoint.x), Math.min(startPoint.y, endPoint.y),
                            Math.abs(endPoint.x - startPoint.x), Math.abs(endPoint.y - startPoint.y))
                        onPressed: mouse => {
                            overviewFlickable.cancelFlick()
                            root.rangeSelectionAnchor = null
                            root.rangeSelectionBase = []
                            root.overviewRangeAnchor = null
                            initialSelection = (mouse.modifiers & Qt.ShiftModifier) ? root.selectedTabViews.slice() : []
                            root.selectedTabViews = initialSelection
                            startPoint = Qt.point(mouse.x, mouse.y)
                            endPoint = startPoint
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return
                            endPoint = Qt.point(mouse.x, mouse.y)
                            root.selectOverviewRectangle(selectionRectangle, initialSelection)
                        }
                    }
                    Rectangle {
                        objectName: "overviewSelectionBox"
                        x: overviewSelectionArea.selectionRectangle.x
                        y: overviewSelectionArea.selectionRectangle.y
                        width: overviewSelectionArea.selectionRectangle.width
                        height: overviewSelectionArea.selectionRectangle.height
                        visible: overviewSelectionArea.pressed && (width > 3 || height > 3)
                        z: 30
                        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                                       Kirigami.Theme.highlightColor.b, 0.15)
                        border.width: 1
                        border.color: Kirigami.Theme.highlightColor
                    }

                    Repeater {
                        id: overviewGroupRepeater
                        model: root.tabGroups.length
                        onItemAdded: root.overviewGroupGeneration++
                        onItemRemoved: root.overviewGroupGeneration++
                        Rectangle {
                            id: groupContainer
                            objectName: "overviewGroupContainer"
                            required property int index
                            readonly property var group: root.tabGroups[index]
                            readonly property color accentColor: group?.color || Kirigami.Theme.highlightColor
                            readonly property var region: root.overviewLayout.groups.find(item => item.id === group?.id)
                            property alias cardArea: groupCardArea
                            property alias selectionHeader: groupOverviewHeader
                            property alias expandedArea: groupExpandedArea
                            readonly property real headerHeight: root.overviewCardHeight
                            readonly property var members: root.views.filter(view => view.tabGroupId === group?.id
                                                                                   && !view.overviewClosingCard)
                            property bool collapsing: false
                            property bool expanding: false
                            readonly property bool transitioning: collapsing || expanding
                            property real expansion: group?.overviewCollapsed ? 0 : 1
                            property string animationGroupId: ""
                            onGroupChanged: {
                                if (transitioning && group?.id !== animationGroupId) {
                                    groupTransition.stop()
                                    collapsing = false
                                    expanding = false
                                }
                                if (!transitioning) expansion = group?.overviewCollapsed ? 0 : 1
                            }
                            readonly property bool dragging: root.overviewDraggedGroupId === group?.id
                            property bool settling: false
                            property real dragOffsetX: 0
                            property real dragOffsetY: 0
                            property real dragOriginX: 0
                            property real dragOriginY: 0
                            property real dragBodyOriginX: 0
                            property real dragBodyOriginY: 0
                            z: dragging || settling ? 20 : transitioning ? 15 : 0
                            transform: Translate { x: groupContainer.dragOffsetX; y: groupContainer.dragOffsetY }
                            x: dragging ? dragOriginX : region?.x ?? root.overviewMargin
                            y: dragging ? dragOriginY : region?.y ?? 0
                            width: root.overviewCardWidth
                            height: root.overviewCardHeight
                            visible: !!region
                            color: Qt.tint(Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                   Kirigami.Theme.backgroundColor.g,
                                                   Kirigami.Theme.backgroundColor.b, 0.35),
                                           Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.045))
                            radius: Kirigami.Units.smallSpacing + 3
                            border.width: 1
                            border.color: group?.color || "transparent"
                            Behavior on x {
                                enabled: root.overviewProgress >= 0.999 && !transitioning && !dragging && !settling && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                enabled: root.overviewProgress >= 0.999 && !root.overviewGroupAnimationRunning && !dragging && !settling && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            function previewSource(view) {
                                return groupPreviewGrid.children.find(cell => cell.previewView === view)?.frameHost ?? null
                            }
                            function animateCollapsed(collapsed) {
                                animationGroupId = group.id
                                groupTransition.stop()
                                collapsing = collapsed
                                expanding = !collapsed
                                if (!collapsed) root.updateTabGroup(group.id, {overviewCollapsed: false}, true)
                                groupTransition.from = expansion
                                groupTransition.to = collapsed ? 0 : 1
                                groupTransition.duration = Math.max(1, Math.round(260 * Math.abs(groupTransition.to - expansion)))
                                groupTransition.start()
                            }
                            NumberAnimation {
                                id: groupTransition
                                target: groupContainer
                                property: "expansion"
                                easing.type: Easing.OutCubic
                                onFinished: {
                                    root.updateTabGroup(groupContainer.group.id,
                                        {overviewCollapsed: groupContainer.collapsing}, true)
                                    groupContainer.collapsing = false
                                    groupContainer.expanding = false
                                }
                            }
                            Item {
                                id: groupExpandedArea
                                objectName: "overviewGroupExpandedArea"
                                parent: overviewFlickable.contentItem
                                property real releaseOffsetX: 0
                                property real releaseOffsetY: 0
                                readonly property real motionY: -50 * (1 - groupContainer.expansion)
                                x: (groupContainer.dragging ? groupContainer.dragBodyOriginX
                                    : groupContainer.region?.body?.x ?? root.overviewMargin - 10)
                                   + groupContainer.dragOffsetX + releaseOffsetX
                                y: (groupContainer.dragging ? groupContainer.dragBodyOriginY
                                    : groupContainer.region?.body?.y ?? 0)
                                   + groupContainer.dragOffsetY + releaseOffsetY
                                width: overviewFlickable.width - 2 * (root.overviewMargin - 10)
                                height: groupContainer.region?.body?.height ?? 0
                                visible: groupContainer.visible && (groupContainer.expansion > 0 || groupContainer.transitioning)
                                z: groupContainer.z
                                clip: true
                                Behavior on y {
                                    enabled: root.overviewProgress >= 0.999 && !root.overviewGroupAnimationRunning
                                             && !groupContainer.dragging && !groupContainer.settling && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                                Behavior on height {
                                    enabled: root.overviewProgress >= 0.999 && !root.overviewGroupAnimationRunning && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                                Rectangle {
                                    width: parent.width; height: parent.height
                                    y: groupExpandedArea.motionY
                                    radius: Kirigami.Units.smallSpacing + 8
                                    color: Qt.rgba(groupContainer.accentColor.r, groupContainer.accentColor.g,
                                                   groupContainer.accentColor.b, 0.045 * groupContainer.expansion)
                                    border.width: 1
                                    border.color: Qt.rgba(groupContainer.accentColor.r, groupContainer.accentColor.g,
                                                          groupContainer.accentColor.b, groupContainer.expansion)
                                    Item {
                                        id: groupCardArea
                                        objectName: "overviewGroupCardArea"
                                        x: 10; y: 10
                                        width: parent.width - 20
                                        height: Math.max(0, parent.height - 20)
                                        clip: true
                                    }
                                }
                            }
                            Item {
                                id: groupOverviewHeader
                                objectName: "overviewGroupHeader"
                                width: parent.width
                                height: parent.height
                                Rectangle {
                                    objectName: "overviewGroupNavigationHighlight"
                                    anchors.fill: parent
                                    z: 3
                                    radius: groupContainer.radius
                                    property real hoverAmount: groupOverviewMouse.containsMouse ? 1 : 0
                                    Behavior on hoverAmount {
                                        enabled: !appSettings.reduceMotion
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                    color: groupContainer.members.some(view => root.selectedTabViews.includes(view)) ? root.selectionTint
                                           : hoverAmount > 0 ? Qt.rgba(root.selectionTint.r, root.selectionTint.g,
                                                                      root.selectionTint.b, root.selectionTint.a * hoverAmount)
                                                             : "transparent"
                                    border.width: groupContainer.group?.overviewCollapsed
                                                  && groupContainer.members.includes(root.activeView) ? 2 : 0
                                    border.color: Kirigami.Theme.highlightColor
                                    visible: color.a > 0 || border.width > 0
                                }
                                Kirigami.Icon {
                                    objectName: "overviewGroupIcon"
                                    x: 14; y: (60 - height) / 2
                                    width: root.tabIconSize; height: width
                                    source: groupContainer.group?.icon || "folder"
                                    color: groupContainer.accentColor
                                }
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 38
                                    y: (60 - height) / 2
                                    width: parent.width - 52
                                    spacing: 3
                                    Controls.Label {
                                        objectName: "overviewGroupTitle"
                                        width: parent.width
                                        text: groupContainer.group?.title || ""
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Controls.Label {
                                        objectName: "overviewGroupCount"
                                        text: groupContainer.members.length === 1 ? qsTr("1 tab")
                                              : qsTr("%1 tabs").arg(groupContainer.members.length)
                                        opacity: 0.7
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                                Item {
                                    id: groupPreviewClip
                                    objectName: "overviewGroupPreviewClip"
                                    x: 12; y: 60
                                    width: parent.width - 24
                                    height: Math.max(0, parent.height - y - 12)
                                    clip: true
                                    Item {
                                        id: groupPreviewGrid
                                        objectName: "overviewGroupPreviewGrid"
                                        width: parent.width; height: parent.height
                                        y: 50 * groupContainer.expansion
                                        opacity: 1 - groupContainer.expansion
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                id: groupPreviewCell
                                                objectName: "overviewGroupPreviewCell"
                                                required property int index
                                                readonly property var previewView: index < 3 ? groupContainer.members[index] ?? null : null
                                                property alias frameHost: groupPreviewHost
                                                onPreviewViewChanged: if (root.overviewVisible) Qt.callLater(root.syncOverviewFrames)
                                                readonly property bool overflow: index === 3 && groupContainer.members.length > 3
                                                readonly property bool placeholder: !previewView && !overflow
                                                x: index % 2 * (width + 8)
                                                y: Math.floor(index / 2) * (height + 8)
                                                width: Math.max(1, (groupPreviewGrid.width - 8) / 2)
                                                height: Math.max(1, (groupPreviewGrid.height - 8) / 2)
                                                radius: Kirigami.Units.smallSpacing + 3
                                                color: placeholder ? "transparent" : Kirigami.Theme.backgroundColor
                                                border.width: 1
                                                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                                      Kirigami.Theme.textColor.b, 0.25)
                                                clip: true
                                                layer.enabled: !!previewView && root.overviewVisible
                                                layer.effect: MultiEffect {
                                                    autoPaddingEnabled: false
                                                    maskEnabled: true
                                                    maskSource: groupPreviewMask
                                                    maskThresholdMin: 0.5
                                                    maskSpreadAtMin: 1.0
                                                }
                                                Rectangle {
                                                    id: groupPreviewMask
                                                    parent: browserArea
                                                    width: groupPreviewCell.width; height: groupPreviewCell.height
                                                    radius: groupPreviewCell.radius
                                                    color: "white"
                                                    antialiasing: true
                                                    visible: false
                                                    layer.enabled: groupPreviewCell.layer.enabled
                                                }
                                                Item {
                                                    id: groupPreviewHost
                                                    objectName: "overviewGroupPreviewSource"
                                                    readonly property bool isGroupPreviewSource: true
                                                    anchors.fill: parent
                                                    anchors.margins: 1
                                                    enabled: false
                                                    Component.onDestruction: {
                                                        const view = groupPreviewCell.previewView
                                                        if (view?.frameContainer?.parent === groupPreviewHost)
                                                            root.detachOverviewFrame(view)
                                                    }
                                                }
                                                ShaderEffectSource {
                                                    id: groupPreviewTexture
                                                    objectName: "overviewGroupPreviewTexture"
                                                    anchors.fill: parent
                                                    anchors.margins: 1
                                                    visible: !!groupPreviewCell.previewView
                                                    opacity: groupContainer.transitioning ? 1 : 0
                                                    sourceItem: groupPreviewCell.previewView?.frameContainer ?? null
                                                    hideSource: false
                                                    live: false
                                                    smooth: true
                                                    textureSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio * appSettings.overviewPreviewQuality / 100)),
                                                                         Math.max(1, Math.ceil(height * Screen.devicePixelRatio * appSettings.overviewPreviewQuality / 100)))
                                                    Timer {
                                                        interval: 33
                                                        running: root.overviewVisible && groupContainer.expansion < 1
                                                                 && !!groupPreviewCell.previewView
                                                                 && groupContainer.y + groupContainer.height > overviewFlickable.contentY
                                                                 && groupContainer.y < overviewFlickable.contentY + overviewFlickable.height
                                                        repeat: true
                                                        onTriggered: groupPreviewTexture.scheduleUpdate()
                                                    }
                                                }
                                                Controls.BusyIndicator {
                                                    objectName: "overviewGroupPreviewLoading"
                                                    anchors.centerIn: parent
                                                    width: Math.min(24, parent.height / 3); height: width
                                                    visible: !!groupPreviewCell.previewView && !groupPreviewCell.previewView.hasLoadedFrame
                                                             && !groupPreviewCell.previewView.showingSleepPreview
                                                    running: visible && root.overviewVisible && groupContainer.expansion < 1
                                                }
                                                Kirigami.Icon {
                                                    anchors.centerIn: parent
                                                    width: root.tabIconSize; height: width
                                                    source: "system-suspend"
                                                    visible: !!groupPreviewCell.previewView && appSettings.sleepingTabPreviews
                                                             && groupPreviewCell.previewView.lifecycleState !== CefView.LifecycleState.Active
                                                }
                                                Controls.Label {
                                                    objectName: "overviewGroupOverflow"
                                                    anchors.centerIn: parent
                                                    visible: groupPreviewCell.overflow
                                                    text: groupPreviewCell.overflow ? "+" + (groupContainer.members.length - 3) : ""
                                                    font.bold: true
                                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.5
                                                }
                                            }
                                        }
                                    }
                                    Kirigami.Icon {
                                        objectName: "overviewGroupArrow"
                                        width: Kirigami.Units.iconSizes.large; height: width
                                        x: (parent.width - width) / 2
                                        y: (parent.height - height) / 2 - 50 * (1 - groupContainer.expansion)
                                        opacity: groupContainer.expansion
                                        source: "arrow-down"
                                        color: groupContainer.accentColor
                                        Accessible.name: groupContainer.group?.overviewCollapsed ? qsTr("Expand tab group") : qsTr("Collapse tab group")
                                    }
                                }
                                MouseArea {
                                    id: groupOverviewMouse
                                    hoverEnabled: true
                                    anchors.fill: parent
                                    onClicked: mouse => {
                                        if (!groupOverviewDrag.active && !groupContainer.settling
                                                && !root.selectGroupForAction(groupContainer.group.id, mouse.modifiers))
                                            root.updateTabGroup(groupContainer.group.id,
                                                {overviewCollapsed: !groupContainer.group.overviewCollapsed && !groupContainer.collapsing})
                                    }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: eventPoint => root.showGroupContextMenu(groupContainer.group.id, groupOverviewHeader, eventPoint.position)
                                }
                                DragHandler {
                                    id: groupOverviewDrag
                                    objectName: "overviewGroupDrag"
                                    target: null
                                    acceptedButtons: Qt.LeftButton
                                    enabled: !groupContainer.transitioning && !root.overviewAnimationRunning
                                             && root.overviewProgress >= 0.999 && !root.overviewClosing
                                    onActiveChanged: {
                                        if (active) {
                                            groupOverviewSettle.stop()
                                            groupContainer.settling = false
                                            groupContainer.dragOriginX = groupContainer.x
                                            groupContainer.dragOriginY = groupContainer.y
                                            groupContainer.dragBodyOriginX = groupExpandedArea.x
                                            groupContainer.dragBodyOriginY = groupExpandedArea.y
                                            groupExpandedArea.releaseOffsetX = 0
                                            groupExpandedArea.releaseOffsetY = 0
                                            overviewWheelScroll.stop()
                                            root.overviewDraggedGroupId = groupContainer.group.id
                                            root.draggedGroupId = groupContainer.group.id
                                            root.groupDropIndex = root.views.findIndex(view => view.tabGroupId === groupContainer.group.id)
                                        } else if (groupContainer.dragging) {
                                            const position = Qt.point(groupContainer.x + groupContainer.dragOffsetX,
                                                                      groupContainer.y + groupContainer.dragOffsetY)
                                            const bodyPosition = Qt.point(groupExpandedArea.x, groupExpandedArea.y)
                                            const stripPositions = root.captureTabStripPositions()
                                            const destination = root.groupDropIndex
                                            const id = groupContainer.group.id
                                            groupContainer.settling = true
                                            root.overviewDraggedGroupId = ""
                                            root.draggedGroupId = ""
                                            root.groupDropIndex = -1
                                            root.moveTabGroup(id, destination, stripPositions)
                                            groupContainer.dragOffsetX = position.x - groupContainer.x
                                            groupContainer.dragOffsetY = position.y - groupContainer.y
                                            groupExpandedArea.releaseOffsetX = bodyPosition.x - (groupContainer.region?.body?.x ?? 0) - groupContainer.dragOffsetX
                                            groupExpandedArea.releaseOffsetY = bodyPosition.y - (groupContainer.region?.body?.y ?? 0) - groupContainer.dragOffsetY
                                            if (appSettings.reduceMotion) {
                                                groupContainer.dragOffsetX = 0
                                                groupContainer.dragOffsetY = 0
                                                groupExpandedArea.releaseOffsetX = 0
                                                groupExpandedArea.releaseOffsetY = 0
                                                groupContainer.settling = false
                                            } else groupOverviewSettle.start()
                                        }
                                    }
                                    onActiveTranslationChanged: {
                                        if (!active) return
                                        groupContainer.dragOffsetX = activeTranslation.x
                                        groupContainer.dragOffsetY = activeTranslation.y
                                        const point = overviewFlickable.contentItem.mapFromItem(root.contentItem,
                                            centroid.scenePosition.x, centroid.scenePosition.y)
                                        root.groupDropIndex = root.overviewGroupDropTarget(point)
                                    }
                                }
                            }
                            ParallelAnimation {
                                id: groupOverviewSettle
                                onFinished: groupContainer.settling = false
                                NumberAnimation { target: groupContainer; property: "dragOffsetX"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: groupContainer; property: "dragOffsetY"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: groupExpandedArea; property: "releaseOffsetX"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: groupExpandedArea; property: "releaseOffsetY"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Repeater {
                        id: overviewCardRepeater
                        model: overviewModel
                        delegate: Item {
                            id: overviewDelegate
                            required property int index
                            required property var previewView
                            property alias card: overviewCard
                            // Keep repeater delegates as siblings while the visual card moves into its group.
                            Item {
                                id: overviewCard
                                objectName: "overviewCard"
                                clip: true
                                readonly property real cornerRadius: Kirigami.Units.smallSpacing + 3
                                readonly property bool inOverviewViewport: visible && !group?.overviewCollapsed
                                    && viewportX + width > 0 && viewportX < overviewFlickable.width
                                    && viewportY + height > overviewFlickable.contentY
                                    && viewportY < overviewFlickable.contentY + overviewFlickable.height
                                layer.enabled: root.overviewVisible
                                               && (floating || !appSettings.cullOffscreenOverviewEffects || inOverviewViewport)
                                readonly property real textureScale: Screen.devicePixelRatio
                                    * (zooming ? 1 - (1 - appSettings.overviewPreviewQuality / 100) * root.overviewProgress
                                               : appSettings.overviewPreviewQuality / 100)
                                layer.textureSize: appSettings.overviewPreviewQuality < 100
                                                   ? Qt.size(Math.max(1, Math.ceil(width * textureScale)),
                                                             Math.max(1, Math.ceil(height * textureScale)))
                                                   : Qt.size(0, 0)
                                layer.smooth: true
                                layer.effect: MultiEffect {
                                    autoPaddingEnabled: false
                                    maskEnabled: true
                                    maskSource: overviewCardMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }
                                Rectangle {
                                    id: overviewCardMask
                                    objectName: "overviewCardMask"
                                    parent: browserArea
                                    width: overviewCard.width
                                    height: overviewCard.height
                                    radius: overviewCard.cornerRadius
                                    color: "white"
                                    antialiasing: true
                                    visible: false
                                    layer.enabled: overviewCard.layer.enabled
                                    // Keep the outline sharp even when web previews use reduced resolution.
                                    layer.textureSize: Qt.size(0, 0)
                                    layer.smooth: true
                                }
                                readonly property int index: overviewDelegate.index
                                readonly property var previewView: overviewDelegate.previewView
                                readonly property int tabIndex: previewView === root.homeView ? -1 : root.views.indexOf(previewView)
                                readonly property var group: root.groupFor(previewView)
                                readonly property var container: group ? root.overviewGroupContainer(group.id) : null
                                readonly property bool dragMember: !!root.dragView && root.dragViews.includes(previewView)
                                readonly property bool floating: dragging || dragMember || settling || closing
                                    || zooming && (root.overviewClosing || root.overviewProgress < 0.999)
                                parent: container && root.overviewVisible && !floating
                                        ? container.cardArea : overviewFlickable.contentItem
                                readonly property bool hosted: !!container && parent === container.cardArea
                                readonly property real parentLeft: hosted ? (container.region?.body?.x ?? 0) + container.cardArea.x : 0
                                readonly property real parentTop: hosted ? (container.region?.body?.y ?? 0) + container.cardArea.y : 0
                                readonly property real viewportX: x + dragOffsetX
                                    + (hosted ? container.expandedArea.x + container.cardArea.x : 0)
                                readonly property real viewportY: y + dragOffsetY
                                    + (hosted ? container.expandedArea.y + container.expandedArea.motionY + container.cardArea.y : 0)
                                property bool changingParent: false
                                onParentChanged: {
                                    changingParent = true
                                    Qt.callLater(() => { if (overviewCard) overviewCard.changingParent = false })
                                }
                                readonly property bool dragging: root.overviewDraggedView === previewView
                                property bool settling: false
                                property real dragOffsetX: 0
                                property real dragOffsetY: 0
                                property real dragOriginX: 0
                                property real dragOriginY: 0
                                readonly property bool closing: !!previewView && previewView.overviewClosingCard
                                readonly property bool sleeping: appSettings.sleepingTabPreviews && !!previewView
                                                                && previewView.lifecycleState !== CefView.LifecycleState.Active
                                readonly property bool zooming: previewView === root.overviewSelectedView
                                readonly property int gridSlot: root.overviewPreviewSlot(tabIndex)
                                readonly property real entrance: zooming && !closing
                                    && (root.overviewClosing || root.overviewProgress < 0.999) ? 1
                                                                   : container?.transitioning && !closing ? container.expansion : previewView?.overviewEntrance ?? 1
                                readonly property real headerHeight: root.overviewTitleHeight
                                                                     * (zooming ? root.overviewProgress : 1)
                                visible: closing || root.overviewMatches(tabIndex)
                                                    && (!group?.overviewCollapsed || dragging || dragMember || settling)
                                         || (zooming && root.overviewProgress < 0.999)
                                enabled: !closing && !container?.transitioning
                                z: dragging || settling ? 20 : dragMember ? 19 : zooming ? 10 : closing ? 9 : 0
                                transform: Translate { x: overviewCard.dragOffsetX; y: overviewCard.dragOffsetY }
                                opacity: entrance
                                x: (closing ? previewView.overviewCloseX
                                   : dragging ? dragOriginX
                                   : zooming ? root.overviewCardX(gridSlot) * root.overviewProgress
                                           : root.overviewCardX(gridSlot)) - parentLeft
                                y: (closing ? previewView.overviewCloseY - 50 * (1 - entrance)
                                   : dragging ? dragOriginY
                                   : zooming ? root.overviewCardY(gridSlot) * root.overviewProgress
                                             + overviewFlickable.contentY * (1 - root.overviewProgress)
                                           : root.overviewCardY(gridSlot)) - parentTop
                                   - (closing || dragging || zooming && (root.overviewClosing || root.overviewProgress < 0.999)
                                      ? 0 : container?.transitioning ? 0 : 50 * (1 - entrance))
                                width: closing ? previewView.overviewCloseWidth
                                       : zooming ? browserArea.width * (1 - root.overviewProgress)
                                                   + root.overviewCardWidth * root.overviewProgress
                                                 : root.overviewCardWidth
                                height: closing ? previewView.overviewCloseHeight
                                        : zooming ? browserArea.height * (1 - root.overviewProgress)
                                                    + root.overviewCardHeight * root.overviewProgress
                                                  : root.overviewCardHeight
                                onPreviewViewChanged: {
                                    if (root.overviewVisible && previewView)
                                        root.attachOverviewFrame(previewView)
                                }
                                Component.onDestruction: root.detachFrameForCard(overviewCard)
                                Behavior on x {
                                    enabled: root.overviewVisible && root.overviewProgress >= 0.999
                                             && overviewCard.entrance >= 0.999 && !root.overviewAnimationRunning
                                             && !overviewCard.dragging && !overviewCard.settling
                                             && !overviewCard.changingParent && !overviewCard.container?.transitioning
                                             && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                                Behavior on y {
                                    enabled: root.overviewVisible && root.overviewProgress >= 0.999
                                             && overviewCard.entrance >= 0.999 && !root.overviewAnimationRunning
                                             && !root.overviewGroupAnimationRunning
                                             && !overviewCard.dragging && !overviewCard.settling
                                             && !overviewCard.changingParent && !overviewCard.container?.transitioning
                                             && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                                Behavior on width {
                                    enabled: !overviewCard.closing && root.overviewVisible
                                             && root.overviewProgress >= 0.999 && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }
                                Behavior on height {
                                    enabled: !overviewCard.closing && root.overviewVisible
                                             && root.overviewProgress >= 0.999 && !appSettings.reduceMotion
                                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                                }

                                function settleFrom(point) {
                                    cardSettle.stop()
                                    const slot = root.overviewFilteredSlot(root.views.indexOf(previewView))
                                    settling = true
                                    dragOffsetX = point.x - root.overviewCardX(slot)
                                    dragOffsetY = point.y - root.overviewCardY(slot)
                                    if (appSettings.reduceMotion) {
                                        dragOffsetX = 0
                                        dragOffsetY = 0
                                        settling = false
                                    } else cardSettle.start()
                                }

                                Rectangle {
                                    objectName: "overviewCardBackground"
                                    anchors.fill: parent
                                    color: Kirigami.Theme.backgroundColor
                                    opacity: (appSettings.translucentSidebars || appSettings.floatingSidebars
                                              && overviewCard.previewView && Policy.isFileUrl(String(overviewCard.previewView.tabUrl)))
                                             && appSettings.sidebarBackdrop === "desktop" && appSettings.toolbarOpacity < 100
                                             && overviewCard.previewView
                                             && overviewCard.previewView.hasLoadedFrame
                                             ? root.overviewSidebarBackdrop : 1
                                }

                                Rectangle {
                                    objectName: "overviewCardBorder"
                                    anchors.fill: parent
                                    z: 3
                                    radius: overviewCard.cornerRadius
                                    property real hoverAmount: overviewCardMouse.containsMouse ? 1 : 0
                                    Behavior on hoverAmount {
                                        enabled: !appSettings.reduceMotion
                                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                    }
                                    color: root.selectedTabViews.includes(overviewCard.previewView) ? root.selectionTint
                                           : hoverAmount > 0 ? Qt.rgba(root.selectionTint.r, root.selectionTint.g,
                                                                      root.selectionTint.b, root.selectionTint.a * hoverAmount)
                                                             : "transparent"
                                    border.width: 1
                                    border.color: overviewCard.group ? overviewCard.group.color
                                                  : Qt.rgba(Kirigami.Theme.textColor.r,
                                                            Kirigami.Theme.textColor.g,
                                                            Kirigami.Theme.textColor.b,
                                                            0.3 + 0.25 * hoverAmount)
                                }

                                Rectangle {
                                    id: overviewTitlebar
                                    z: 2
                                    x: 1
                                    y: 1
                                    width: parent.width - 2
                                    height: Math.max(0, overviewCard.headerHeight - 1)
                                    color: Kirigami.Theme.backgroundColor
                                    clip: true

                                    Item {
                                        anchors.fill: parent
                                        opacity: overviewCard.zooming ? root.overviewProgress : 1

                                    Kirigami.Icon {
                                        width: root.tabIconSize
                                        height: root.tabIconSize
                                        anchors.left: parent.left
                                        anchors.leftMargin: Kirigami.Units.smallSpacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: overviewCard.previewView
                                                  && Policy.isFileUrl(overviewCard.previewView.tabUrl)
                                                  ? "text-x-generic" : "go-home"
                                    }
                                    RowLayout {
                                        id: overviewCardTitleRow
                                        anchors.left: parent.left
                                        anchors.leftMargin: Kirigami.Units.smallSpacing
                                                            + root.tabIconSize + Kirigami.Units.smallSpacing
                                        anchors.right: parent.right
                                        anchors.rightMargin: overviewActions.width + Kirigami.Units.smallSpacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Kirigami.Units.smallSpacing
                                        Controls.Label {
                                            Layout.minimumWidth: 0
                                            Layout.maximumWidth: Math.max(0, overviewCardTitleRow.width
                                                - (overviewGroupName.visible ? Math.min(overviewGroupName.implicitWidth, overviewCard.width * 0.4) : 0)
                                                - overviewCardTitleRow.spacing * 2)
                                            text: overviewCard.tabIndex < 0 ? qsTr("Home")
                                                  : overviewCard.previewView
                                                    ? Policy.pageLabel(overviewCard.previewView.tabUrl,
                                                                       overviewCard.previewView.title) : ""
                                            elide: Text.ElideRight
                                        }
                                        Controls.Label {
                                            id: overviewGroupName
                                            objectName: "overviewTabGroupName"
                                            visible: !!overviewCard.group
                                            text: overviewCard.group ? overviewCard.group.title : ""
                                            color: overviewCard.group ? overviewCard.group.color : Kirigami.Theme.textColor
                                            Layout.maximumWidth: overviewCard.width * 0.4
                                            elide: Text.ElideRight
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                    Row {
                                        id: overviewActions
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0
                                        z: 3

                                        Controls.ToolButton {
                                            id: overviewOptionsButton
                                            objectName: "overviewTabOptions"
                                            visible: overviewCard.tabIndex >= 0
                                            width: 30
                                            height: 30
                                            icon.name: "overflow-menu"
                                            icon.width: root.tabIconSize
                                            icon.height: root.tabIconSize
                                            Accessible.name: qsTr("Tab options")
                                            onClicked: overviewMenu.popup(overviewOptionsButton, 0, overviewOptionsButton.height)

                                            Controls.Menu {
                                                id: overviewMenu
                                                objectName: "overviewTabMenu"
                                                TabGroupMenu { appWindow: root; tabView: overviewCard.previewView; enabled: overviewCard.tabIndex >= 0 }
                                                Controls.MenuItem {
                                                    text: qsTr("Move to new window")
                                                    enabled: overviewCard.tabIndex >= 0 && !!overviewCard.previewView
                                                             && root.views.length > 1
                                                             && Policy.isFigmaUrl(overviewCard.previewView.tabUrl)
                                                    onTriggered: {
                                                        const view = overviewCard.previewView
                                                        Qt.callLater(() => root.moveTabToNewWindow(root.views.indexOf(view)))
                                                    }
                                                }
                                                Controls.MenuItem {
                                                    text: root.tabsForAction(overviewCard.previewView).length > 1 ? qsTr("Close selected tabs") : qsTr("Close")
                                                    enabled: overviewCard.tabIndex >= 0
                                                    onTriggered: {
                                                        const view = overviewCard.previewView
                                                        Qt.callLater(() => root.closeSelectedTabs(view))
                                                    }
                                                }
                                                Controls.MenuItem {
                                                    text: qsTr("Refresh")
                                                    enabled: !root.allFrozen
                                                    onTriggered: {
                                                        root.refreshSelectedTabs(overviewCard.previewView)
                                                    }
                                                }
                                                Controls.MenuItem {
                                                    text: qsTr("Copy URL")
                                                    enabled: !!overviewCard.previewView
                                                             && Policy.isFigmaUrl(overviewCard.previewView.tabUrl)
                                                    onTriggered: appSettings.copyToClipboard(String(overviewCard.previewView.tabUrl))
                                                }
                                            }
                                        }
                                        Controls.ToolButton {
                                            visible: overviewCard.tabIndex >= 0
                                            width: 30
                                            height: 30
                                            icon.name: "window-close"
                                            icon.width: root.tabIconSize
                                            icon.height: root.tabIconSize
                                            Accessible.name: qsTr("Close tab")
                                            onClicked: root.closeTab(root.views.indexOf(overviewCard.previewView))
                                        }
                                    }
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.topMargin: overviewCard.headerHeight
                                    anchors.bottom: parent.bottom
                                    z: 0.5
                                    color: Kirigami.Theme.backgroundColor
                                    visible: !overviewCard.previewView
                                             || ((!overviewCard.previewView.hasLoadedFrame
                                                  || overviewCard.previewView.lifecycleState !== CefView.LifecycleState.Active)
                                                 && !overviewCard.previewView.showingSleepPreview)

                                    Controls.BusyIndicator {
                                        anchors.centerIn: parent
                                        width: 32
                                        height: 32
                                        visible: !overviewCard.sleeping
                                        running: parent.visible && visible
                                    }
                                }

                                Kirigami.Icon {
                                    objectName: "sleepingTabIcon"
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: overviewCard.headerHeight / 2
                                    z: 0.75
                                    width: Kirigami.Units.iconSizes.medium
                                    height: width
                                    source: "system-suspend"
                                    visible: overviewCard.sleeping
                                    Accessible.name: qsTr("Sleeping tab")
                                }

                                MouseArea {
                                    id: overviewCardMouse
                                    objectName: "overviewCardMouse"
                                    anchors.fill: parent
                                    z: 1
                                    hoverEnabled: true
                                    enabled: root.overviewVisible && !root.overviewClosing
                                    onClicked: mouse => {
                                        if (!overviewCard.dragging && !overviewCard.settling)
                                            root.selectFileTabs(overviewCard.previewView, mouse.modifiers, true)
                                    }
                                }
                                DragHandler {
                                    id: cardDrag
                                    objectName: "overviewCardDrag"
                                    target: null
                                    acceptedButtons: Qt.LeftButton
                                    enabled: !!overviewCard.previewView && !overviewCard.closing
                                             && root.overviewProgress >= 0.999 && !root.overviewClosing
                                             && !root.overviewAnimationRunning
                                    onActiveChanged: {
                                        if (active) {
                                            cardSettle.stop()
                                            overviewCard.settling = false
                                            const origin = overviewCard.mapToItem(overviewFlickable.contentItem, 0, 0)
                                            overviewCard.dragOriginX = origin.x
                                            overviewCard.dragOriginY = origin.y
                                            overviewWheelScroll.stop()
                                            root.overviewDraggedView = overviewCard.previewView
                                            root.overviewDropIndex = overviewCard.tabIndex
                                            root.overviewDropGroupId = overviewCard.previewView.tabGroupId || ""
                                            if (overviewCard.tabIndex >= 0)
                                                root.beginItemDrag(overviewCard.previewView, overviewCard, centroid.scenePosition)
                                        } else if (overviewCard.dragging) {
                                            const stripPositions = root.captureTabStripPositions()
                                            const view = overviewCard.previewView
                                            const point = centroid.scenePosition
                                            const destination = root.overviewDropIndex
                                            const destinationGroup = root.overviewDropGroupId
                                            const visualX = overviewCard.x + overviewCard.dragOffsetX
                                            const visualY = overviewCard.y + overviewCard.dragOffsetY
                                            const members = root.dragViews.slice()
                                            const peers = root.outsideWindow(point) ? [] : members.filter(item => item !== view)
                                                .map(item => overviewCardRepeater.itemAt(root.views.indexOf(item) + 1)?.card)
                                                .filter(card => !!card)
                                                .map(card => ({card: card, point: card.mapToItem(overviewFlickable.contentItem, 0, 0)}))
                                            for (const peer of peers) peer.card.settling = true
                                            overviewCard.settling = true
                                            root.overviewDraggedView = null
                                            root.overviewDropIndex = -1
                                            root.overviewDropGroupId = ""
                                            if (view === root.homeView) {
                                                if (appSettings.reduceMotion) {
                                                    overviewCard.dragOffsetX = 0
                                                    overviewCard.dragOffsetY = 0
                                                    overviewCard.settling = false
                                                } else cardSettle.start()
                                            } else if (root.outsideWindow(point)) {
                                                overviewCard.dragOffsetX = 0
                                                overviewCard.dragOffsetY = 0
                                                overviewCard.settling = false
                                                root.finishItemDrag(point)
                                            } else {
                                                root.cancelItemDrag()
                                                root.reorderTab(root.views.indexOf(view), destination, stripPositions, false, destinationGroup, members)
                                                if (destinationGroup)
                                                    root.updateTabGroup(destinationGroup, {overviewCollapsed: false})
                                                overviewCard.settleFrom(Qt.point(visualX, visualY))
                                                for (const peer of peers) peer.card.settleFrom(peer.point)
                                            }
                                        }
                                    }
                                    onActiveTranslationChanged: {
                                        if (!active) return
                                        overviewCard.dragOffsetX = activeTranslation.x
                                        overviewCard.dragOffsetY = activeTranslation.y
                                        if (overviewCard.previewView === root.homeView) return
                                        const point = overviewFlickable.contentItem.mapFromItem(root.contentItem,
                                            centroid.scenePosition.x, centroid.scenePosition.y)
                                        root.overviewDropIndex = root.overviewDropTarget(point)
                                        root.updateItemDrag(centroid.scenePosition)
                                    }
                                }
                                ParallelAnimation {
                                    id: cardSettle
                                    onFinished: overviewCard.settling = false
                                    NumberAnimation { target: overviewCard; property: "dragOffsetX"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: overviewCard; property: "dragOffsetY"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.MiddleButton
                                    enabled: root.overviewProgress > 0.95
                                    onTapped: root.closeTab(root.views.indexOf(overviewCard.previewView))
                                }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    enabled: root.overviewProgress > 0.95 && !overviewCard.closing
                                    onTapped: eventPoint => {
                                        const position = overviewCard.mapToItem(root.contentItem, eventPoint.position.x, eventPoint.position.y)
                                        overviewMenu.popup(root.contentItem, position.x, position.y)
                                    }
                                }
                                Rectangle {
                                    objectName: "overviewCardFocusRing"
                                    anchors.fill: parent
                                    z: 4
                                    radius: overviewCard.cornerRadius
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Kirigami.Theme.highlightColor
                                    visible: overviewCard.zooming
                                    opacity: root.overviewProgress
                                }
                            }
                        }
                    }
                }

                Controls.TextField {
                    id: overviewSearch
                    objectName: "overviewSearch"
                    x: (parent.width - width) / 2
                    y: root.overviewMargin
                    width: Math.min(320, parent.width - root.overviewMargin * 2)
                    height: 38
                    z: 5
                    placeholderText: qsTr("Search tabs")
                    leftPadding: 12 + root.tabIconSize + Kirigami.Units.smallSpacing
                    rightPadding: 12
                    Accessible.name: qsTr("Search tabs")
                    Keys.forwardTo: [overviewOverlay]
                    onTextChanged: {
                        overviewFlickable.resetScroll()
                        root.syncOverviewNavigation()
                    }

                    Kirigami.Icon {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.tabIconSize
                        height: root.tabIconSize
                        source: "edit-find"
                    }
                }

            }

        }
    }

    WindowResizeHandles {
        parent: root.contentItem
        anchors.fill: parent
        active: root.framelessTabBar && !root.webFullscreen
        targetWindow: root
    }

    HoverHandler {
        parent: root.contentItem
        enabled: root.toolbarAutoHidden
        onPointChanged: root.fullscreenToolbarHovered = hovered && point.position.y >= 0
                                                       && point.position.y < (root.fullscreenToolbarHovered ? root.tabStripHeight : 3)
        onHoveredChanged: root.fullscreenToolbarHovered = hovered && point.position.y >= 0
                                                         && point.position.y < (root.fullscreenToolbarHovered ? root.tabStripHeight : 3)
    }

    ListModel { id: tabModel }
    ListModel { id: overviewModel }
    onViewsChanged: {
        selectedTabViews = selectedTabViews.filter(view => view === homeView || views.includes(view))
        tabGroups = tabGroups.filter(group => views.some(view => view.tabGroupId === group.id))
        syncOverviewModel()
        if (overviewVisible) Qt.callLater(root.syncOverviewNavigation)
    }
    onTabGroupsChanged: {
        selectedGroupIds = selectedGroupIds.filter(id => tabGroups.some(group => group.id === id))
        if (overviewVisible) Qt.callLater(root.syncOverviewNavigation)
    }
    onOverviewVisibleChanged: if (!overviewVisible) {
        overviewNavigationTarget = null
        overviewRangeAnchor = null
    }
    onHomeViewChanged: syncOverviewModel()

    DropArea {
        id: tabDropArea
        objectName: "tabDropArea"
        parent: root.contentItem
        anchors.fill: parent
        z: 1000
        keys: ["application/x-resketch-tab"]
        onEntered: event => event.accepted = root.canAcceptTabDrop(event.getDataAsString("application/x-resketch-tab"))
        onDropped: event => {
            if (root.acceptTabDrop(event.getDataAsString("application/x-resketch-tab")))
                event.accept(Qt.MoveAction)
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 2
            border.color: Kirigami.Theme.highlightColor
            visible: tabDropArea.containsDrag
        }
    }

    Image {
        objectName: "tabDragPreview"
        parent: root.contentItem
        z: 1001
        x: root.dragScenePosition.x + 16
        y: root.dragScenePosition.y + 16
        width: root.dragPreviewSize.width
        height: root.dragPreviewSize.height
        source: root.dragSnapshot ? root.dragSnapshot.url : ""
        fillMode: Image.PreserveAspectFit
        cache: false
        opacity: 0.85
        visible: !!root.dragView && !root.nativeTabDragRunning && status === Image.Ready
                 && root.outsideWindow(root.dragScenePosition)
    }

    Item {
        id: nativeDragProxy
        objectName: "nativeDragProxy"
        parent: root.contentItem
        width: 1
        height: 1
        Drag.dragType: Drag.None
        Drag.source: root
        Drag.supportedActions: Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: ({"application/x-resketch-tab": root.dragToken})
        Drag.imageSource: root.dragSnapshot ? root.dragSnapshot.url : ""
        Drag.hotSpot: Qt.point(12, 12)
        Drag.onDragFinished: action => root.finishNativeTabDrag(action)
    }

    // One receiver handles both axes, including zero-delta gesture boundaries.
    component ScrollGestureArea: MouseArea {
        id: gestureArea
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton
        required property var flickable
        required property real wheelStep
        property bool horizontal: false
        property int gestureAxis: 0
        Timer {
            id: gestureIdle
            interval: 150
            onTriggered: gestureArea.gestureAxis = 0
        }
        onWheel: event => {
            const pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
            const continuous = pixels || event.phase !== Qt.NoScrollPhase
                               || event.device.type === PointerDevice.TouchPad
            if (event.phase === Qt.ScrollBegin) gestureAxis = 0
            const delta = pixels ? event.pixelDelta : event.angleDelta
            let axis = horizontal && Math.abs(delta.x) > Math.abs(delta.y) ? 1 : 2
            if (continuous && (delta.x !== 0 || delta.y !== 0)) {
                if (!gestureAxis) gestureAxis = axis
                axis = gestureAxis
            }
            const distance = axis === 1 ? delta.x : delta.y
            if (distance !== 0 || (continuous && event.phase === Qt.ScrollBegin)) {
                flickable.cancelFlick()
                flickable.scrollBy(pixels ? distance : distance * wheelStep / 120, continuous)
            }
            if (continuous) gestureIdle.restart()
            if (event.phase === Qt.ScrollEnd) {
                gestureIdle.stop()
                gestureAxis = 0
            }
            event.accepted = true
        }
    }

    Kirigami.InlineMessage {
        objectName: "gpuAccelerationWarning"
        parent: root.contentItem
        anchors.top: parent.top
        anchors.topMargin: root.tabStripHeight + Kirigami.Units.smallSpacing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Kirigami.Units.smallSpacing
        z: 2000
        type: Kirigami.MessageType.Warning
        text: appSettings.gpuAccelerationWarning
        visible: text.length > 0
        showCloseButton: true
    }

    // Create secondary UI only when needed, and optionally release it on close.
    component AuxiliaryWindowLoader: Loader {
        id: windowLoader
        active: false
        property var savedGeometry: null
        function openWindow() {
            active = true
            if (!item) return
            if (savedGeometry) {
                item.x = savedGeometry.x
                item.y = savedGeometry.y
                item.width = savedGeometry.width
                item.height = savedGeometry.height
            }
            item.show()
            item.raise()
            item.requestActivate()
        }
        function releaseIfHidden() {
            if (appSettings.releaseClosedWindows && item && !item.visible)
                active = false
        }
        Connections {
            target: windowLoader.item
            function onVisibleChanged() {
                if (!windowLoader.item.visible) {
                    const window = windowLoader.item
                    windowLoader.savedGeometry = Qt.rect(window.x, window.y, window.width, window.height)
                    // Let the window finish dispatching its close event first.
                    Qt.callLater(windowLoader.releaseIfHidden)
                }
            }
        }
        Connections {
            target: appSettings
            function onChanged() { Qt.callLater(windowLoader.releaseIfHidden) }
        }
    }
    AuxiliaryWindowLoader {
        id: settingsWindowLoader
        sourceComponent: SettingsWindow { visible: false }
    }
    AuxiliaryWindowLoader {
        id: aboutWindowLoader
        sourceComponent: AboutWindow { visible: false }
    }
    AuxiliaryWindowLoader {
        id: exportHistoryWindowLoader
        sourceComponent: ExportHistoryWindow { visible: false }
    }

    AuxiliaryWindowLoader {
        id: taskManagerWindowLoader
        sourceComponent: ChromiumToolsWindow { mode: "tasks"; ownerWindow: root; visible: false }
    }
    AuxiliaryWindowLoader {
        id: developerToolsWindowLoader
        sourceComponent: ChromiumToolsWindow { mode: "devtools"; ownerWindow: root; visible: false }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.updateTabLifecycle()
    }

    property bool notificationPolling: false
    property double lastNotificationPoll: 0
    Timer {
        interval: 5000
        repeat: true
        running: !!root.homeView && root.homeView.notificationSource
        onTriggered: root.pollHomeNotifications()
    }
    Timer {
        interval: 500
        repeat: true
        running: !!root.homeView && root.homeView.notificationSource && !root.homeView.loading
                 && Policy.isFileBrowserUrl(root.homeView.url)
        onTriggered: root.homeView.runJavaScript(NotificationPolicy.drainFeedScript(), root.receiveHomeNotifications)
    }

    Timer {
        id: signInRefreshTimer
        objectName: "signInRefreshTimer"
        property var sourceView: null
        interval: 4000
        onTriggered: {
            if (sourceView && (sourceView === root.homeView || root.views.includes(sourceView)))
                sourceView.reload()
            sourceView = null
        }
    }

    Connections {
        target: appSettings
        function onChanged() {
            if (appSettings.reduceMotion && root.outgoingView)
                root.resetSlide()
            if (appSettings.reduceMotion && overviewAnimation.running) {
                overviewAnimation.stop()
                if (root.overviewClosing) {
                    root.overviewProgress = 0
                    root.finishOverviewTransition()
                } else {
                    root.overviewProgress = 1
                    if (root.pendingOverviewSelection)
                        root.selectOverviewView(root.pendingOverviewSelection)
                }
            }
            if (appSettings.reduceMotion) {
                selectionGlide.stop()
                root.homeSelectionGlide = false
                selectionBar.startOffset = 0
                selectionBar.endOffset = 0
                root.heldOpenSelection = null
                root.hideHeldSelection = false
                Qt.callLater(root.processPendingClose)
            }
            if (!appSettings.sleepingTabPreviews) {
                for (const view of [root.homeView].concat(root.views)) {
                    if (!view) continue
                    view.sleepPreview = null
                }
            }
            root.updateTabLifecycle()
            if (root.overviewVisible) root.syncOverviewFrames()
        }
        function onEffectiveThemeChanged() {
            figmaAppearanceTimer.restart()
        }
        function onFigmaAppearanceChanged() {
            figmaAppearanceTimer.restart()
        }
    }

    Timer {
        id: figmaAppearanceTimer
        interval: 50
        onTriggered: {
            for (const view of [root.homeView].concat(root.views))
                root.syncFigmaTheme(view)
        }
    }

    CefProfile {
        id: figmaProfile
        // Home's feed supplies notifications without depending on Chromium's
        // push registration endpoint; only Home receives native notifications.
        storageName: root.sharedProfile ? "" : "resketch"
        persistentStoragePath: root.sharedProfile ? "" : appSettings.profileStoragePath
        offTheRecord: !!root.sharedProfile
        onDownloadRequested: function(download) { root.handleDownload(download) }
        onDownloadFinished: function(download) { root.completeDownload(download) }
        onPresentNotification: function(notification) { appSettings.showDesktopNotification(notification, root) }
    }

    ParallelAnimation {
        id: tabSlide
        onFinished: root.finishSlide()
        NumberAnimation {
            id: incomingSlide
            property: "slideX"
            to: 0
            duration: 260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
        }
        NumberAnimation {
            id: outgoingSlide
            property: "slideX"
            duration: 260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
        }
    }

    NumberAnimation {
        id: overviewAnimation
        target: root
        property: "overviewProgress"
        duration: 300
        easing.type: Easing.OutCubic
        onFinished: {
            if (root.overviewClosing)
                overviewFinishTimer.start()
            else if (root.overviewVisible) {
                const target = root.pendingOverviewSelection
                root.pendingOverviewSelection = null
                if (target && (target === root.homeView || root.views.includes(target))
                        && !target.overviewClosingCard)
                    root.selectOverviewView(target)
                else overviewSearch.forceActiveFocus()
            }
        }
    }

    Timer {
        id: overviewFinishTimer
        interval: 16
        onTriggered: root.finishOverviewTransition()
    }

    Component {
        id: webFrameComponent

        Item {
            id: frame
            property var ownerWindow: root
            property var previewView: null
            property var previewCard: null
            visible: !frame.ownerWindow.overviewVisible
                     || (!!previewCard && (parent === previewCard || parent.isGroupPreviewSource === true))
            clip: true
            x: 0
            y: parent.isGroupPreviewSource === true ? 0 : previewCard ? previewCard.headerHeight : 0
            width: parent.isGroupPreviewSource === true ? parent.width
                   : previewCard ? previewCard.width : frame.ownerWindow.browserWidth
            height: parent.isGroupPreviewSource === true ? parent.height
                    : previewCard ? Math.max(0, previewCard.height - previewCard.headerHeight)
                                  : frame.ownerWindow.browserHeight
            z: previewCard ? 0 : previewView ? previewView.slideZ : 0
            transform: Translate { x: frame.previewView ? frame.previewView.slideX : 0 }

            Image {
                objectName: "sleepingTabPreview"
                anchors.fill: parent
                z: 1
                visible: frame.ownerWindow.overviewVisible && !!frame.previewView
                         && frame.previewView.showingSleepPreview
                source: visible ? frame.previewView.sleepPreview.url : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                cache: false
                readonly property real displayTextureScale: frame.previewCard
                                                           ? frame.previewCard.textureScale : Screen.devicePixelRatio
                readonly property real textureScale: appSettings.compactPreviewTextures
                    ? Math.min(displayTextureScale, 640 / Math.max(1, width), 480 / Math.max(1, height))
                    : displayTextureScale
                layer.enabled: visible && (!appSettings.cullOffscreenOverviewEffects
                                           || frame.parent.isGroupPreviewSource === true
                                           || (!!frame.previewCard && frame.previewCard.inOverviewViewport))
                layer.textureSize: appSettings.compactPreviewTextures || appSettings.overviewPreviewQuality < 100
                                   ? Qt.size(Math.max(1, Math.round(width * textureScale)),
                                             Math.max(1, Math.round(height * textureScale)))
                                   : Qt.size(0, 0)
                layer.smooth: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 16
                    autoPaddingEnabled: false
                }
            }

            Item {
                anchors.fill: parent
                visible: !frame.ownerWindow.overviewVisible && !!frame.previewView
                         && (frame.previewView === frame.ownerWindow.activeView
                             || frame.previewView === frame.ownerWindow.outgoingView)
                         && !frame.previewView.hasLoadedFrame

                Controls.BusyIndicator {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    running: parent.visible
                }
            }
        }
    }

    Component {
        id: webViewComponent

        CefView {
            id: webView
            property real slideX: 0
            property int slideZ: 0
            property double lastUsedAt: Date.now()
            property bool reloadAfterFreeze: false
            property bool tabOpening: false
            property var tabStripItem: null
            property string tabGroupId: ""
            property real groupExpansion: ownerWindow.groupFor(webView)?.collapsed ? 0 : 1
            Behavior on groupExpansion {
                enabled: !appSettings.reduceMotion
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            property bool dedicatedHome: false
            readonly property bool notificationSource: dedicatedHome && !ownerWindow.primaryWindow
                                                       && appSettings.desktopNotifications
            function syncNotifications() {
                if (notificationSource && Policy.isFigmaUrl(url))
                    profile.queryPermission(url, CefPermission.PermissionType.Notifications).grant()
                if (!loading && Policy.isFigmaUrl(url))
                    runJavaScript(NotificationPolicy.script(notificationSource))
                if (notificationSource && !loading) ownerWindow.pollHomeNotifications()
            }
            onNotificationSourceChanged: {
                syncNotifications()
            }
            property bool googleSignIn: false
            property bool pendingPopup: false
            property var popupSource: null
            property bool popupBackground: false
            Timer {
                interval: 30000
                running: webView.pendingPopup
                onTriggered: webView.ownerWindow.discardPendingPopup(webView)
            }
            property bool hasLoadedFrame: false
            property url deferredRestoreUrl: ""
            readonly property url tabUrl: String(deferredRestoreUrl) || url
            onDeferredRestoreUrlChanged: {
                webView.ownerWindow.syncTab(webView)
                webView.ownerWindow.syncTabLoading(webView)
            }
            property var sleepPreview: null
            property bool sleepCapturePending: false
            property int sleepCaptureSerial: 0
            property bool memoryUnloaded: false
            property int requestedSleepState: CefView.LifecycleState.Active
            readonly property bool showingSleepPreview: appSettings.sleepingTabPreviews
                                                        && !!sleepPreview
                                                        && lifecycleState !== CefView.LifecycleState.Active
            Timer {
                interval: 500
                running: webView.sleepCapturePending
                // A minimized or occluded window may not render a capture frame.
                onTriggered: webView.ownerWindow.finishTabSleep(webView, null, String(webView.url), webView.sleepCaptureSerial)
            }
            property real overviewEntrance: 1
            property bool overviewClosingCard: false
            property real overviewCloseX: 0
            property real overviewCloseY: 0
            property real overviewCloseWidth: 0
            property real overviewCloseHeight: 0
            property var frameContainer: null
            property var authWindow: null
            property var ownerWindow: root
            property url lastHomeUrl: webView.ownerWindow.homeUrl
            function startOverviewEntrance(start = 0) {
                overviewEntranceAnimation.from = start
                overviewEntranceAnimation.start()
            }
            function finishOverviewEntrance() {
                overviewEntranceAnimation.stop()
                if (!overviewClosingCard)
                    overviewEntrance = 1
            }
            function startOverviewClose() {
                const start = overviewEntrance
                overviewEntranceAnimation.stop()
                overviewExitAnimation.from = start
                overviewExitAnimation.start()
            }
            function stopOverviewClose() {
                overviewExitAnimation.stop()
            }
            NumberAnimation {
                id: overviewEntranceAnimation
                target: webView
                property: "overviewEntrance"
                from: 0
                to: 1
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                id: overviewExitAnimation
                target: webView
                property: "overviewEntrance"
                to: 0
                duration: 240
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0, 0.45, 0.50, 1, 1, 1]
                onFinished: webView.ownerWindow.finishOverviewClose(webView)
            }
            width: googleSignIn ? parent.width : webView.ownerWindow.browserWidth
            height: googleSignIn ? parent.height : webView.ownerWindow.browserHeight
            x: 0
            y: 0
            transformOrigin: Item.TopLeft
            scale: frameContainer ? frameContainer.width / Math.max(1, width) : 1
            visible: false
            enabled: !webView.ownerWindow.overviewVisible
            opacity: !hasLoadedFrame ? 0
                     : !webView.ownerWindow.overviewVisible ? 1
                     : overviewClosingCard || frameContainer?.parent?.isGroupPreviewSource === true ? 1
                     : webView.ownerWindow.overviewMatches(webView.ownerWindow.overviewSlot(webView))
                       ? webView === webView.ownerWindow.overviewSelectedView ? 1
                         : overviewEntrance
                       : 0
            profile: webView.ownerWindow.browserProfile
            settings.scrollAnimatorEnabled: !appSettings.reduceMotion
            backgroundColor: appSettings.toolbarOpacity < 100 && !googleSignIn ? "transparent" : "white"
            userScripts.collection: [{
                name: "resketch-canvas-scrollbars",
                sourceCode: FigmaTheme.canvasScrollbarsScript(appSettings.floatingSidebars && appSettings.hideFloatingScrollbars),
                injectionPoint: CefScript.DocumentCreation,
                worldId: CefScript.MainWorld,
                runsOnSubFrames: false
            }, {
                name: "resketch-appearance",
                sourceCode: webView.ownerWindow.figmaAppearanceScript,
                injectionPoint: CefScript.DocumentReady,
                worldId: CefScript.MainWorld,
                runsOnSubFrames: false
            }, {
                name: "resketch-notification-policy",
                sourceCode: NotificationPolicy.script(webView.notificationSource),
                injectionPoint: CefScript.DocumentCreation,
                worldId: CefScript.MainWorld,
                runsOnSubFrames: true
            }]
            transform: Translate { x: webView.frameContainer ? 0 : webView.slideX }

            onLoadStateChanged: function(loadInfo) {
                if (!loading) {
                    if (lifecycleState !== CefView.LifecycleState.Discarded
                            && String(url) && String(url) !== "about:blank")
                        hasLoadedFrame = true
                    if (hasLoadedFrame) sleepPreview = null
                    webView.ownerWindow.syncFigmaTheme(webView)
                }
                webView.ownerWindow.syncTabLoading(webView)
                if (webView.ownerWindow.allFrozen && !loading)
                    webView.ownerWindow.sleepTab(webView, CefView.LifecycleState.Frozen)
                Qt.callLater(webView.ownerWindow.updateTabLifecycle)
                if (pendingPopup && loadInfo.status === CefView.LoadSucceededStatus
                        && Policy.isFigmaUrl(url))
                    Qt.callLater(() => webView.ownerWindow.commitPendingPopup(webView))
            }

            onLoadProgressChanged: {
                webView.ownerWindow.syncTabLoading(webView)
            }

            onTitleChanged: webView.ownerWindow.syncTab(webView)
            onVisibleChanged: {
                if (visible && hasLoadedFrame && lifecycleState === CefView.LifecycleState.Active)
                    appSettings.repaintWebView(webView)
            }
            onLifecycleStateChanged: {
                if (lifecycleState === CefView.LifecycleState.Active) {
                    sleepPreview = null
                    webView.ownerWindow.syncFigmaTheme(webView)
                } else if (lifecycleState === CefView.LifecycleState.Discarded)
                    hasLoadedFrame = false
                if (webView.ownerWindow.overviewVisible)
                    webView.ownerWindow.attachOverviewFrame(webView)
            }
            onWindowCloseRequested: {
                if (pendingPopup)
                    webView.ownerWindow.discardPendingPopup(webView)
                else if (authWindow) {
                    webView.ownerWindow.refreshAfterGoogleSignIn(authWindow.sourceView)
                    Qt.callLater(() => authWindow.close())
                }
            }
            onUrlChanged: {
                syncNotifications()
                sleepPreview = null
                const address = String(url)
                if (dedicatedHome && Policy.isFileUrl(address)) {
                    url = lastHomeUrl
                    webView.ownerWindow.openTab(address, null, false, webView)
                    return
                }
                if (dedicatedHome && Policy.isFileBrowserUrl(address)) {
                    lastHomeUrl = url
                }
                if (appSettings.floatingSidebars && Policy.isFigmaUrl(address))
                    runJavaScript("window.__resketchSidebars?.schedule()")
                webView.ownerWindow.syncTab(webView)
            }

            onNewWindowRequested: function(request) {
                const address = String(request.requestedUrl)
                if (Policy.isExternalWebUrl(address))
                    webView.ownerWindow.openExternalLink(address)
                else if (Policy.isAuthGrantUrl(address))
                    webView.ownerWindow.openWebSignIn(webView)
                else if (!webView.googleSignIn && Policy.isFigmaUrl(address)
                         && address.includes("start_google_sso")
                         && !String(webView.url).startsWith(String(webView.ownerWindow.loginUrl)))
                    webView.ownerWindow.openWebSignIn(webView)
                else if (Policy.isGoogleSignInUrl(address)
                         || (Policy.isFigmaUrl(address) && address.includes("start_google_sso")))
                    webView.ownerWindow.openGoogleSignInWindow(request, "", null, webView)
                else if (!address || address === "about:blank")
                    webView.ownerWindow.openPendingPopup(request, webView)
                else if (!webView.dedicatedHome
                         && (Policy.isFileBrowserUrl(webView.url)
                             || Policy.isNewFileTabUrl(webView.url))
                         && Policy.isFileUrl(address))
                    webView.url = address
                else if (Policy.isFileUrl(address) || Policy.isFileBrowserUrl(address)
                         || Policy.isNewFileTabUrl(address))
                    webView.ownerWindow.openTab("", request,
                                 request.destination === CefNewWindowRequest.InNewBackgroundTab,
                                 webView)
                else if (Policy.isFigmaUrl(address))
                    webView.ownerWindow.openPendingPopup(request, webView)
            }

            onNavigationRequested: function(request) {
                if (!request.isMainFrame)
                    return
                const address = String(request.url)
                if (Policy.isAuthGrantUrl(address)) {
                    request.reject()
                    webView.ownerWindow.openWebSignIn(webView)
                } else if (!webView.googleSignIn && Policy.isFigmaUrl(address)
                           && address.includes("start_google_sso")
                           && !String(webView.url).startsWith(String(webView.ownerWindow.loginUrl))) {
                    request.reject()
                    webView.ownerWindow.openWebSignIn(webView)
                } else if (Policy.isGoogleSignInUrl(address) && !webView.googleSignIn) {
                    if (pendingPopup)
                        Qt.callLater(() => webView.ownerWindow.openGoogleSignInWindow(null, "", webView))
                    else {
                        request.reject()
                        webView.ownerWindow.openGoogleSignInWindow(null, address, null, webView)
                    }
                } else if (Policy.isGoogleSignInUrl(address)) {
                    return
                } else if (!Policy.isFigmaUrl(address) && address !== "about:blank") {
                    request.reject()
                    if (Policy.isExternalWebUrl(address))
                        webView.ownerWindow.openExternalLink(address)
                    if (pendingPopup)
                        webView.ownerWindow.discardPendingPopup(webView)
                } else if (webView.dedicatedHome && Policy.isFileUrl(address)) {
                    request.reject()
                    webView.ownerWindow.openTab(address, null, false, webView)
                }
            }

            onPermissionRequested: function(permission) {
                if (permission.permissionType === CefPermission.PermissionType.Notifications) {
                    if (webView.notificationSource && Policy.isFigmaUrl(permission.origin)) permission.grant()
                    else permission.deny()
                    return
                }
                if (Policy.isFigmaUrl(permission.origin)
                        && (permission.permissionType === CefPermission.PermissionType.ClipboardReadWrite
                            || permission.permissionType === CefPermission.PermissionType.LocalFontsAccess
                            || permission.permissionType === CefPermission.PermissionType.LocalNetworkAccess))
                    permission.grant()
                else
                    permission.deny()
            }
        }
    }

    Component {
        id: googleWindowComponent

        Window {
            id: googleWindow
            objectName: "googleSignInWindow"
            readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
            property alias webContent: googleContent
            width: 520
            height: 680
            minimumWidth: 400
            minimumHeight: 500
            flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                                     : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
            title: qsTr("ReSketch — Google sign in")
            color: Kirigami.Theme.backgroundColor
            transientParent: null
            property var authView: null
            property var sourceView: null

            Item {
                id: googleContent
                anchors.fill: parent
                anchors.topMargin: googleHeader.height
                clip: true
            }

            ExternalWindowHeader {
                id: googleHeader
                targetWindow: googleWindow
                width: parent.width
                height: appSettings.windowControlsInTabBar ? implicitHeight : 0
                visible: height > 0
                title: qsTr("Google sign in")
                iconName: "dialog-password"
            }

            WindowResizeHandles {
                anchors.fill: parent
                active: googleWindow.framelessControls
                targetWindow: googleWindow
            }

            onClosing: {
                if (authView && authView.frameContainer) authView.frameContainer.destroy()
                Qt.callLater(() => googleWindow.destroy())
            }
        }
    }

    function refreshAfterGoogleSignIn(sourceView) {
        signInRefreshTimer.sourceView = sourceView
        signInRefreshTimer.restart()
    }

    function openGoogleSignInWindow(request, address, existingView, sourceView) {
        if (existingView && !existingView.pendingPopup) return
        const window = googleWindowComponent.createObject(root)
        if (!window)
            return
        const view = existingView || webViewComponent.createObject(window.webContent,
                                                   {googleSignIn: true, authWindow: window, visible: true})
        if (!view) {
            window.destroy()
            return
        }
        window.authView = view
        window.sourceView = sourceView || existingView?.popupSource || root.activeView
        if (existingView) {
            pendingPopups = pendingPopups.filter(popup => popup !== view)
            view.pendingPopup = false
            view.googleSignIn = true
            view.authWindow = window
            view.frameContainer.parent = window.webContent
            view.frameContainer.visible = true
            view.frameContainer.width = Qt.binding(() => window.webContent.width)
            view.frameContainer.height = Qt.binding(() => window.webContent.height)
            view.visible = true
        }
        if (request)
            view.acceptAsNewWindow(request)
        else if (!existingView)
            view.url = address
        window.show()
        window.raise()
        window.requestActivate()
    }

    function openPendingPopup(request, sourceView) {
        const view = createBrowserView()
        if (!view) return
        view.pendingPopup = true
        view.popupSource = sourceView
        view.popupBackground = request.destination === CefNewWindowRequest.InNewBackgroundTab
        pendingPopups = pendingPopups.concat(view)
        view.acceptAsNewWindow(request)
    }

    function discardPendingPopup(view) {
        if (!view || !view.pendingPopup) return
        view.pendingPopup = false
        pendingPopups = pendingPopups.filter(popup => popup !== view)
        view.frameContainer.destroy()
    }

    function commitPendingPopup(view) {
        if (!view || !view.pendingPopup) return
        view.pendingPopup = false
        pendingPopups = pendingPopups.filter(popup => popup !== view)
        openTab("", null, view.popupBackground, view.popupSource, view)
    }

    function openWebSignIn(sourceView) {
        if (homeView) {
            activateHome()
            Qt.callLater(() => homeView.url = loginUrl)
        }
        if (sourceView.authWindow) {
            const window = sourceView.authWindow
            Qt.callLater(() => window.close())
        }
    }

    function syncTab(view) {
        const index = views.indexOf(view)
        if (index < 0)
            return
        tabModel.setProperty(index, "filePage", Policy.isFileUrl(view.tabUrl))
        tabModel.setProperty(index, "newFilePage", Policy.isNewFileTabUrl(view.tabUrl))
        tabModel.setProperty(index, "title", Policy.pageLabel(view.tabUrl, view.title))
    }

    function syncTabLoading(view) {
        const index = views.indexOf(view)
        if (index < 0) return
        tabModel.setProperty(index, "loading", !String(view.deferredRestoreUrl) && view.loading)
        tabModel.setProperty(index, "progress", view.loading ? view.loadProgress : 100)
    }

    function syncFigmaTheme(view) {
        if (!view || view.loading || view.lifecycleState !== CefView.LifecycleState.Active
                || !Policy.isFigmaUrl(view.url))
            return
        view.runJavaScript(root.figmaAppearanceScript, () => {
            if (view) appSettings.repaintWebView(view)
        })
        view.syncNotifications()
    }

    function pollHomeNotifications() {
        const view = homeView
        if (!view || !view.notificationSource || view.loading || !Policy.isFileBrowserUrl(view.url)
                || notificationPolling || Date.now() - lastNotificationPoll < 1000) return
        lastNotificationPoll = Date.now()
        notificationPolling = true
        view.runJavaScript(NotificationPolicy.feedScript(FigmaMenu.storeSource), receiveHomeNotifications)
    }

    function receiveHomeNotifications(result) {
        let data
        try { data = JSON.parse(result) } catch (_) { notificationPolling = false; return }
        notificationPolling = !!data.pending
        if (!homeView?.notificationSource || !Policy.isFileBrowserUrl(homeView.url)) return
        for (const item of data.notifications || [])
            appSettings.showHomeNotification(item.title, item.body, item.url, root)
        if (data.refresh) pollHomeNotifications()
    }

    function openNotificationLink(address) {
        activateHome(false)
        if (Policy.isFileUrl(address)) openTab(address)
        else if (Policy.isFigmaUrl(address)) homeView.url = address
        else openExternalLink(address)
    }

    function handleDownload(download) {
        const view = download.view
        const key = Policy.fileKey(view ? view.url : download.url)
        const origin = {name: view ? Policy.pageLabel(view.url, view.title) : qsTr("Unknown origin"),
                        url: view ? String(view.url) : ""}
        const owner = view ? view.authWindow || view.ownerWindow : root
        const folder = appSettings.chooseExportFolder(key, download.suggestedFileName, owner)
        if (!folder) {
            download.cancel()
            return
        }
        download.downloadDirectory = folder
        exportOrigins[download.id] = origin
        download.accept()
    }

    function completeDownload(download) {
        const origin = exportOrigins[download.id] || {name: qsTr("Unknown origin"), url: ""}
        delete exportOrigins[download.id]
        if (download.state === CefDownload.DownloadCompleted)
            appSettings.recordExport(download.downloadDirectory, download.downloadFileName, origin.name, origin.url)
    }

    function handleExternalUrl(address) {
        if (address === "resketch:home") {
            activateHome()
            return
        }
        const target = Policy.deepLink(address)
        if (target) {
            openTab(target)
            return
        }
        const secret = Policy.redeemSecret(address)
        if (secret && homeView) {
            activateHome()
            homeView.url = "https://www.figma.com/app_auth/redeem?g_secret=" + encodeURIComponent(secret)
        }
    }

    onExternalUrlChanged: {
        if (externalUrl)
            handleExternalUrl(externalUrl)
    }

    function resetSlide() {
        tabSlide.stop()
        incomingSlide.target = null
        outgoingSlide.target = null
        outgoingView = null
        const allViews = homeView ? [homeView].concat(views) : views
        for (const view of allViews) {
            view.slideX = 0
            view.slideZ = 0
            view.visible = !allFrozen
                           && !String(view.deferredRestoreUrl)
                           && !view.memoryUnloaded
                           && (overviewVisible ? view.lifecycleState === CefView.LifecycleState.Active
                                                && !!view.frameContainer
                                                && !!view.frameContainer.previewCard
                                               : view === activeView)
        }
    }

    function detachOverviewFrame(view) {
        if (!view || !view.frameContainer || !view.frameContainer.previewCard)
            return
        view.visible = false
        view.frameContainer.previewCard = null
        view.frameContainer.parent = browserArea
    }

    function detachFrameForCard(card) {
        for (const view of [homeView].concat(views)) {
            if (!view)
                continue
            if (view.frameContainer && view.frameContainer.previewCard === card) {
                view.visible = false
                detachOverviewFrame(view)
            }
        }
    }

    function attachOverviewFrame(view) {
        if (!view || !view.frameContainer)
            return false
        const tabIndex = views.indexOf(view)
        if (view !== homeView && tabIndex < 0)
            return false
        const index = view === homeView ? 0 : tabIndex + 1
        const card = index >= 0 ? overviewCardRepeater.itemAt(index)?.card : null
        if (!card)
            return false
        const group = groupFor(view)
        const target = group?.overviewCollapsed ? overviewGroupContainer(group.id)?.previewSource(view) || card : card
        if (view.frameContainer.previewCard !== card || view.frameContainer.parent !== target) {
            detachFrameForCard(card)
            view.visible = false
            view.frameContainer.previewCard = card
            view.frameContainer.parent = target
        }
        view.visible = !view.memoryUnloaded && !String(view.deferredRestoreUrl)
            && view.lifecycleState === CefView.LifecycleState.Active
        return true
    }

    function restoreOverviewFrames() {
        for (const view of [homeView].concat(views)) {
            if (view)
                view.visible = false
            detachOverviewFrame(view)
        }
    }

    function syncOverviewFrames() {
        if (!overviewVisible)
            return
        for (const view of [homeView].concat(views))
            attachOverviewFrame(view)
    }

    function overviewSlot(view) {
        if (view === homeView)
            return -1
        const index = views.indexOf(view)
        return index < 0 ? -2 : index
    }

    function syncOverviewModel() {
        const items = homeView ? [homeView].concat(views) : views
        for (let i = overviewModel.count - 1; i >= 0; --i)
            if (!items.includes(overviewModel.get(i).previewView)) overviewModel.remove(i)
        for (let i = 0; i < items.length; ++i) {
            let existing = i
            while (existing < overviewModel.count && overviewModel.get(existing).previewView !== items[i]) ++existing
            if (existing === overviewModel.count) overviewModel.insert(i, {previewView: items[i]})
            else if (existing !== i) overviewModel.move(existing, i, 1)
        }
    }

    function overviewPreviewSlot(index) {
        return overviewFilteredSlot(index)
    }

    function layoutOverview(preview = true) {
        const items = [], groups = []
        let y = overviewMargin + overviewSearchHeight, column = 0, rowGroups = []
        const order = preview ? previewTabOrder() : views
        const visibleViews = (overviewMatches(-1) ? [homeView] : []).concat(order.filter(view => overviewMatches(views.indexOf(view))))
        const dragging = overviewDraggedView || (draggedTabIndex >= 0 ? views[draggedTabIndex] : null)
        const groupId = view => preview && dragging && view !== homeView
                                  && (dragViews.includes(view) || dragging === view)
                                  ? (overviewDraggedView ? overviewDropGroupId : tabDropGroupId) : view.tabGroupId || ""
        function flushRow() {
            if (!column) return
            y += overviewCardHeight + overviewGap
            column = 0
            for (const entry of rowGroups) {
                const expansion = overviewGroupContainer(entry.region.id)?.expansion
                                  ?? (entry.group.overviewCollapsed ? 0 : 1)
                const fullHeight = Math.ceil(entry.members.length / overviewColumns) * (overviewCardHeight + overviewGap)
                                   - overviewGap + 20
                entry.region.body = {x: overviewMargin - 10, y: y, height: fullHeight * expansion}
                entry.members.forEach((view, index) => items.push({view: view,
                    x: overviewMargin + index % overviewColumns * (overviewCardWidth + overviewGap),
                    y: y + 10 + Math.floor(index / overviewColumns) * (overviewCardHeight + overviewGap)}))
                y += (fullHeight + overviewGap) * expansion
            }
            rowGroups = []
        }
        function cell() {
            return {x: tabModel.count === 0 ? (browserArea.width - overviewCardWidth) / 2
                         : overviewMargin + column * (overviewCardWidth + overviewGap), y: y}
        }
        for (let first = 0; first < visibleViews.length;) {
            const id = groupId(visibleViews[first])
            let end = first + 1
            if (id) while (end < visibleViews.length && groupId(visibleViews[end]) === id) ++end
            const members = visibleViews.slice(first, end)
            const group = tabGroups.find(item => item.id === id)
            const position = cell()
            if (group) {
                const region = Object.assign({id: id, height: overviewCardHeight, count: members.length, collapsedCell: true}, position)
                groups.push(region)
                rowGroups.push({region: region, group: group, members: members})
            } else items.push(Object.assign({view: members[0]}, position))
            if (++column === overviewColumns) flushRow()
            first = end
        }
        flushRow()
        return {items: items, groups: groups,
                height: Math.max(overviewMargin + overviewSearchHeight, y - overviewGap + overviewMargin)
                        + Math.ceil(overviewClosingCardCount / overviewColumns) * (overviewCardHeight + overviewGap)}
    }

    function overviewGroupContainer(id) {
        const generation = overviewGroupGeneration
        return overviewGroupRepeater.itemAt(tabGroups.findIndex(group => group.id === id))
    }

    function overviewGroupDropTarget(point) {
        const layout = layoutOverview(false)
        let destination = 0
        for (let first = 0; first < views.length;) {
            const id = views[first].tabGroupId
            let end = first + 1
            if (id) while (end < views.length && views[end].tabGroupId === id) ++end
            if (id !== overviewDraggedGroupId) {
                const region = id ? layout.groups.find(item => item.id === id) : null
                const card = layout.items.find(item => item.view === views[first])
                if (region) {
                    if (region.collapsedCell
                        ? point.y < region.y || point.y < region.y + region.height && point.x < region.x + overviewCardWidth / 2
                        : point.y < region.y + region.height / 2) return destination
                } else if (card && (point.y < card.y || point.y < card.y + overviewCardHeight
                                                   && point.x < card.x + overviewCardWidth / 2)) {
                    return destination
                }
                destination += end - first
            }
            first = end
        }
        return destination
    }

    function overviewDropTarget(point) {
        let closest = views.indexOf(overviewDraggedView)
        let distance = Infinity
        const layout = layoutOverview(false)
        const inside = rect => rect && point.y >= rect.y && point.y <= rect.y + rect.height
            && point.x >= rect.x && point.x <= rect.x + rect.width
        const region = layout.groups.find(group => inside({x: group.x, y: group.y,
                                      width: overviewCardWidth, height: overviewCardHeight})
            || inside(Object.assign({width: browserArea.width - 2 * (overviewMargin - 10)}, group.body)))
        overviewDropGroupId = region?.id || ""
        for (let i = 0; i < views.length; ++i) {
            if (!overviewMatches(i) || views[i].tabGroupId !== overviewDropGroupId) continue
            const item = layout.items.find(item => item.view === views[i])
            const dx = point.x - item.x - overviewCardWidth / 2
            const dy = point.y - item.y - overviewCardHeight / 2
            const candidate = dx * dx + dy * dy
            if (candidate < distance) { distance = candidate; closest = i }
        }
        if (!region) {
            // Group boundaries are also insertion points, so leaving a group cannot split another one.
            const source = views.indexOf(overviewDraggedView)
            for (const group of layout.groups) {
                const first = views.findIndex(view => view.tabGroupId === group.id)
                const end = first + views.filter(view => view.tabGroupId === group.id).length
                for (const edge of [{index: first, y: group.y - overviewGap / 2},
                                    {index: end, y: group.y + group.height + overviewGap / 2}]) {
                    const dx = point.x - Math.max(overviewMargin, Math.min(point.x, browserArea.width - overviewMargin))
                    const candidate = dx * dx + Math.pow(point.y - edge.y, 2)
                    if (candidate < distance) {
                        distance = candidate
                        closest = Math.max(0, Math.min(views.length - 1, edge.index - (source < edge.index ? 1 : 0)))
                    }
                }
            }
        }
        return closest
    }

    function overviewMatches(slot) {
        const query = overviewSearch.text.trim().toLocaleLowerCase()
        if (slot === -1)
            return !!homeView && (!query || qsTr("Home").toLocaleLowerCase().includes(query))
        if (slot < 0)
            return false
        const view = views[slot]
        if (!view || view.overviewClosingCard)
            return false
        if (!query)
            return true
        const title = Policy.pageLabel(view.tabUrl, view.title)
        return title.toLocaleLowerCase().includes(query)
               || String(view.tabUrl).toLocaleLowerCase().includes(query)
    }

    function overviewFilteredCount() {
        let count = overviewMatches(-1) ? 1 : 0
        for (let slot = 0; slot < tabModel.count; ++slot)
            if (overviewMatches(slot))
                ++count
        return count
    }

    function overviewFilteredSlot(slot) {
        let position = 0
        for (let current = -1; current < slot; ++current)
            if (overviewMatches(current))
                ++position
        return position
    }

    function overviewCardX(slot) {
        const view = [homeView].concat(views).filter(view => overviewMatches(overviewSlot(view)))[slot]
        return overviewLayout.items.find(item => item.view === view)?.x ?? overviewMargin
    }

    function overviewCardY(slot) {
        const view = [homeView].concat(views).filter(view => overviewMatches(overviewSlot(view)))[slot]
        return overviewLayout.items.find(item => item.view === view)?.y ?? overviewMargin + overviewSearchHeight
    }

    function overviewNavigationCards() {
        const layout = layoutOverview(false)
        return layout.items.filter(item => item.view === homeView || !groupFor(item.view)?.overviewCollapsed
            && tabsForAction(item.view).includes(item.view))
            .map(item => ({target: item.view, x: item.x, y: item.y}))
            .concat(layout.groups.map(item => ({target: item.id, x: item.x, y: item.y})))
            .sort((a, b) => a.y - b.y || a.x - b.x)
    }

    function syncOverviewNavigation() {
        if (!overviewVisible || overviewClosing) return
        const cards = overviewNavigationCards()
        if (!cards.some(item => item.target === overviewNavigationTarget))
            overviewNavigationTarget = cards[0]?.target ?? null
    }

    function handleOverviewInput(event) {
        if (!overviewVisible || keyboardPopupActive) return
        const sequence = appSettings.keyEventSequence(event.key, event.modifiers)
        const action = Shortcuts.items.find(item => (item.category === "Overview" || item.category === "Selection")
            && sequence && appSettings.shortcutSequenceText(Shortcuts.sequence(appSettings, item.id)) === sequence)
        if (!action) return
        if (action.category === "Selection") {
            if (!selectionShortcutAvailable) return
            event.accepted = true
            actOnSelectedItems(action.id)
        } else {
            const keys = {Left: Qt.Key_Left, Right: Qt.Key_Right, Up: Qt.Key_Up,
                          Down: Qt.Key_Down, Return: Qt.Key_Return, Enter: Qt.Key_Enter}
            const navigation = {key: keys[action.key], modifiers: action.range ? Qt.ShiftModifier : Qt.NoModifier,
                                accepted: false}
            handleOverviewKey(navigation)
            event.accepted = navigation.accepted
        }
    }

    function handleOverviewKey(event) {
        if (!overviewVisible || overviewClosing
                || overviewDraggedView || draggedGroupId
                || event.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) return
        const horizontal = event.key === Qt.Key_Left || event.key === Qt.Key_Right
        const vertical = event.key === Qt.Key_Up || event.key === Qt.Key_Down
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        if (!horizontal && !vertical && !enter || enter && event.modifiers & Qt.ShiftModifier) return
        event.accepted = true
        const cards = overviewNavigationCards()
        if (!cards.length) return
        const current = cards.find(item => item.target === overviewNavigationTarget)
        let next = current || cards[0]
        if (enter) {
            overviewNavigationTarget = next.target
            if (typeof next.target === "string") {
                const group = tabGroups.find(item => item.id === next.target)
                updateTabGroup(group.id, {overviewCollapsed: !group.overviewCollapsed})
            } else selectOverviewView(next.target)
            return
        }
        if (current) {
            const direction = event.key === Qt.Key_Left || event.key === Qt.Key_Up ? -1 : 1
            if (horizontal) {
                const index = Math.max(0, Math.min(cards.length - 1, cards.indexOf(current) + direction))
                next = cards[index]
            } else {
                let nearest = Infinity
                for (const card of cards) {
                    const along = card.y - current.y
                    const across = card.x - current.x
                    if (direction * along <= 1) continue
                    const distance = Math.abs(along) * browserArea.width + Math.abs(across)
                    if (distance < nearest) { nearest = distance; next = card }
                }
            }
        }
        let selectionCards = [next]
        if (event.modifiers & Qt.ShiftModifier) {
            let anchor = cards.findIndex(card => card.target === overviewRangeAnchor)
            if (anchor < 0) {
                overviewRangeAnchor = current?.target ?? next.target
                anchor = current ? cards.indexOf(current) : cards.indexOf(next)
            }
            const end = cards.indexOf(next)
            selectionCards = cards.slice(Math.min(anchor, end), Math.max(anchor, end) + 1)
        } else overviewRangeAnchor = null
        const candidates = selectionCards.reduce((result, card) => result.concat(typeof card.target === "string"
            ? views.filter(view => view.tabGroupId === card.target)
            : card.target === homeView && next.target !== homeView ? [] : [card.target]), [])
        rangeSelectionAnchor = null
        rangeSelectionBase = []
        selectedTabViews = Array.from(new Set(candidates)).filter(view => view &&
            (view === homeView || views.includes(view) && !pendingCloseViews.includes(view)
             && !closingViews.includes(view) && !readyCloseViews.includes(view) && !view.overviewClosingCard))
        selectedGroupIds = selectionCards.filter(card => typeof card.target === "string").map(card => card.target)
        overviewNavigationTarget = next.target
        overviewFlickable.cancelFlick()
        const position = overviewWheelScroll.running ? overviewFlickable.wheelTargetY : overviewFlickable.contentY
        const top = overviewMargin + overviewSearchHeight
        let scroll = position
        if (next.y < position + top) scroll = next.y - top
        else if (next.y + overviewCardHeight > position + overviewFlickable.height - overviewMargin)
            scroll = next.y + overviewCardHeight - overviewFlickable.height + overviewMargin
        if (scroll !== position) overviewFlickable.scrollBy(position - scroll, false)
    }

    function toggleOverview() {
        if (allFrozen || !activeView)
            return
        if (overviewVisible) {
            if (overviewClosing) {
                overviewFinishTimer.stop()
                overviewAnimation.stop()
                overviewClosing = false
                overviewAnimation.from = overviewProgress
                overviewAnimation.to = 1
                overviewAnimation.start()
            } else {
                if (overviewMatches(overviewSlot(activeView)))
                    selectOverviewView(activeView)
                else
                    dismissOverview()
            }
            return
        }
        resetSlide()
        selectionGlide.stop()
        homeSelectionGlide = false
        selectionBar.startOffset = 0
        selectionBar.endOffset = 0
        pendingOverviewSelection = null
        overviewSelectedView = activeView
        const selectedGroup = groupFor(activeView) || tabGroups.find(group => !group.overviewCollapsed)
        if (selectedGroup)
            updateTabGroup(selectedGroup.id, {overviewCollapsed: false}, true)
        overviewClosing = false
        overviewProgress = 0
        overviewSearch.text = ""
        const selectedCardY = overviewCardY(overviewFilteredSlot(overviewSlot(activeView)))
        overviewFlickable.resetScroll(selectedCardY - (overviewFlickable.height - overviewCardHeight) / 2)
        overviewVisible = true
        overviewSearch.forceActiveFocus()
        overviewNavigationTarget = activeView
        for (const view of [homeView].concat(views)) {
            if (!view)
                continue
            attachOverviewFrame(view)
        }
        updateTabLifecycle()
        if (appSettings.reduceMotion) {
            overviewProgress = 1
            overviewSearch.forceActiveFocus()
        } else {
            overviewAnimation.from = 0
            overviewAnimation.to = 1
            overviewAnimation.start()
        }
    }

    function selectOverviewView(target) {
        if (!target || (target !== homeView && views.indexOf(target) < 0))
            return
        selectedTabViews = []
        if (!overviewVisible) {
            activateView(target, target === homeView ? -1 : views.indexOf(target))
            return
        }
        if (overviewAnimationRunning && !overviewClosing) {
            // Retain early choices without changing the card that is scaling out.
            pendingOverviewSelection = target
            overviewNavigationTarget = target
            return
        }
        pendingOverviewSelection = null
        target.memoryUnloaded = false
        target.requestedSleepState = CefView.LifecycleState.Active
        target.lifecycleState = CefView.LifecycleState.Active
        target.lastUsedAt = Date.now()
        loadRestoredTab(target)
        for (const view of [homeView].concat(views))
            view.finishOverviewEntrance()
        overviewFinishTimer.stop()
        overviewAnimation.stop()
        overviewWheelScroll.stop()
        overviewFlickable.wheelTargetY = overviewFlickable.contentY
        overviewSelectedView = target
        selectTabInStrip(target, target === homeView ? -1 : views.indexOf(target))
        overviewClosing = true
        if (appSettings.reduceMotion) {
            overviewProgress = 0
            finishOverviewTransition()
        } else {
            overviewAnimation.from = overviewProgress
            overviewAnimation.to = 0
            overviewAnimation.start()
        }
    }

    function finishOverviewTransition() {
        if (!overviewClosing || overviewProgress > 0.001)
            return
        const target = overviewSelectedView
        overviewVisible = false
        pendingOverviewSelection = null
        restoreOverviewFrames()
        for (const view of views.slice())
            if (view.overviewClosingCard)
                finishOverviewClose(view)
        const index = target === homeView ? -1 : views.indexOf(target)
        overviewClosing = false
        overviewSelectedView = null
        overviewProgress = 0
        if (index < 0 && target !== homeView) {
            resetSlide()
            updateTabLifecycle()
            return
        }
        skipNextWebSlide = true
        activateView(target, index)
    }

    function dismissOverview() {
        if (!overviewVisible)
            return
        overviewFinishTimer.stop()
        overviewAnimation.stop()
        overviewVisible = false
        pendingOverviewSelection = null
        restoreOverviewFrames()
        for (const view of views.slice())
            if (view.overviewClosingCard)
                finishOverviewClose(view)
        overviewClosing = false
        overviewSelectedView = null
        overviewProgress = 0
        for (const view of views)
            view.finishOverviewEntrance()
        resetSlide()
        updateTabLifecycle()
    }

    function finishSlide() {
        if (outgoingView) {
            outgoingView.visible = false
            outgoingView.slideX = 0
            outgoingView.slideZ = 0
        }
        if (activeView) {
            activeView.slideX = 0
            activeView.slideZ = 0
        }
        outgoingView = null
        incomingSlide.target = null
        outgoingSlide.target = null
        updateTabLifecycle()
    }

    function updateTabLifecycle() {
        const protectedHome = homeMustStayAwake ? homeView : null
        if (protectedHome) {
            protectedHome.memoryUnloaded = false
            protectedHome.requestedSleepState = CefView.LifecycleState.Active
            if (protectedHome.lifecycleState !== CefView.LifecycleState.Active)
                protectedHome.lifecycleState = CefView.LifecycleState.Active
            if (protectedHome.reloadAfterFreeze) {
                protectedHome.reloadAfterFreeze = false
                protectedHome.reload()
            }
            if (overviewVisible) attachOverviewFrame(protectedHome)
        }
        if (allFrozen)
            return
        const background = [homeView].concat(views).filter(view => view && view !== activeView
                                   && view !== outgoingView && view !== protectedHome && !view.overviewClosingCard)
        background.sort((a, b) => b.lastUsedAt - a.lastUsedAt)
        const now = Date.now()
        const liveOverview = overviewVisible && !appSettings.sleepingTabPreviews
        const limit = appSettings.maximumLoadedTabs
        const foreground = (activeView ? 1 : 0) + (outgoingView && outgoingView !== activeView ? 1 : 0)
                         + (protectedHome && protectedHome !== activeView && protectedHome !== outgoingView ? 1 : 0)
        const maxBackground = Math.max(0, limit - foreground)
        const minimumBackground = Math.max(0, appSettings.minimumLoadedTabs - foreground)
        let awake = 0
        for (const view of background) {
            if (String(view.deferredRestoreUrl) || view.memoryUnloaded) continue
            if (overviewVisible && appSettings.sleepingTabPreviews
                    && view.lifecycleState !== CefView.LifecycleState.Active)
                continue
            const recent = now - view.lastUsedAt < appSettings.sleepMinutes * 60 * 1000
            const discarded = view.lifecycleState === CefView.LifecycleState.Discarded
            const fillMinimum = awake < minimumBackground
            const keepAwake = liveOverview || (awake < maxBackground
                              && (view.loading || fillMinimum || overviewVisible || (!discarded && recent)))
            if (keepAwake) {
                ++awake
                view.requestedSleepState = CefView.LifecycleState.Active
                if (view.lifecycleState !== CefView.LifecycleState.Active)
                    view.lifecycleState = CefView.LifecycleState.Active
                if (view.reloadAfterFreeze) {
                    view.reloadAfterFreeze = false
                    view.reload()
                }
                if (overviewVisible) attachOverviewFrame(view)
            } else {
                // Chromium cannot freeze a visible page. Hide only the webview;
                // its overview card and saved preview remain in place.
                view.visible = false
                if (view.loading) {
                    view.reloadAfterFreeze = true
                    view.stop()
                }
                if (view.lifecycleState === CefView.LifecycleState.Active)
                    sleepTab(view, CefView.LifecycleState.Frozen)
            }
        }
    }

    function memoryUnloadEligible(view) {
        return !!view && (view === homeView ? !homeMustStayAwake : views.includes(view))
            && view !== activeView && view !== outgoingView && view !== overviewSelectedView
            && !dragViews.includes(view) && view !== dragView && view !== tabDragSession?.view && !view.devToolsView
            && !view.memoryUnloaded && !String(view.deferredRestoreUrl)
            && view.lifecycleState !== CefView.LifecycleState.Discarded
            && !view.overviewClosingCard && !pendingCloseViews.includes(view) && !closingViews.includes(view)
    }

    function unloadTabForMemory(view) {
        if (!memoryUnloadEligible(view)) return false
        view.memoryUnloaded = true
        view.visible = false
        view.reloadAfterFreeze = false
        if (view.loading) view.stop()
        sleepTab(view, CefView.LifecycleState.Discarded)
        return true
    }

    function sleepTab(view, state) {
        if (view === homeView && homeMustStayAwake) {
            view.requestedSleepState = CefView.LifecycleState.Active
            return
        }
        view.requestedSleepState = state
        if (view.sleepCapturePending) return
        if (!appSettings.sleepingTabPreviews || !view.hasLoadedFrame
                || view.lifecycleState !== CefView.LifecycleState.Active) {
            view.lifecycleState = state
            return
        }
        view.sleepCapturePending = true
        const serial = ++view.sleepCaptureSerial
        const address = String(view.url)
        const scale = Math.min(1, 640 / Math.max(1, view.width), 480 / Math.max(1, view.height))
        const size = Qt.size(Math.max(1, Math.round(view.width * scale)),
                             Math.max(1, Math.round(view.height * scale)))
        if (!view.grabToImage(result => root.finishTabSleep(view, result, address, serial), size))
            finishTabSleep(view, null, address, serial)
    }

    function finishTabSleep(view, preview, address, serial) {
        if (!view || view.ownerWindow !== root || !view.sleepCapturePending
                || view.sleepCaptureSerial !== serial) return
        view.sleepCapturePending = false
        if ((view !== homeView && !views.includes(view))
                || (view === homeView && homeMustStayAwake)
                || String(view.url) !== address || view.loading
                || (!allFrozen && (view.visible || view === activeView || view === outgoingView))
                || view.requestedSleepState === CefView.LifecycleState.Active) {
            view.memoryUnloaded = false
            return
        }
        if (preview && appSettings.sleepingTabPreviews) view.sleepPreview = preview
        view.lifecycleState = view.requestedSleepState
    }

    function freezeAllTabs() {
        if (allFrozen)
            return
        dismissOverview()
        allFrozen = true
        resetSlide()
        for (const view of [homeView].concat(views)) {
            if (!view)
                continue
            if (view === homeView && homeMustStayAwake)
                continue
            if (view.loading) {
                view.reloadAfterFreeze = true
                view.stop()
            }
            if (!view.loading)
                sleepTab(view, CefView.LifecycleState.Frozen)
        }
    }

    function wakeCurrentTab() {
        if (allFrozen) {
            if (activeIndex < 0)
                activateHome()
            else
                activateTab(activeIndex)
        }
    }

    function openSettings() {
        settingsWindowLoader.openWindow()
    }

    function triggerToolbarItem(id, button) {
        switch (id) {
        case "new-tab": openTab(newTabUrl); break
        case "overview": toggleOverview(); break
        case "refresh": triggerPageAction(CefView.Reload); break
        case "menu": appMenu.popup(button, button.width - appMenu.width, button.height); break
        case "export-history": openExportHistory(); break
        case "settings": openSettings(); break
        case "task-manager": openTaskManager(); break
        case "developer-tools": openDeveloperTools(); break
        }
    }

    Controls.Menu {
        id: toolbarContextMenu
        objectName: "toolbarContextMenu"
        Controls.MenuItem {
            text: qsTr("Configure toolbar…")
            icon.name: "configure"
            onTriggered: {
                root.openSettings()
                settingsWindowLoader.item.selectedSection = 4
            }
        }
    }

    function openTaskManager() {
        taskManagerWindowLoader.openWindow()
        taskManagerWindowLoader.item.refreshTasks()
    }

    function openDeveloperTools() {
        if (!activeView) return
        developerToolsWindowLoader.openWindow()
        developerToolsWindowLoader.item.inspectedView = activeView
    }

    function openExternalLink(address) {
        if (Policy.isExternalWebUrl(address))
            Qt.openUrlExternally(address)
    }

    function openExportHistory() {
        exportHistoryWindowLoader.openWindow()
    }

    function triggerHomeMenuAction(command) {
        if (command === "reload") {
            if (!allFrozen) triggerPageAction(CefView.Reload)
        } else if (command === "overview") {
            toggleOverview()
        } else if (command === "about") {
            openAbout()
        } else if (["theme-auto", "theme-light", "theme-dark"].indexOf(command) >= 0) {
            appSettings.theme = command.slice(6)
        } else {
            const links = {
                help: "https://help.figma.com",
                forum: "https://forum.figma.com",
                tutorials: "https://www.youtube.com/figmadesign",
                releases: "https://www.figma.com/releases",
                legal: "https://www.figma.com/legal"
            }
            if (links[command]) Qt.openUrlExternally(links[command])
        }
    }

    function openAbout() {
        aboutWindowLoader.openWindow()
    }

    function refreshTab(index) {
        if (index < 0 || index >= views.length || allFrozen)
            return
        const view = views[index]
        view.memoryUnloaded = false
        view.requestedSleepState = CefView.LifecycleState.Active
        if (String(view.deferredRestoreUrl)) {
            loadRestoredTab(view)
            return
        }
        const discarded = view.lifecycleState === CefView.LifecycleState.Discarded
        view.lifecycleState = CefView.LifecycleState.Active
        if (!discarded)
            view.reload()
    }

    function createDetachedWindow(address, profile, position) {
        const component = Qt.createComponent(Qt.resolvedUrl("Main.qml"))
        if (component.status !== Component.Ready) {
            console.warn(component.errorString())
            return null
        }
        const window = component.createObject(null, {
            primaryWindow: root,
            sharedProfile: profile,
            startupUrl: address,
            width: root.width,
            height: root.height
        })
        if (!window) {
            console.warn(component.errorString())
            return null
        }
        detachedWindows = detachedWindows.concat(window)
        if (position) {
            window.x = position.x - 80
            window.y = position.y - 20
        }
        window.raise()
        window.requestActivate()
        return window
    }

    function moveTabToNewWindow(index, position) {
        if (views.length <= 1 || index < 0 || index >= views.length)
            return null
        const view = views[index]
        if (view.overviewClosingCard || pendingCloseViews.includes(view)
                || closingViews.includes(view) || readyCloseViews.includes(view))
            return null
        const owner = primaryWindow || root
        const window = owner.createDetachedWindow("", view.profile, position)
        if (!window) return null
        transferTabToWindow(index, window)
        return window
    }

    function transferTabToWindow(index, window) {
        const view = views[index]
        if (!view || !window || window === root || !window.visible
                || window.browserProfile !== view.profile
                || view.overviewClosingCard || pendingCloseViews.includes(view)
                || closingViews.includes(view) || readyCloseViews.includes(view))
            return false
        const selected = activeView === view
        const next = views[nextAvailableTab(index)] || homeView
        resetSlide()
        detachOverviewFrame(view)
        view.visible = false
        view.finishOverviewEntrance()
        finishTabOpening(view)
        if (selected) activeView = next
        if (overviewSelectedView === view) overviewSelectedView = activeView
        views = views.filter(item => item !== view)
        tabModel.remove(index)
        tabBar.currentIndex = activeIndex
        if (selected && !overviewVisible)
            activateView(next, activeIndex, false)
        else {
            resetSlide()
            Qt.callLater(root.syncOverviewFrames)
            updateTabLifecycle()
        }
        window.adoptTransferredView(view)
        if (!views.length) Qt.callLater(() => root.close())
        return true
    }

    function adoptTransferredView(view) {
        const frame = view.frameContainer
        frame.previewCard = null
        frame.ownerWindow = root
        frame.parent = browserArea
        view.ownerWindow = root
        view.tabGroupId = ""
        view.sleepCapturePending = false
        view.memoryUnloaded = false
        view.requestedSleepState = CefView.LifecycleState.Active
        view.tabOpening = false
        views = views.concat(view)
        tabModel.append({tabView: view, title: Policy.pageLabel(view.tabUrl, view.title),
                         filePage: Policy.isFileUrl(view.tabUrl), newFilePage: Policy.isNewFileTabUrl(view.tabUrl),
                         loading: view.loading, progress: view.loading ? view.loadProgress : 100,
                         animateOpen: false})
        if (overviewVisible) {
            loadRestoredTab(view)
            activeView = view
            overviewSelectedView = view
            tabBar.currentIndex = activeIndex
            view.lifecycleState = CefView.LifecycleState.Active
            view.visible = attachOverviewFrame(view)
            Qt.callLater(root.syncOverviewFrames)
            updateTabLifecycle()
        } else activateTab(views.length - 1, false)
    }

    function outsideWindow(point) {
        return point.x < 0 || point.y < 0 || point.x >= width || point.y >= height
    }

    function beginItemDrag(view, item, point) {
        cancelItemDrag()
        dragView = view
        const members = tabsForAction(view)
        dragViews = views.filter(item => members.includes(item))
        dragScenePosition = point
        dragToken = Date.now().toString(36) + Math.random().toString(36).slice(2)
        const owner = primaryWindow || root
        const token = dragToken
        owner.tabDragSession = {token: token, sourceWindow: root, view: view, targetWindow: null}
        const scale = Math.min(1, 280 / Math.max(1, item.width), 200 / Math.max(1, item.height))
        dragPreviewSize = Qt.size(Math.max(1, Math.round(item.width * scale)), Math.max(1, Math.round(item.height * scale)))
        item.grabToImage(result => {
            if (root.dragToken !== token) return
            root.dragSnapshot = result
            if (root.nativeTabDragRequested) root.startNativeTabDrag()
        }, dragPreviewSize)
    }

    function updateItemDrag(point) {
        dragScenePosition = point
        if (!dragView || nativeTabDragRunning) return
        nativeTabDragRequested = appSettings.nativeTabDragSupported && outsideWindow(point)
        if (nativeTabDragRequested && dragSnapshot) startNativeTabDrag()
    }

    function startNativeTabDrag() {
        const token = dragToken
        Qt.callLater(() => {
            if (!root.dragView || root.dragToken !== token || !root.nativeTabDragRequested
                    || root.nativeTabDragRunning || !root.outsideWindow(root.dragScenePosition)) return
            root.nativeTabDragRunning = true
            if (root.overviewDraggedView) {
                const card = overviewCardRepeater.itemAt(root.views.indexOf(root.overviewDraggedView) + 1)?.card
                if (card) { card.dragOffsetX = 0; card.dragOffsetY = 0 }
            }
            root.draggedTabIndex = -1
            root.tabDropIndex = -1
            root.overviewDraggedView = null
            root.overviewDropIndex = -1
            nativeDragProxy.Drag.active = true
            nativeDragProxy.Drag.startDrag(Qt.MoveAction)
        })
    }

    function canAcceptTabDrop(token) {
        const session = (primaryWindow || root).tabDragSession
        return !!session && session.token === token
               && root.visible && session.view && session.view.ownerWindow === session.sourceWindow
               && session.sourceWindow.views.includes(session.view) && session.view.profile === browserProfile
    }

    function acceptTabDrop(token) {
        if (!canAcceptTabDrop(token)) return false
        const owner = primaryWindow || root
        owner.tabDragSession.targetWindow = root
        return true
    }

    function windowAtDrop(position) {
        const owner = primaryWindow || root
        for (const window of [owner].concat(owner.detachedWindows).reverse()) {
            if (window === root || !window.visible) continue
            const point = window.contentItem.mapFromGlobal(position.x, position.y)
            if (point.x >= 0 && point.y >= 0 && point.x < window.width && point.y < window.height)
                return window
        }
        return null
    }

    function finishItemDrag(point) {
        const position = root.contentItem.mapToGlobal(point.x, point.y)
        const view = dragView
        const owner = primaryWindow || root
        const target = owner.tabDragSession?.targetWindow || windowAtDrop(position)
        cancelItemDrag()
        if (!view) return
        Qt.callLater(() => {
            const index = root.views.indexOf(view)
            if (target) root.transferTabToWindow(index, target)
            else root.moveTabToNewWindow(index, position)
        })
    }

    function finishNativeTabDrag(action) {
        const owner = primaryWindow || root
        const target = owner.tabDragSession?.targetWindow
        const view = dragView
        const position = appSettings.cursorPosition()
        const droppedOutside = outsideWindow(dragScenePosition)
        cancelItemDrag()
        if (!view) return
        Qt.callLater(() => {
            const index = root.views.indexOf(view)
            if (target && action === Qt.MoveAction) root.transferTabToWindow(index, target)
            else if (action === Qt.IgnoreAction
                     || (!target && action === Qt.MoveAction && droppedOutside))
                root.moveTabToNewWindow(index, position)
        })
    }

    function cancelItemDrag() {
        nativeDragProxy.Drag.active = false
        const owner = primaryWindow || root
        if (owner.tabDragSession?.sourceWindow === root) owner.tabDragSession = null
        dragView = null
        dragViews = []
        dragSnapshot = null
        dragToken = ""
        nativeTabDragRequested = false
        nativeTabDragRunning = false
    }

    function toggleMaximize() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
    }

    function toggleWebFullscreen() {
        if (!webFullscreen) {
            visibilityBeforeFullscreen = visibility
            autoHideBeforeFullscreen = autoHideToolbar
            autoHideToolbar = true
            fullscreenToolbarHovered = false
            showFullScreen()
        } else {
            autoHideToolbar = autoHideBeforeFullscreen
            fullscreenToolbarHovered = false
            if (visibilityBeforeFullscreen === Window.Maximized) showMaximized()
            else showNormal()
        }
    }

    function toggleToolbarAutoHide() {
        autoHideToolbar = !autoHideToolbar
        fullscreenToolbarHovered = false
    }

    function selectFileTabs(view, modifiers, inOverview) {
        overviewRangeAnchor = null
        selectedGroupIds = selectedGroupIds.filter(id => id !== view?.tabGroupId)
        if (!view || (view !== homeView && !views.includes(view))) return
        if (view !== homeView && (pendingCloseViews.includes(view) || closingViews.includes(view)
                                 || readyCloseViews.includes(view) || view.overviewClosingCard)) return
        if (modifiers & Qt.ShiftModifier) {
            if (view === homeView) return
            if (modifiers & Qt.AltModifier) {
                if (!rangeSelectionAnchor || !views.includes(rangeSelectionAnchor)) {
                    rangeSelectionAnchor = view
                    rangeSelectionBase = selectedTabViews.slice()
                }
                const start = views.indexOf(rangeSelectionAnchor), end = views.indexOf(view)
                const range = views.slice(Math.min(start, end), Math.max(start, end) + 1)
                selectedTabViews = Array.from(new Set(rangeSelectionBase.concat(range)))
                    .filter(item => views.includes(item) && !pendingCloseViews.includes(item)
                        && !closingViews.includes(item) && !readyCloseViews.includes(item) && !item.overviewClosingCard)
            } else {
                rangeSelectionAnchor = null
                rangeSelectionBase = []
                selectedTabViews = selectedTabViews.includes(view)
                    ? selectedTabViews.filter(item => item !== view) : selectedTabViews.concat(view)
            }
            return
        }
        selectedTabViews = []
        if (inOverview) selectOverviewView(view)
        else if (activeView !== view || allFrozen || overviewVisible && !overviewClosing) {
            if (view === homeView) activateHome()
            else activateTab(views.indexOf(view))
        }
    }

    function pointInsideItem(item, point) {
        if (!item || !item.visible) return false
        const local = item.mapFromItem(root.contentItem, point.x, point.y)
        return item.contains(local)
    }

    function selectionSurfaceAt(point) {
        if (overviewVisible) {
            for (let i = 0; i < overviewCardRepeater.count; ++i)
                if (pointInsideItem(overviewCardRepeater.itemAt(i)?.card, point)) return true
            for (let i = 0; i < overviewGroupRepeater.count; ++i)
                if (pointInsideItem(overviewGroupRepeater.itemAt(i)?.selectionHeader, point)) return true
        }
        for (let i = 0; i < tabRepeater.count; ++i)
            if (pointInsideItem(tabRepeater.itemAt(i), point)) return true
        for (let i = 0; i < groupHeaderRepeater.count; ++i)
            if (pointInsideItem(groupHeaderRepeater.itemAt(i), point)) return true
        return false
    }

    function selectOverviewRectangle(area, initialSelection) {
        const selected = initialSelection.slice()
        for (let i = 0; i < overviewCardRepeater.count; ++i) {
            const card = overviewCardRepeater.itemAt(i)?.card
            if (!card || !card.visible || card.closing || card.previewView === homeView
                    || !overviewMatches(card.tabIndex) || card.group?.overviewCollapsed
                    || !tabsForAction(card.previewView).includes(card.previewView)) continue
            const origin = card.mapToItem(overviewFlickable.contentItem, 0, 0)
            if (origin.x < area.x + area.width && origin.x + card.width > area.x
                    && origin.y < area.y + area.height && origin.y + card.height > area.y
                    && !selected.includes(card.previewView)) selected.push(card.previewView)
        }
        selectedTabViews = selected
    }

    function tabsForAction(view) {
        return (selectedTabViews.includes(view) ? selectedTabViews : [view])
            .filter(item => item && views.includes(item) && !pendingCloseViews.includes(item)
                            && !closingViews.includes(item) && !readyCloseViews.includes(item) && !item.overviewClosingCard)
    }

    function selectGroupForAction(id, modifiers) {
        overviewRangeAnchor = null
        rangeSelectionAnchor = null
        rangeSelectionBase = []
        if (!(modifiers & Qt.ShiftModifier)) {
            selectedTabViews = []
            return false
        }
        const members = views.filter(view => view.tabGroupId === id && !view.overviewClosingCard)
        const selected = selectedGroupIds.includes(id)
        const groups = selected ? selectedGroupIds.filter(group => group !== id) : selectedGroupIds.concat(id)
        selectedTabViews = selected ? selectedTabViews.filter(view => !members.includes(view))
                                   : Array.from(new Set(selectedTabViews.concat(members)))
        selectedGroupIds = groups
        if (overviewVisible) overviewNavigationTarget = id
        return true
    }

    function actOnSelectedItems(action) {
        const groups = selectedGroupIds.filter(id => tabGroups.some(group => group.id === id))
        const tabs = selectedTabViews.filter(view => views.includes(view)
            && !groups.includes(view.tabGroupId) && !pendingCloseViews.includes(view)
            && !closingViews.includes(view) && !readyCloseViews.includes(view) && !view.overviewClosingCard)
        if (action === "group-selection") {
            if (!groups.length && tabs.length) requestTabGroup(tabs[0])
            else if (groups.length === 1 && tabs.length) {
                for (const view of tabs) assignTabGroup(view, groups[0])
            } else if (groups.length && !tabs.length) {
                selectedTabViews = []
                for (const id of groups) ungroupTabs(id)
            }
            return
        }
        selectedTabViews = []
        for (const id of groups) {
            if (action === "close-selection") closeTabGroup(id)
            else ungroupTabs(id)
        }
        for (const view of tabs) closeTab(views.indexOf(view))
    }

    function closeSelectedTabs(view) {
        for (const target of tabsForAction(view)) closeTab(views.indexOf(target))
    }

    function refreshSelectedTabs(view) {
        for (const target of tabsForAction(view)) refreshTab(views.indexOf(target))
    }

    function assignSelectedTabGroup(view, id) {
        for (const target of tabsForAction(view)) assignTabGroup(target, id)
    }

    function triggerPageAction(action) {
        if (activeView)
            activeView.triggerWebAction(action)
    }

    function activateHome(animateWebSlide) {
        if (homeView)
            activateView(homeView, -1, animateWebSlide)
    }

    function activateTab(index, animateWebSlide) {
        if (index < 0 || index >= views.length)
            return
        const view = views[index]
        if (pendingCloseViews.indexOf(view) >= 0 || closingViews.indexOf(view) >= 0
                || readyCloseViews.indexOf(view) >= 0 || view.overviewClosingCard)
            return
        activateView(view, index, animateWebSlide)
    }

    function cycleTab(direction) {
        const count = views.length + 1
        if (count < 2)
            return
        for (let step = 1; step < count; ++step) {
            const position = (activeIndex + 1 + direction * step + count) % count
            if (position === 0) {
                activateHome()
                return
            }
            const view = views[position - 1]
            if (pendingCloseViews.indexOf(view) < 0 && closingViews.indexOf(view) < 0
                    && readyCloseViews.indexOf(view) < 0) {
                activateTab(position - 1)
                return
            }
        }
    }

    function selectTabInStrip(next, index) {
        const group = groupFor(next)
        if (group && group.collapsed) updateTabGroup(group.id, {collapsed: false})
        const previous = activeView
        const previousIndex = activeIndex
        const waitForOpening = !appSettings.reduceMotion && !!next.tabOpening
        const animateSelection = previous && previous !== next && selectionBar.visible
                                 && !appSettings.reduceMotion && !allFrozen
        const oldLeft = animateSelection ? selectionBar.x : 0
        const oldRight = animateSelection ? selectionBar.x + selectionBar.width : 0
        selectionGlide.stop()
        homeSelectionGlide = animateSelection && (previous === homeView || next === homeView)
        activeView = next
        tabBar.currentIndex = index
        wheelScroll.stop()
        tabsViewport.smoothWheel = false
        if (index >= 0) {
            const left = tabStripTabPosition(index)
            const right = left + tabWidth
            if (left < tabsViewport.contentX)
                tabsViewport.scrollBy(tabsViewport.contentX - left, false)
            else if (right > tabsViewport.contentX + tabsViewport.width)
                tabsViewport.scrollBy(tabsViewport.contentX - Math.max(0, right - tabsViewport.width), false)
        }
        heldOpenSelection = waitForOpening ? next : null
        hideHeldSelection = !!waitForOpening && !animateSelection
        if (animateSelection) {
            const newLeft = selectionBar.targetX
            const newRight = newLeft + selectionBar.targetWidth
            selectionBar.startOffset = oldLeft - newLeft
            selectionBar.endOffset = oldRight - newRight
            selectionStretch.property = index > previousIndex ? "endOffset" : "startOffset"
            selectionContract.property = index > previousIndex ? "startOffset" : "endOffset"
            if (!waitForOpening)
                selectionGlide.start()
        } else if (previous !== next || index < 0 || appSettings.reduceMotion) {
            selectionBar.startOffset = 0
            selectionBar.endOffset = 0
        }
    }

    function activateView(next, index, animateWebSlide) {
        selectedTabViews = []
        if (overviewVisible) {
            selectOverviewView(next)
            return
        }
        const allowWebSlide = !skipNextWebSlide && animateWebSlide !== false
        skipNextWebSlide = false
        const previous = activeView
        const previousIndex = activeIndex
        const frozen = allFrozen
        resetSlide()
        if (previous !== next || frozen)
            selectTabInStrip(next, index)
        else
            tabBar.currentIndex = index
        allFrozen = false
        next.lastUsedAt = Date.now()
        next.memoryUnloaded = false
        next.requestedSleepState = CefView.LifecycleState.Active
        next.lifecycleState = CefView.LifecycleState.Active
        loadRestoredTab(next)
        if (next.reloadAfterFreeze) {
            next.reloadAfterFreeze = false
            next.reload()
        }
        tabBar.currentIndex = index
        if (previous && previous !== next && browserArea.width > 0
                && !appSettings.reduceMotion && allowWebSlide && !frozen) {
            const direction = index > previousIndex ? 1 : -1
            const distance = browserArea.width
            outgoingView = previous
            previous.visible = true
            next.slideX = direction * distance
            next.slideZ = 1
            next.visible = true
            incomingSlide.target = next
            incomingSlide.from = direction * distance
            outgoingSlide.target = previous
            outgoingSlide.from = 0
            outgoingSlide.to = -direction * distance
            tabSlide.start()
        } else {
            if (previous && previous !== next)
                previous.visible = false
            next.visible = true
        }
        activeView.forceActiveFocus()
        if (!outgoingView)
            updateTabLifecycle()
        if (pendingCloseViews.length && !selectionGlide.running && !heldOpenSelection)
            Qt.callLater(root.processPendingClose)
    }

    function finishOpenSelection(view) {
        if (heldOpenSelection !== view)
            return
        heldOpenSelection = null
        hideHeldSelection = false
        if (Math.abs(selectionBar.startOffset) > 0.5 || Math.abs(selectionBar.endOffset) > 0.5)
            selectionGlide.start()
        else
            Qt.callLater(root.processPendingClose)
    }

    function finishTabOpening(view) {
        if (!view)
            return
        view.tabOpening = false
        finishOpenSelection(view)
        Qt.callLater(root.processPendingClose)
    }

    function createBrowserView(targetWindow) {
        // All transferable views use the primary window's long-lived creation context.
        if (primaryWindow) return primaryWindow.createBrowserView(root)
        const owner = targetWindow || root
        const frame = webFrameComponent.createObject(browserArea, {ownerWindow: owner})
        if (!frame)
            return null
        const view = webViewComponent.createObject(frame, {ownerWindow: owner}) as CefView
        if (!view) {
            frame.destroy()
            return null
        }
        view.frameContainer = frame
        frame.previewView = view
        frame.parent = owner.browserContent
        return view
    }

    function groupFor(view) {
        return view ? tabGroups.find(group => group.id === view.tabGroupId) || null : null
    }

    function tabGroupHeaderItem(id) {
        return groupHeaderRepeater.itemAt(tabGroups.findIndex(group => group.id === id))
    }

    function tabGroupHeaderWidth(index, order) {
        const tabs = order || views
        const group = groupFor(tabs[index])
        return group && (index === 0 || tabs[index - 1].tabGroupId !== group.id) ? groupHeaderWidth : 0
    }

    function tabSlotWidth(index, order) {
        const tabs = order || views
        return tabGroupHeaderWidth(index, tabs) + tabWidth * (tabs[index]?.groupExpansion ?? 1)
    }

    function tabStripPosition(index, order) {
        const tabs = order || views
        let position = 0
        for (let i = 0; i < Math.min(index, tabs.length); ++i) position += tabSlotWidth(i, tabs)
        return position
    }

    function tabStripTabPosition(index, order) {
        return tabStripPosition(index, order) + tabGroupHeaderWidth(index, order)
    }

    function tabDropTarget(position, pointer) {
        const point = pointer === undefined ? position : pointer
        tabDropGroupId = ""
        for (const group of tabGroups) {
            const first = views.findIndex(view => view.tabGroupId === group.id)
            const last = views.map(view => view.tabGroupId).lastIndexOf(group.id)
            if (first >= 0 && point >= tabStripPosition(first)
                    && point < tabStripTabPosition(last) + tabWidth * views[last].groupExpansion) {
                tabDropGroupId = group.id
                if (point < tabStripTabPosition(first)) return Math.min(views.length - 1, last + (draggedTabIndex > last ? 1 : 0))
                break
            }
        }
        let best = 0, distance = Infinity
        for (let i = 0; i < views.length; ++i) {
            if (views[i].groupExpansion < 0.001) continue
            const delta = Math.abs(tabStripTabPosition(i) - position)
            if (delta < distance) { best = i; distance = delta }
        }
        if (tabDropGroupId) {
            const first = views.findIndex(view => view.tabGroupId === tabDropGroupId)
            const last = views.map(view => view.tabGroupId).lastIndexOf(tabDropGroupId)
            return Math.max(first, Math.min(last, best))
        }
        const group = groupFor(views[best])
        if (group) {
            const first = views.findIndex(view => view.tabGroupId === group.id)
            const last = views.map(view => view.tabGroupId).lastIndexOf(group.id)
            return point < tabStripPosition(first)
                    ? Math.max(0, first - (draggedTabIndex < first ? 1 : 0))
                    : Math.min(views.length - 1, last + (draggedTabIndex > last ? 1 : 0))
        }
        return best
    }

    function requestTabGroup(view) {
        if (!view || !views.includes(view)) return
        groupRenameDialog.createView = view
        groupRenameDialog.createViews = tabsForAction(view)
        groupRenameDialog.groupId = ""
        groupRenameDialog.groupColor = Kirigami.Theme.highlightColor
        groupRenameDialog.groupIcon = "folder"
        groupNameEditor.text = qsTr("Tab Group %1").arg((primaryWindow || root).nextGroupNumber)
        groupRenameDialog.open()
        groupNameEditor.forceActiveFocus()
        groupNameEditor.selectAll()
    }

    function createTabGroup(view, name, color, icon = "folder") {
        if (!view || views.indexOf(view) < 0) return
        const owner = primaryWindow || root
        const number = owner.nextGroupNumber++
        const id = Date.now().toString(36) + "-" + number
        assignTabGroup(view, "")
        view.tabGroupId = id
        tabGroups = tabGroups.concat({id: id, title: name && name.trim() || qsTr("Tab Group %1").arg(number), color: color || Kirigami.Theme.highlightColor, icon: icon, collapsed: false})
        if (overviewVisible) updateTabGroup(id, {overviewCollapsed: false})
        return id
    }

    function restoreTabGroups(groups) {
        for (const group of groups) {
            const members = group.tabs.filter(index => Number.isInteger(index) && index >= 0 && index < views.length)
                                      .map(index => views[index]).filter(view => !view.tabGroupId)
            if (!members.length) continue
            const id = createTabGroup(members[0], group.title, group.color, group.icon || "folder")
            for (const view of members) view.tabGroupId = id
            updateTabGroup(id, {collapsed: !!group.collapsed, overviewCollapsed: !!group.overviewCollapsed}, true)
        }
    }

    function updateTabGroup(id, changes, immediate) {
        if (changes.overviewCollapsed === false) {
            for (const group of tabGroups) {
                const other = overviewGroupContainer(group.id)
                if (group.id !== id && !group.overviewCollapsed && !other?.collapsing)
                    updateTabGroup(group.id, {overviewCollapsed: true}, immediate)
            }
        }
        const container = overviewGroupContainer(id)
        if (!immediate && overviewVisible && !appSettings.reduceMotion && container
                && changes.overviewCollapsed !== undefined) {
            container.animateCollapsed(changes.overviewCollapsed)
            const remaining = Object.assign({}, changes)
            delete remaining.overviewCollapsed
            if (Object.keys(remaining).length) updateTabGroup(id, remaining, true)
            return
        }
        tabGroups = tabGroups.map(group => group.id === id ? Object.assign({}, group, changes) : group)
        if (overviewVisible && changes.overviewCollapsed !== undefined) syncOverviewFrames()
        if (changes.overviewCollapsed === false)
            for (const view of views.filter(view => view.tabGroupId === id && !view.overviewClosingCard))
                view.finishOverviewEntrance()
    }

    function assignTabGroup(view, id) {
        if (!view || views.indexOf(view) < 0 || view.tabGroupId === id) return
        const positions = captureTabStripPositions()
        const members = views.filter(item => item !== view && item.tabGroupId === (id || view.tabGroupId))
        const last = members.length ? members[members.length - 1] : null
        const from = views.indexOf(view)
        if (last) {
            const lastIndex = views.indexOf(last)
            const to = lastIndex > from ? lastIndex : lastIndex + 1
            reorderTab(from, to, positions, true)
        }
        view.tabGroupId = id
        if (id) updateTabGroup(id, {collapsed: false})
        tabGroups = tabGroups.filter(group => views.some(item => item.tabGroupId === group.id))
    }

    function ungroupTabs(id) {
        for (const view of views) if (view.tabGroupId === id) {
            if (!view.overviewClosingCard) view.finishOverviewEntrance()
            view.tabGroupId = ""
        }
        tabGroups = tabGroups.filter(group => group.id !== id)
    }

    function showGroupContextMenu(id, item, point) {
        groupContextMenu.groupId = id
        const position = item.mapToItem(root.contentItem, point.x, point.y)
        groupContextMenu.popup(root.contentItem, position.x, position.y)
    }

    function chooseTabGroupIcon(id) {
        groupIconPicker.groupId = id
        if (groupIconPicker.item) groupIconPicker.item.open()
        else groupIconPicker.active = true
    }

    function editTabGroup(id) {
        const group = tabGroups.find(group => group.id === id)
        if (!group) return
        groupRenameDialog.createView = null
        groupRenameDialog.groupId = id
        groupRenameDialog.groupColor = group.color
        groupRenameDialog.groupIcon = group.icon || "folder"
        groupNameEditor.text = group.title
        groupRenameDialog.open()
        groupNameEditor.forceActiveFocus()
        groupNameEditor.selectAll()
    }

    function closeTabGroup(id) {
        for (const view of views.slice().reverse())
            if (view.tabGroupId === id) closeTab(views.indexOf(view))
    }

    function loadRestoredTab(view) {
        const address = String(view.deferredRestoreUrl)
        if (!address) return
        view.lifecycleState = CefView.LifecycleState.Active
        view.url = address
        view.deferredRestoreUrl = ""
    }

    function openTab(address, request, background, sourceView, existingView, deferLoad) {
        const keepOverview = overviewVisible
        const sourceIndex = sourceView ? views.indexOf(sourceView) : -1
        const insertIndex = sourceIndex >= 0 ? sourceIndex + 1 : views.length
        if (keepOverview)
            overviewSearch.text = ""
        if (keepOverview && overviewClosing) {
            overviewFinishTimer.stop()
            overviewAnimation.stop()
            overviewClosing = false
            overviewProgress = 1
        }
        const view = existingView || createBrowserView()
        if (!view)
            return
        if (!existingView && sourceView && sourceView.tabGroupId)
            view.tabGroupId = sourceView.tabGroupId
        if (deferLoad) {
            view.deferredRestoreUrl = address
        }
        if (keepOverview && !appSettings.reduceMotion)
            view.overviewEntrance = 0
        view.tabOpening = !appSettings.reduceMotion
        views = views.slice(0, insertIndex).concat(view, views.slice(insertIndex))
        tabModel.insert(insertIndex, {tabView: view,
                                      title: Policy.pageLabel(address || newTabUrl, ""),
                                      filePage: Policy.isFileUrl(address || newTabUrl),
                                      newFilePage: Policy.isNewFileTabUrl(address || newTabUrl),
                                      loading: !deferLoad, progress: 0,
                                      animateOpen: !appSettings.reduceMotion})
        if (!background && !keepOverview)
            activateTab(insertIndex)
        if (keepOverview) {
            view.lifecycleState = CefView.LifecycleState.Active
            view.visible = attachOverviewFrame(view)
            Qt.callLater(root.syncOverviewFrames)
            if (!appSettings.reduceMotion)
                Qt.callLater(() => view.startOverviewEntrance())
        }
        if (request)
            view.acceptAsNewWindow(request)
        else if (!existingView && !deferLoad)
            view.url = address || newTabUrl
        syncTab(view)
        if (existingView) syncTabLoading(view)
        if (background || keepOverview)
            tabBar.currentIndex = activeIndex
        if (background || keepOverview)
            updateTabLifecycle()
    }

    function closeTab(index) {
        if (index < 0 || index >= views.length)
            return
        if (overviewVisible) {
            closeOverviewTab(index)
            return
        }
        const view = views[index]
        const closingSelected = view === activeView
        const tab = tabRepeater.itemAt(index)
        if (!tab) {
            if (pendingCloseViews.indexOf(view) >= 0)
                return
            if (view.tabOpening || (!appSettings.reduceMotion && closingSelected)) {
                pendingCloseViews = pendingCloseViews.concat(view)
                if (closingSelected) {
                    const nextIndex = nextAvailableTab(index)
                    if (nextIndex >= 0)
                        activateTab(nextIndex)
                    else
                        activateHome()
                }
                Qt.callLater(root.processPendingClose)
            } else
                finishClose(view)
            return
        }
        if (tab.closing || tab.closePending)
            return
        if (view.tabOpening || tab.openRise > 0 || animatingCloseGap || (!appSettings.reduceMotion
                && (closingSelected || pendingCloseViews.length))) {
            tab.closePending = true
            pendingCloseViews = pendingCloseViews.concat(view)
            if (closingSelected) {
                const nextIndex = nextAvailableTab(index)
                if (nextIndex >= 0)
                    activateTab(nextIndex)
                else
                    activateHome()
            }
            Qt.callLater(root.processPendingClose)
        } else {
            closingViews = closingViews.concat(view)
            tab.startClose()
        }
    }

    function closeTabByMiddleClick(view) {
        const index = views.indexOf(view)
        if (index < 0)
            return
        if (pendingCloseViews.indexOf(view) >= 0 || closingViews.indexOf(view) >= 0
                || readyCloseViews.indexOf(view) >= 0)
            return
        closeTab(index)
    }

    function closeOverviewTab(index) {
        const view = views[index]
        if (!view || view.overviewClosingCard)
            return
        if (overviewClosing) {
            overviewFinishTimer.stop()
            overviewAnimation.stop()
            overviewClosing = false
            overviewProgress = 1
        }
        pendingCloseViews = pendingCloseViews.filter(item => item !== view)
        closingViews = closingViews.filter(item => item !== view)
        readyCloseViews = readyCloseViews.filter(item => item !== view)
        if (heldOpenSelection === view) {
            heldOpenSelection = null
            hideHeldSelection = false
        }
        const card = overviewCardRepeater.itemAt(index + 1)?.card
        if (appSettings.reduceMotion || !card) {
            finishOverviewClose(view)
            return
        }
        const cardPosition = card.mapToItem(overviewFlickable.contentItem, 0, 0)
        view.overviewCloseX = cardPosition.x
        view.overviewCloseY = cardPosition.y + 50 * (1 - card.entrance)
        view.overviewCloseWidth = card.width
        view.overviewCloseHeight = card.height
        view.overviewClosingCard = true
        overviewClosingCardCount++
        if (activeView === view) {
            const nextIndex = nextAvailableTab(index)
            selectTabInStrip(nextIndex >= 0 ? views[nextIndex] : homeView, nextIndex)
        }
        if (overviewSelectedView === view)
            overviewSelectedView = activeView
        const tab = tabRepeater.itemAt(index)
        if (tab) {
            const position = tab.mapToItem(tabsViewport, 0, 0)
            if (position.x + tab.width > 0 && position.x < tabsViewport.width)
                tab.startClose()
        }
        view.startOverviewClose()
    }

    function finishOverviewClose(view) {
        const index = views.indexOf(view)
        if (index < 0)
            return
        const tab = tabRepeater.itemAt(index)
        if (overviewVisible && view.overviewClosingCard
                && (view.overviewEntrance > 0 || (tab?.closing && tab.closeDrop < tabStripHeight)))
            return
        view.stopOverviewClose()
        view.visible = false
        view.enabled = false
        view.lifecycleState = CefView.LifecycleState.Discarded
        detachOverviewFrame(view)
        const oldPositions = captureTabStripPositions()
        animatingCloseGap = !appSettings.reduceMotion
        views = views.filter((_, position) => position !== index)
        tabModel.remove(index)
        animateCloseGaps(oldPositions)
        if (view.overviewClosingCard) {
            view.overviewClosingCard = false
            overviewClosingCardCount--
        }
        Qt.callLater(root.syncOverviewFrames)
        if (activeView === view)
            activeView = views[Math.min(index, views.length - 1)] || homeView
        if (overviewSelectedView === view)
            overviewSelectedView = activeView
        tabBar.currentIndex = activeIndex
        retiredOverviewViews = retiredOverviewViews.concat(view)
        overviewDisposalTimer.restart()
        updateTabLifecycle()
    }

    function nextAvailableTab(index) {
        for (let next = index + 1; next < views.length; ++next)
            if (pendingCloseViews.indexOf(views[next]) < 0
                    && closingViews.indexOf(views[next]) < 0
                    && readyCloseViews.indexOf(views[next]) < 0
                    && !views[next].overviewClosingCard)
                return next
        for (let next = index - 1; next >= 0; --next)
            if (pendingCloseViews.indexOf(views[next]) < 0
                    && closingViews.indexOf(views[next]) < 0
                    && readyCloseViews.indexOf(views[next]) < 0
                    && !views[next].overviewClosingCard)
                return next
        return -1
    }

    function processPendingClose() {
        if (!pendingCloseViews.length || animatingCloseGap
                || selectionGlide.running || heldOpenSelection)
            return
        const activeIndex = views.indexOf(activeView)
        if (activeIndex >= 0 && pendingCloseViews.indexOf(activeView) >= 0) {
            const nextIndex = nextAvailableTab(activeIndex)
            if (nextIndex >= 0)
                activateTab(nextIndex)
            else
                activateHome()
            Qt.callLater(root.processPendingClose)
            return
        }
        const waiting = []
        const ready = []
        for (const view of pendingCloseViews) {
            const index = views.indexOf(view)
            if (index < 0)
                continue
            const tab = tabRepeater.itemAt(index)
            if (view.tabOpening || (tab && tab.openRise > 0))
                waiting.push(view)
            else
                ready.push({view: view, tab: tab})
        }
        pendingCloseViews = waiting
        closingViews = closingViews.concat(ready.filter(item => item.tab).map(item => item.view))
        for (const item of ready) {
            if (item.tab)
                item.tab.startClose()
            else
                finishClose(item.view)
        }
        if (!waiting.length && readyCloseViews.length)
            Qt.callLater(root.flushClosedTabs)
    }

    function finishClose(target) {
        if (target?.overviewClosingCard) {
            finishOverviewClose(target)
            return
        }
        if (views.indexOf(target) < 0 || readyCloseViews.indexOf(target) >= 0)
            return
        readyCloseViews = readyCloseViews.concat(target)
        Qt.callLater(root.flushClosedTabs)
    }

    function flushClosedTabs() {
        if (pendingCloseViews.length)
            return
        if (closingViews.some(view => views.indexOf(view) >= 0
                              && readyCloseViews.indexOf(view) < 0))
            return
        const targets = readyCloseViews.filter(view => views.indexOf(view) >= 0)
        readyCloseViews = []
        closingViews = closingViews.filter(view => targets.indexOf(view) < 0)
        if (!targets.length)
            return
        if (overviewVisible) {
            for (const view of targets.slice().sort((a, b) => views.indexOf(b) - views.indexOf(a))) {
                const index = views.indexOf(view)
                if (index >= 0)
                    closeOverviewTab(index)
            }
            Qt.callLater(root.processPendingClose)
            return
        }
        if (targets.indexOf(activeView) >= 0 || targets.indexOf(outgoingView) >= 0)
            resetSlide()
        const oldPositions = captureTabStripPositions()
        const previousIndex = activeIndex
        animatingCloseGap = !appSettings.reduceMotion
        for (let index = views.length - 1; index >= 0; --index) {
            if (targets.indexOf(views[index]) < 0)
                continue
            const view = views.splice(index, 1)[0]
            if (view === activeView)
                activeView = null
            tabModel.remove(index)
            view.visible = false
            view.frameContainer.destroy()
        }
        views = views.slice()
        animateCloseGaps(oldPositions)
        if (views.length === 0) {
            activeView = null
            activateHome(false)
        } else if (activeView) {
            tabBar.currentIndex = activeIndex
            updateTabLifecycle()
        } else {
            activateTab(Math.min(Math.max(previousIndex, 0), views.length - 1), false)
        }
        Qt.callLater(root.processPendingClose)
    }

    function animateCloseGaps(oldPositions) {
        if (!animatingCloseGap)
            return
        closeGapTimer.restart()
        for (let next = 0; next < tabModel.count; ++next) {
            const tab = tabRepeater.itemAt(next)
            const before = oldPositions.find(item => item.view === views[next])
            const distance = before ? before.x - tabStripTabPosition(next) : 0
            if (tab && distance > 0)
                tab.startCloseFill(distance)
        }
    }

    function tabPreviewOffset(index) {
        if (draggedGroupId && !overviewDraggedGroupId && views[index]?.tabGroupId === draggedGroupId)
            return groupDragOffset
        const order = previewTabOrder()
        return tabStripTabPosition(order.indexOf(views[index]), order) - tabStripTabPosition(index)
    }

    function previewTabOrder() {
        const order = views.slice()
        if (draggedGroupId) {
            const members = order.filter(view => view.tabGroupId === draggedGroupId)
            const remaining = order.filter(view => view.tabGroupId !== draggedGroupId)
            remaining.splice(Math.max(0, groupDropIndex), 0, ...members)
            return remaining
        }
        const from = overviewDraggedView && overviewDraggedView !== homeView
                       ? views.indexOf(overviewDraggedView) : draggedTabIndex
        const to = overviewDraggedView && overviewDraggedView !== homeView
                     ? overviewDropIndex : tabDropIndex
        if (from < 0 || to < 0)
            return order
        return tabMoveOrder(from, to, dragViews.length ? dragViews : [views[from]],
                            overviewDraggedView ? overviewDropGroupId : tabDropGroupId)
    }

    function groupHeaderPosition(id) {
        const first = views.findIndex(view => view.tabGroupId === id)
        if (first < 0) return 0
        if (id === draggedGroupId && !overviewDraggedGroupId) return tabStripPosition(first) + groupDragOffset
        // Individual member dragging never moves its group's label.
        if (!draggedGroupId) return tabStripPosition(first)
        const order = previewTabOrder()
        return tabStripPosition(order.findIndex(view => view.tabGroupId === id), order)
    }

    function groupDropTarget(position) {
        let destination = 0
        for (let first = 0; first < views.length;) {
            const id = views[first].tabGroupId
            let end = first + 1
            if (id) while (end < views.length && views[end].tabGroupId === id) ++end
            if (id !== draggedGroupId) {
                const middle = (tabStripPosition(first) + tabStripPosition(end)) / 2
                if (position < middle) return destination
                destination += end - first
            }
            first = end
        }
        return destination
    }

    function groupHeaderVisualPosition(id) {
        const header = tabGroupHeaderItem(id)
        return header ? header.x + header.releaseOffset : groupHeaderPosition(id)
    }

    function moveTabGroup(id, destination, positions) {
        const members = views.filter(view => view.tabGroupId === id)
        if (!members.length) return
        const order = views.filter(view => view.tabGroupId !== id)
        order.splice(Math.max(0, Math.min(destination, order.length)), 0, ...members)
        applyTabOrder(order, positions)
    }

    function applyTabOrder(order, positions) {
        selectionGlide.stop()
        selectionBar.startOffset = 0
        selectionBar.endOffset = 0
        homeSelectionGlide = false
        // Move the existing delegates, preserving the webviews and selection identity.
        const current = views.slice()
        for (let index = 0; index < order.length; ++index) {
            const from = current.indexOf(order[index])
            if (from !== index) {
                current.splice(index, 0, current.splice(from, 1)[0])
                tabModel.move(from, index, 1)
            }
        }
        views = order
        tabBar.contentItem.forceLayout()
        animateTabReorder(positions)
        tabBar.currentIndex = activeIndex
        if (overviewVisible) Qt.callLater(root.syncOverviewFrames)
        Qt.callLater(root.processPendingClose)
    }

    function animateTabReorder(positions) {
        if (!positions || appSettings.reduceMotion) return
        for (let index = 0; index < views.length; ++index) {
            const before = positions.find(item => item.view === views[index])
            const offset = before ? before.x - tabStripTabPosition(index) : 0
            if (Math.abs(offset) > 0.5)
                tabRepeater.itemAt(index)?.startReorderFill(offset)
        }
    }

    function captureTabStripPositions() {
        return views.map((view, index) => ({view: view, x: tabStripTabPosition(index)
                                            + (tabRepeater.itemAt(index)?.visualOffset || 0)}))
    }

    function tabMoveOrder(from, to, members, groupId) {
        if (from === to && (groupId === undefined || members.every(view => view.tabGroupId === groupId)))
            return views.slice()
        const moving = views.filter(view => members.includes(view))
        const remaining = views.filter(view => !moving.includes(view))
        const edge = to + (to > from ? 1 : 0)
        const destination = views.slice(0, edge).filter(view => !moving.includes(view)).length
        remaining.splice(destination, 0, ...moving)
        return remaining
    }

    function reorderTab(from, to, stripPositions, preserveGroup, groupId, members) {
        if (from < 0 || to < 0 || from >= views.length || to >= views.length
                || from === to && !stripPositions && groupId === undefined)
            return
        const moving = (members || [views[from]]).filter(view => tabsForAction(view).includes(view))
        const destinationGroup = groupId === undefined ? views[to].tabGroupId : groupId
        const order = tabMoveOrder(from, to, moving, preserveGroup ? undefined : destinationGroup)
        if (!preserveGroup) for (const view of moving) view.tabGroupId = destinationGroup
        applyTabOrder(order, stripPositions)
    }

    Controls.Menu {
        id: groupContextMenu
        objectName: "tabGroupContextMenu"
        property string groupId: ""
        readonly property var group: root.tabGroups.find(group => group.id === groupId)
        enabled: !!group
        Controls.MenuItem {
            objectName: "renameTabGroup"
            text: qsTr("Rename group…")
            icon.name: "edit-rename"
            onTriggered: root.editTabGroup(groupContextMenu.groupId)
        }
        Controls.MenuItem {
            objectName: "changeTabGroupColor"
            text: qsTr("Change color…")
            icon.name: "color-management"
            onTriggered: {
                const group = groupContextMenu.group
                if (group) root.updateTabGroup(group.id, {color: appSettings.chooseGroupColor(group.color, root)})
            }
        }
        Controls.MenuItem {
            objectName: "changeTabGroupIcon"
            text: qsTr("Change icon…")
            icon.name: "preferences-desktop-icons"
            onTriggered: root.chooseTabGroupIcon(groupContextMenu.groupId)
        }
        Controls.MenuSeparator {}
        Controls.MenuItem {
            objectName: "deleteTabGroup"
            text: qsTr("Delete group")
            icon.name: "edit-delete"
            onTriggered: root.ungroupTabs(groupContextMenu.groupId)
        }
        Controls.MenuItem {
            objectName: "closeTabGroup"
            text: qsTr("Close all tabs")
            icon.name: "window-close"
            onTriggered: root.closeTabGroup(groupContextMenu.groupId)
        }
    }

    Controls.Dialog {
        id: groupRenameDialog
        objectName: "tabGroupNameDialog"
        property string groupId: ""
        property var createView: null
        property var createViews: []
        property color groupColor: Kirigami.Theme.highlightColor
        property string groupIcon: "folder"
        title: createView ? qsTr("New tab group") : qsTr("Edit tab group")
        width: Math.min(380, root.width - Kirigami.Units.largeSpacing * 2)
        padding: Kirigami.Units.largeSpacing
        modal: true
        anchors.centerIn: parent
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: {
            if (groupNameEditor.text.trim()) {
                if (createView) {
                    const id = createTabGroup(createView, groupNameEditor.text.trim(), groupColor, groupIcon)
                    if (id) for (const view of createViews) assignTabGroup(view, id)
                }
                else updateTabGroup(groupId, {title: groupNameEditor.text.trim(), color: groupColor, icon: groupIcon})
            }
        }
        onClosed: {
            createView = null
            createViews = []
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Controls.Label { text: qsTr("Name"); font.bold: true }
            Controls.TextField {
                id: groupNameEditor
                objectName: "tabGroupNameEditor"
                Layout.fillWidth: true
                placeholderText: qsTr("Group name")
                Accessible.name: qsTr("Group name")
                onAccepted: if (text.trim()) groupRenameDialog.accept()
            }
            Controls.Button {
                objectName: "tabGroupIconPicker"
                Layout.fillWidth: true
                text: qsTr("Choose icon…")
                icon.name: groupRenameDialog.groupIcon
                onClicked: root.chooseTabGroupIcon("")
            }
            Controls.Label {
                text: qsTr("Color")
                font.bold: true
                Layout.topMargin: Kirigami.Units.mediumSpacing
            }
            Controls.Button {
                objectName: "tabGroupColorPicker"
                Layout.fillWidth: true
                text: qsTr("Choose color…")
                leftPadding: Kirigami.Units.largeSpacing + groupColorSwatch.width + Kirigami.Units.smallSpacing
                onClicked: groupRenameDialog.groupColor = appSettings.chooseGroupColor(groupRenameDialog.groupColor, root)
                Rectangle {
                    id: groupColorSwatch
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.tabIconSize
                    height: width
                    radius: 3
                    color: groupRenameDialog.groupColor
                    border.width: 1
                    border.color: Kirigami.Theme.textColor
                }
            }
        }
    }

    Loader {
        id: groupIconPicker
        property string groupId: ""
        active: false
        onLoaded: item.open()
        sourceComponent: IconThemes.IconDialog {
            title: qsTr("Tab group icon")
            modality: Qt.WindowModal
            onAccepted: {
                if (!iconName) return
                if (groupIconPicker.groupId) root.updateTabGroup(groupIconPicker.groupId, {icon: iconName})
                else groupRenameDialog.groupIcon = iconName
            }
        }
    }

    MouseArea {
        parent: root.contentItem
        anchors.fill: parent
        z: 900
        enabled: root.selectedTabViews.length > 0
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => {
            if (!root.selectionSurfaceAt(Qt.point(mouse.x, mouse.y))
                    && !(root.overviewVisible && (mouse.modifiers & Qt.ShiftModifier)))
                root.selectedTabViews = []
            // Observe click-away without consuming presses intended for Chromium or controls.
            mouse.accepted = false
        }
    }

    Instantiator {
        model: Shortcuts.items.filter(item => item.category === "Overview").map(item => item.id)
        delegate: Shortcut {
            required property string modelData
            readonly property var definition: Shortcuts.items.find(item => item.id === modelData)
            objectName: "overviewKey" + modelData
            sequence: Shortcuts.sequence(appSettings, modelData)
            context: Qt.WindowShortcut
            enabled: root.active && sequence !== "" && root.overviewVisible && !root.keyboardPopupActive
            onActivated: {
                const keys = {Left: Qt.Key_Left, Right: Qt.Key_Right, Up: Qt.Key_Up,
                              Down: Qt.Key_Down, Return: Qt.Key_Return, Enter: Qt.Key_Enter}
                root.handleOverviewKey({key: keys[definition.key],
                    modifiers: definition.range ? Qt.ShiftModifier : Qt.NoModifier, accepted: false})
            }
        }
    }
    Instantiator {
        model: Shortcuts.items.filter(item => item.category === "Selection").map(item => item.id)
        delegate: Shortcut {
            required property string modelData
            readonly property var definition: Shortcuts.items.find(item => item.id === modelData)
            objectName: "selectionKey" + modelData
            sequence: Shortcuts.sequence(appSettings, modelData)
            context: Qt.WindowShortcut
            enabled: root.active && sequence !== "" && root.selectionShortcutAvailable
            onActivated: root.actOnSelectedItems(modelData)
        }
    }

    Shortcut { sequence: Shortcuts.sequence(appSettings, "new-tab"); onActivated: root.openTab(root.newTabUrl) }
    Shortcut { sequence: Shortcuts.sequence(appSettings, "close-tab"); onActivated: root.closeTab(root.activeIndex) }
    Shortcut { sequence: Shortcuts.sequence(appSettings, "fullscreen"); onActivated: root.toggleWebFullscreen() }
    Shortcut { sequence: Shortcuts.sequence(appSettings, "autohide-toolbar"); onActivated: root.toggleToolbarAutoHide() }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "cancel-selection")
        enabled: root.selectedTabViews.length > 0 || (root.overviewVisible && !root.overviewClosing)
        onActivated: {
            if (root.selectedTabViews.length) root.selectedTabViews = []
            else root.toggleOverview()
        }
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "previous-tab")
        context: Qt.ApplicationShortcut
        enabled: root.active && sequence !== ""
        onActivated: root.cycleTab(-1)
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "next-tab")
        context: Qt.ApplicationShortcut
        enabled: root.active && sequence !== ""
        onActivated: root.cycleTab(1)
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "cycle-tabs")
        onActivated: {
            if (root.views.length)
                root.activateTab((root.activeIndex + 1) % root.views.length)
        }
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "toggle-overview")
        onActivated: root.toggleOverview()
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "detach-tab")
        enabled: root.activeIndex >= 0 && root.views.length > 1
        onActivated: root.moveTabToNewWindow(root.activeIndex)
    }
    Shortcut {
        sequence: Shortcuts.sequence(appSettings, "freeze-tabs")
        context: Qt.ApplicationShortcut
        enabled: root.active && sequence !== ""
        onActivated: root.allFrozen ? root.wakeCurrentTab() : root.freezeAllTabs()
    }

    Component.onCompleted: {
        appSettings.registerMainWindow(root)
        homeView = createBrowserView()
        if (homeView) {
            homeView.dedicatedHome = true
            homeView.url = homeUrl
            activateHome()
        }
        if (String(startupUrl))
            openTab(startupUrl)
        if (!primaryWindow && appSettings.rememberOpenedTabs) {
            for (const address of appSettings.rememberedFileTabs)
                openTab(address, null, true, null, null, appSettings.deferRestoredTabs)
            restoreTabGroups(appSettings.rememberedTabGroups)
        }
        show()
    }
}
