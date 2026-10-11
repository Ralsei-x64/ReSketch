pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects
import Qt.labs.platform as Platform
import QtWebEngine
import org.kde.kirigami as Kirigami
import "Policy.js" as Policy
import "FigmaMenu.js" as FigmaMenu
import "FigmaTheme.js" as FigmaTheme

Kirigami.ApplicationWindow {
    id: root

    readonly property url homeUrl: "https://www.figma.com/files/recent"
    readonly property url loginUrl: "https://www.figma.com/login"
    readonly property url newTabUrl: "https://www.figma.com/desktop_new_tab"
    readonly property int tabStripHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property int tabWidth: 220
    readonly property real tabAreaWidth: Math.max(0, width - homeButton.width
                                               - addTabButton.width - overviewButton.width
                                               - refreshButton.width - menuButton.width
                                               - windowControlGroup.width)
    readonly property bool tabStripOverflow: tabModel.count * tabWidth > tabAreaWidth + 1
    readonly property int tabIconSize: Kirigami.Units.iconSizes.small
    readonly property int tabContentLeftMargin: Kirigami.Units.smallSpacing + 5
    readonly property real toolbarAlpha: appSettings.toolbarOpacity / 100
    readonly property bool desktopSidebars: appSettings.translucentSidebars
                                            && appSettings.sidebarBackdrop === "desktop"
                                            && appSettings.toolbarOpacity < 100
    readonly property int overviewColumns: Math.min(width < 1360 ? 3 : 4, tabModel.count + 1)
    readonly property int overviewRows: Math.ceil((overviewFilteredCount() + overviewClosingCardCount)
                                                  / overviewColumns)
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
    readonly property bool chromiumFrameLoaded: !!activeView && activeView.hasLoadedFrame
                                               && !overviewVisible
    readonly property string figmaAppearanceScript: FigmaTheme.script({
        dark: appSettings.darkTheme,
        systemColors: appSettings.figmaSystemColors,
        palette: appSettings.figmaPalette,
        customCssEnabled: appSettings.figmaCustomCssEnabled,
        customCss: appSettings.figmaCustomCss,
        translucentSidebars: appSettings.translucentSidebars,
        sidebarBackdrop: appSettings.sidebarBackdrop,
        opacity: appSettings.toolbarOpacity
    }, FigmaMenu.storeSource)
    property var views: []
    property var homeView: null
    property var activeView: null
    property var outgoingView: null
    readonly property int activeIndex: activeView && activeView !== homeView
                                       ? views.indexOf(activeView) : -1
    property bool allFrozen: false
    property string externalUrl: ""
    property double appMemoryBytes: 0
    property bool memoryPressure: false
    property var sharedProfile: null
    property var primaryWindow: null
    property var detachedWindows: []
    property url startupUrl: ""
    property int draggedTabIndex: -1
    property int tabDropIndex: -1
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
        enabled: !appSettings.reduceMotion
        NumberAnimation { duration: 150 }
    }
    property bool overviewClosing: false
    property real overviewProgress: 0
    readonly property bool overviewAnimationRunning: overviewAnimation.running
    property var overviewSelectedView: null
    property bool skipNextWebSlide: false

    width: 1280
    height: 800
    minimumWidth: 640
    minimumHeight: 400
    flags: framelessTabBar ? Qt.Window | Qt.FramelessWindowHint : Qt.Window
    color: "transparent"
    background: Item { }
    title: Policy.windowTitle(activeView ? activeView.url : "", activeView ? activeView.title : "")
    onChromiumFrameLoadedChanged: appSettings.refreshWindowBlur(root)
    onClosing: {
        settingsWindow.close()
        aboutWindow.close()
        exportHistoryWindow.close()
        if (primaryWindow) {
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
            Platform.MenuItem { text: qsTr("Reload page"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.triggerPageAction(WebEngineView.Reload) }
            Platform.MenuItem { text: qsTr("About ReSketch…"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.openAbout() }
        }
        Platform.Menu {
            id: nativePreferencesMenu
            title: qsTr("&Preferences")
            Platform.MenuSeparator { visible: figmaMenus.preferencesActionCount > 0 }
            Platform.MenuItem { text: qsTr("Settings…"); onTriggered: root.openSettings() }
        }
    }

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.initialPage: Kirigami.Page {
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        background: Item { }

        header: Rectangle {
            width: root.width
            height: root.tabStripHeight
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                           Kirigami.Theme.backgroundColor.g,
                           Kirigami.Theme.backgroundColor.b, root.toolbarAlpha)

            Row {
                anchors.fill: parent
                spacing: 0

            Controls.ToolButton {
                id: homeButton
                width: 49
                height: root.tabStripHeight
                text: ""
                Accessible.name: "Home"
                Controls.ToolTip.text: qsTr("Home")
                Controls.ToolTip.visible: hovered
                readonly property bool selected: root.activeView === root.homeView
                background: Rectangle {
                    color: homeButton.selected ? Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                          Kirigami.Theme.backgroundColor.g,
                                                          Kirigami.Theme.backgroundColor.b,
                                                          root.toolbarAlpha)
                                               : homeButton.hovered ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                              Kirigami.Theme.highlightColor.g,
                                                                              Kirigami.Theme.highlightColor.b, 0.12)
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

                WheelHandler {
                    enabled: tabsViewport.contentWidth > tabsViewport.width
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const pixel = event.pixelDelta.y
                        const angle = event.angleDelta.y
                        const stepped = Math.abs(angle) >= 60
                        const precise = !stepped && pixel !== 0 && Math.abs(pixel) <= 24
                        const distance = stepped ? angle * root.tabWidth / 120
                                                 : pixel || angle * root.tabWidth / 120
                        tabsViewport.scrollBy(distance, precise)
                        event.accepted = true
                    }
                }

                WheelHandler {
                    enabled: tabsViewport.contentWidth > tabsViewport.width
                    target: null
                    orientation: Qt.Horizontal
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const pixel = event.pixelDelta.x
                        const angle = event.angleDelta.x
                        const stepped = Math.abs(angle) >= 60
                        const precise = !stepped && pixel !== 0 && Math.abs(pixel) <= 24
                        const distance = stepped ? angle * root.tabWidth / 120
                                                 : pixel || angle * root.tabWidth / 120
                        tabsViewport.scrollBy(distance, precise)
                        event.accepted = true
                    }
                }

                Controls.TabBar {
                    id: tabBar
                    width: tabModel.count * root.tabWidth
                    height: root.tabStripHeight
                    background: Item { }

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
                            readonly property bool selected: root.activeView === tabView
                            property bool settling: false
                            property real dropOffset: 0
                            property bool closing: false
                            property bool closePending: false
                            property var closingView: null
                            property real closeDrop: 0
                            property real openRise: 0
                            property bool fillingClose: false
                            property real fillOffset: 0
                            readonly property real visualOffset: tabTranslate.x
                            width: root.tabWidth
                            height: root.tabStripHeight
                            z: closing ? 20 : tabDrag.active || settling ? 10 : 0
                            transform: Translate {
                                id: tabTranslate
                                x: tabDrag.active ? tabDrag.activeTranslation.x
                                                  : tabButton.fillingClose ? tabButton.fillOffset
                                                  : tabButton.settling ? tabButton.dropOffset
                                                  : root.tabPreviewOffset(tabButton.index, tabButton.width)
                                y: -tabButton.y + tabButton.closeDrop + tabButton.openRise

                                Behavior on x {
                                    enabled: root.draggedTabIndex >= 0 && root.tabDropIndex >= 0
                                             && !tabDrag.active && !tabButton.settling
                                             && !appSettings.reduceMotion
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                    }
                                }
                            }
                            NumberAnimation {
                                id: tabSettle
                                target: tabButton
                                property: "dropOffset"
                                to: 0
                                duration: 220
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0, 0.76, 0, 1, 1, 1]
                                onFinished: tabButton.settling = false
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
                                if (animateOpen) {
                                    tabModel.setProperty(index, "animateOpen", false)
                                    if (!appSettings.reduceMotion) {
                                        openRise = root.tabStripHeight
                                        openToast.start()
                                    } else
                                        root.finishTabOpening(tabView)
                                }
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
                                fillOffset = distance
                                fillingClose = true
                                closeFill.start()
                            }
                            function startClose() {
                                if (closing)
                                    return
                                closingView = tabView
                                closing = true
                                tabSettle.stop()
                                if (appSettings.reduceMotion)
                                    root.finishClose(closingView)
                                else
                                    closeToast.start()
                            }
                            text: ""
                            Accessible.name: title
                            checkable: false
                            checked: selected
                            opacity: selected ? 1 : 0.7
                            background: Rectangle {
                                color: tabButton.selected ? Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                                                    Kirigami.Theme.backgroundColor.g,
                                                                    Kirigami.Theme.backgroundColor.b,
                                                                    root.toolbarAlpha)
                                                          : tabButton.hovered ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                                         Kirigami.Theme.highlightColor.g,
                                                                                         Kirigami.Theme.highlightColor.b, 0.12)
                                                                              : "transparent"

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
                                if (!closing && !closePending && root.activeView !== tabView)
                                    root.activateTab(root.views.indexOf(tabView))
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                onTapped: (point) => {
                                    if (!tabButton.closing && !tabButton.closePending
                                            && point.position.x < closeTabButton.mapToItem(tabButton, 0, 0).x
                                            && root.activeView !== tabButton.tabView)
                                        root.activateTab(root.views.indexOf(tabButton.tabView))
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
                                Controls.MenuItem {
                                    text: qsTr("Move to new window")
                                    enabled: !!tabButton.tabView
                                             && Policy.isFigmaUrl(tabButton.tabView.url)
                                    onTriggered: {
                                        const target = tabButton.tabView
                                        Qt.callLater(() => root.moveTabToNewWindow(root.views.indexOf(target)))
                                    }
                                }
                                Controls.MenuItem {
                                    text: qsTr("Close")
                                    onTriggered: {
                                        const target = tabButton.tabView
                                        Qt.callLater(() => root.closeTab(root.views.indexOf(target)))
                                    }
                                }
                                Controls.MenuItem {
                                    text: qsTr("Refresh")
                                    enabled: !root.allFrozen
                                    onTriggered: root.refreshTab(root.views.indexOf(tabButton.tabView))
                                }
                                Controls.MenuItem {
                                    text: qsTr("Copy URL")
                                    enabled: !!tabButton.tabView
                                             && Policy.isFigmaUrl(tabButton.tabView.url)
                                    onTriggered: appSettings.copyToClipboard(String(tabButton.tabView.url))
                                }
                            }

                            contentItem: Item {
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
                                        property real lastDragX: 0
                                        enabled: !tabButton.closing
                                        target: null
                                        acceptedButtons: Qt.LeftButton
                                        yAxis.enabled: false
                                        onActiveChanged: {
                                            if (active) {
                                                if (tabButton.selected) {
                                                    selectionGlide.stop()
                                                    root.homeSelectionGlide = false
                                                    selectionBar.startOffset = 0
                                                    selectionBar.endOffset = 0
                                                }
                                                lastDragX = activeTranslation.x
                                                tabSettle.stop()
                                                tabButton.settling = false
                                                tabButton.dropOffset = 0
                                                root.draggedTabIndex = tabButton.index
                                                root.tabDropIndex = tabButton.index
                                            } else if (root.draggedTabIndex >= 0) {
                                                const source = root.draggedTabIndex
                                                const destination = root.tabDropIndex
                                                const dropOffset = tabButton.x + lastDragX
                                                                   - destination * tabButton.width
                                                tabButton.dropOffset = dropOffset
                                                tabButton.settling = !appSettings.reduceMotion
                                                                     && Math.abs(dropOffset) > 0.5
                                                root.draggedTabIndex = -1
                                                root.tabDropIndex = -1
                                                root.reorderTab(source, destination)
                                                if (tabButton.settling)
                                                    tabSettle.start()
                                                else
                                                    tabButton.dropOffset = 0
                                            }
                                        }
                                        onActiveTranslationChanged: {
                                            if (active) {
                                                lastDragX = activeTranslation.x
                                                root.tabDropIndex = Math.max(0, Math.min(tabModel.count - 1,
                                                    Math.round(root.draggedTabIndex + activeTranslation.x / tabButton.width)))
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    }
                }

                Rectangle {
                    x: (root.tabDropIndex + (root.tabDropIndex > root.draggedTabIndex ? 1 : 0)) * root.tabWidth - width / 2
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

            TabBarButton {
                id: addTabButton
                dragWindow: root
                width: 40
                height: root.tabStripHeight
                icon.name: "tab-new"
                icon.width: root.tabIconSize
                icon.height: root.tabIconSize
                Accessible.name: "New tab"
                Controls.ToolTip.text: qsTr("New file tab")
                Controls.ToolTip.visible: hovered
                onClicked: root.openTab(root.newTabUrl)
            }

            TabBarButton {
                id: overviewButton
                dragWindow: root
                width: 40
                height: root.tabStripHeight
                dimmed: !root.homeView && !root.overviewVisible
                icon.name: "view-grid"
                icon.width: root.tabIconSize
                icon.height: root.tabIconSize
                Accessible.name: "Tab overview"
                Controls.ToolTip.text: qsTr("Tab overview")
                Controls.ToolTip.visible: hovered
                onClicked: {
                    if (!dimmed)
                        root.toggleOverview()
                }
            }

            TabBarButton {
                id: refreshButton
                dragWindow: root
                width: 40
                height: root.tabStripHeight
                icon.name: "view-refresh"
                icon.width: root.tabIconSize
                icon.height: root.tabIconSize
                dimmed: !root.activeView || root.allFrozen
                Accessible.name: "Refresh page"
                Controls.ToolTip.text: qsTr("Refresh page")
                Controls.ToolTip.visible: hovered
                onClicked: {
                    if (!dimmed)
                        root.triggerPageAction(WebEngineView.Reload)
                }
            }

            TabBarButton {
                id: menuButton
                dragWindow: root
                width: 40
                height: root.tabStripHeight
                icon.name: "application-menu"
                icon.width: root.tabIconSize
                icon.height: root.tabIconSize
                Accessible.name: "Application menu"
                Controls.ToolTip.text: qsTr("Application menu")
                Controls.ToolTip.visible: hovered
                onClicked: appMenu.open()

                Controls.Menu {
                    id: appMenu
                    x: menuButton.width - width
                    y: menuButton.height
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
                        Controls.MenuItem { text: qsTr("Reload page"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.triggerPageAction(WebEngineView.Reload) }
                        Controls.MenuItem { text: qsTr("About ReSketch…"); visible: !figmaMenus.usingHomeMenu; onTriggered: root.openAbout() }
                    }
                    Controls.Menu {
                        id: preferencesPopupMenu
                        title: qsTr("Preferences")
                        Controls.MenuSeparator { visible: figmaMenus.preferencesActionCount > 0 }
                        Controls.MenuItem { text: qsTr("Settings…"); onTriggered: root.openSettings() }
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
                x: tabsViewport.x + Math.min(tabsViewport.width,
                                             Math.max(0, tabsViewport.contentWidth
                                                            - tabsViewport.contentX))
                y: 0
                z: 8
                width: Math.max(0, tabsViewport.x + tabsViewport.width - x)
                height: root.tabStripHeight - 1
                acceptedButtons: Qt.LeftButton
                onPressed: root.startSystemMove()
                onDoubleClicked: root.toggleMaximize()
            }

            Item {
                width: homeButton.width + leftTabOverflow.width + tabsViewport.width
                       + rightTabOverflow.width
                height: 3
                z: 15
                clip: true

                Item {
                    id: selectionBar
                    property real startOffset: 0
                    property real endOffset: 0
                    readonly property var currentTab: root.activeIndex >= 0 ? tabBar.currentItem : null
                    readonly property real targetX: root.activeIndex < 0 ? 0
                                                    : tabsViewport.x - tabsViewport.contentX
                                                      + (currentTab && currentTab.tabView === root.activeView
                                                         ? currentTab.x + currentTab.visualOffset
                                                         : root.activeIndex * root.tabWidth)
                    readonly property real targetWidth: root.activeIndex < 0
                                                        ? homeButton.width - 1 : root.tabWidth
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

        Item {
            id: browserArea
            anchors.fill: parent
            clip: true

            Rectangle {
                anchors.fill: parent
                opacity: root.desktopSidebars && root.activeView && root.activeView.hasLoadedFrame
                         ? root.overviewSidebarBackdrop : 1
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b, root.toolbarAlpha)
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
                        text: "All tabs are frozen"
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
                anchors.fill: parent
                z: 40
                visible: root.overviewVisible

                Flickable {
                    id: overviewFlickable
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
                    function resetScroll() {
                        overviewWheelScroll.stop()
                        smoothWheel = false
                        wheelTargetY = 0
                        contentY = 0
                    }
                    anchors.fill: parent
                    z: root.overviewSelectedView
                       && (root.overviewClosing || root.overviewProgress < 0.999) ? 10 : 0
                    contentWidth: width
                    contentHeight: root.overviewMargin * 2
                                   + root.overviewSearchHeight
                                   + root.overviewRows * root.overviewCardHeight
                                   + Math.max(0, root.overviewRows - 1) * root.overviewGap
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

                    WheelHandler {
                        enabled: overviewFlickable.contentHeight > overviewFlickable.height
                        target: null
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            const pixel = event.pixelDelta.y
                            const angle = event.angleDelta.y
                            const stepped = Math.abs(angle) >= 60
                            const precise = !stepped && pixel !== 0 && Math.abs(pixel) <= 24
                            const step = Math.max(220, Math.min(320, root.overviewCardHeight
                                                               + root.overviewGap))
                            overviewFlickable.scrollBy(stepped ? angle * step / 120
                                                               : pixel || angle * step / 120,
                                                       precise)
                            event.accepted = true
                        }
                    }

                    Repeater {
                        id: overviewCardRepeater
                        model: tabModel.count + 1
                        delegate: Item {
                            id: overviewCard
                            clip: true
                            layer.enabled: root.overviewVisible
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: overviewCardMask
                            }
                            Rectangle {
                                id: overviewCardMask
                                parent: browserArea
                                width: overviewCard.width
                                height: overviewCard.height
                                radius: Kirigami.Units.smallSpacing + 3
                                color: "white"
                                visible: false
                                layer.enabled: true
                            }
                            required property int index
                            readonly property int tabIndex: index - 1
                            readonly property var previewView: tabIndex < 0 ? root.homeView
                                                                            : root.views[tabIndex]
                            readonly property bool closing: !!previewView && previewView.overviewClosingCard
                            readonly property bool zooming: previewView === root.overviewSelectedView
                            readonly property int gridSlot: root.overviewFilteredSlot(tabIndex)
                            readonly property real entrance: zooming ? 1
                                                               : previewView ? previewView.overviewEntrance : 1
                            readonly property real headerHeight: root.overviewTitleHeight
                                                                 * (zooming ? root.overviewProgress : 1)
                            visible: closing || root.overviewMatches(tabIndex)
                                     || (zooming && root.overviewProgress < 1)
                            enabled: !closing
                            z: zooming ? 10 : closing ? 9 : 0
                            opacity: entrance
                            x: closing ? previewView.overviewCloseX
                               : zooming ? root.overviewCardX(gridSlot) * root.overviewProgress
                                       : root.overviewCardX(gridSlot)
                            y: closing ? previewView.overviewCloseY - 50 * (1 - entrance)
                               : zooming ? root.overviewCardY(gridSlot) * root.overviewProgress
                                         + overviewFlickable.contentY * (1 - root.overviewProgress)
                                       : root.overviewCardY(gridSlot) - 50 * (1 - entrance)
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
                                         && entrance >= 0.999 && !root.overviewAnimationRunning
                                         && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                enabled: root.overviewVisible && root.overviewProgress >= 0.999
                                         && entrance >= 0.999 && !root.overviewAnimationRunning
                                         && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            Behavior on width {
                                enabled: !closing && root.overviewVisible
                                         && root.overviewProgress >= 0.999 && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            Behavior on height {
                                enabled: !closing && root.overviewVisible
                                         && root.overviewProgress >= 0.999 && !appSettings.reduceMotion
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Kirigami.Theme.backgroundColor
                                opacity: root.desktopSidebars && overviewCard.previewView
                                         && overviewCard.previewView.hasLoadedFrame
                                         ? root.overviewSidebarBackdrop : 1
                            }

                            Rectangle {
                                anchors.fill: parent
                                z: 3
                                radius: Kirigami.Units.smallSpacing + 3
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                      Kirigami.Theme.textColor.g,
                                                      Kirigami.Theme.textColor.b, 0.3)
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
                                              && Policy.isFileUrl(overviewCard.previewView.url)
                                              ? "text-x-generic" : "go-home"
                                }
                                Controls.Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                                        + root.tabIconSize + Kirigami.Units.smallSpacing
                                    anchors.right: parent.right
                                    anchors.rightMargin: overviewActions.width + Kirigami.Units.smallSpacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: overviewCard.tabIndex < 0 ? qsTr("Home")
                                          : overviewCard.previewView
                                            ? Policy.pageLabel(overviewCard.previewView.url,
                                                               overviewCard.previewView.title) : ""
                                    elide: Text.ElideRight
                                }
                                Row {
                                    id: overviewActions
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    z: 3

                                    Controls.ToolButton {
                                        visible: overviewCard.tabIndex >= 0
                                        width: 30
                                        height: 30
                                        icon.name: "overflow-menu"
                                        icon.width: root.tabIconSize
                                        icon.height: root.tabIconSize
                                        Accessible.name: qsTr("Tab options")
                                        onClicked: overviewMenu.popup()

                                        Controls.Menu {
                                            id: overviewMenu
                                            Controls.MenuItem {
                                                text: qsTr("Move to new window")
                                                enabled: !!overviewCard.previewView
                                                         && Policy.isFigmaUrl(overviewCard.previewView.url)
                                                onTriggered: {
                                                    const view = overviewCard.previewView
                                                    Qt.callLater(() => root.moveTabToNewWindow(root.views.indexOf(view)))
                                                }
                                            }
                                            Controls.MenuItem {
                                                text: qsTr("Close")
                                                onTriggered: {
                                                    const view = overviewCard.previewView
                                                    Qt.callLater(() => root.closeTab(root.views.indexOf(view)))
                                                }
                                            }
                                            Controls.MenuItem {
                                                text: qsTr("Refresh")
                                                enabled: !root.allFrozen
                                                onTriggered: {
                                                    root.refreshTab(root.views.indexOf(overviewCard.previewView))
                                                }
                                            }
                                            Controls.MenuItem {
                                                text: qsTr("Copy URL")
                                                enabled: !!overviewCard.previewView
                                                         && Policy.isFigmaUrl(overviewCard.previewView.url)
                                                onTriggered: appSettings.copyToClipboard(String(overviewCard.previewView.url))
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
                                         || !overviewCard.previewView.hasLoadedFrame

                                Controls.BusyIndicator {
                                    anchors.centerIn: parent
                                    width: 32
                                    height: 32
                                    running: parent.visible
                                }
                            }

                            MouseArea {
                                id: overviewCardMouse
                                anchors.fill: parent
                                z: 1
                                hoverEnabled: true
                                enabled: root.overviewProgress > 0.95
                                onClicked: root.selectOverviewView(overviewCard.previewView)
                            }
                            TapHandler {
                                acceptedButtons: Qt.MiddleButton
                                enabled: root.overviewProgress > 0.95
                                onTapped: root.closeTab(root.views.indexOf(overviewCard.previewView))
                            }
                            Rectangle {
                                anchors.fill: parent
                                z: 0
                                radius: Kirigami.Units.smallSpacing + 3
                                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                               Kirigami.Theme.highlightColor.g,
                                               Kirigami.Theme.highlightColor.b, 0.1)
                                visible: overviewCardMouse.containsMouse
                                border.width: 1
                                border.color: Kirigami.Theme.highlightColor
                            }
                            Rectangle {
                                anchors.fill: parent
                                z: 4
                                radius: Kirigami.Units.smallSpacing + 3
                                color: "transparent"
                                border.width: 2
                                border.color: Kirigami.Theme.highlightColor
                                visible: overviewCard.zooming
                                opacity: root.overviewProgress
                            }
                        }
                    }
                }

                Controls.TextField {
                    id: overviewSearch
                    x: (parent.width - width) / 2
                    y: root.overviewMargin
                    width: Math.min(320, parent.width - root.overviewMargin * 2)
                    height: 38
                    z: 5
                    placeholderText: qsTr("Search tabs")
                    leftPadding: 12 + root.tabIconSize + Kirigami.Units.smallSpacing
                    rightPadding: 12
                    Accessible.name: qsTr("Search tabs")
                    onTextChanged: overviewFlickable.resetScroll()

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
        active: root.framelessTabBar
        targetWindow: root
    }

    ListModel { id: tabModel }

    SettingsWindow { id: settingsWindow; visible: false }
    AboutWindow { id: aboutWindow; visible: false }
    ExportHistoryWindow { id: exportHistoryWindow; visible: false }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.updateTabLifecycle()
    }

    Timer {
        id: signInRefreshTimer
        interval: 1000
        onTriggered: {
            if (root.homeView)
                root.homeView.reload()
            for (const view of root.views)
                if (view !== root.homeView && view === root.activeView)
                    view.reload()
        }
    }

    onAppMemoryBytesChanged: refreshMemoryPressure()

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
            root.refreshMemoryPressure()
        }
        function onEffectiveThemeChanged() {
            for (const view of [root.homeView].concat(root.views))
                root.syncFigmaTheme(view)
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

    WebEngineProfile {
        id: figmaProfile
        storageName: root.sharedProfile ? "" : "resketch"
        persistentStoragePath: root.sharedProfile ? "" : appSettings.profileStoragePath
        offTheRecord: !!root.sharedProfile
        onDownloadRequested: function(download) { root.handleDownload(download) }
        onDownloadFinished: function(download) { root.completeDownload(download) }
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
            else if (root.overviewVisible)
                overviewSearch.forceActiveFocus()
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
            property var previewView: null
            property var previewCard: null
            visible: !root.overviewVisible || (!!previewCard && parent === previewCard)
            clip: true
            x: 0
            y: previewCard ? previewCard.headerHeight : 0
            width: previewCard ? previewCard.width : browserArea.width
            height: previewCard ? Math.max(0, previewCard.height - previewCard.headerHeight)
                                : browserArea.height
            z: previewCard ? 0 : previewView ? previewView.slideZ : 0
            transform: Translate { x: frame.previewView ? frame.previewView.slideX : 0 }

            Item {
                anchors.fill: parent
                visible: !root.overviewVisible && !!frame.previewView
                         && (frame.previewView === root.activeView
                             || frame.previewView === root.outgoingView)
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

        WebEngineView {
            id: webView
            property real slideX: 0
            property int slideZ: 0
            property double lastUsedAt: Date.now()
            property bool reloadAfterFreeze: false
            property bool tabOpening: false
            property bool dedicatedHome: false
            property bool googleSignIn: false
            property bool hasLoadedFrame: false
            property real overviewEntrance: 1
            property bool overviewClosingCard: false
            property real overviewCloseX: 0
            property real overviewCloseY: 0
            property real overviewCloseWidth: 0
            property real overviewCloseHeight: 0
            property var frameContainer: null
            property var authWindow: null
            readonly property var ownerWindow: root
            property url lastHomeUrl: root.homeUrl
            function startOverviewEntrance() {
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
                onFinished: root.finishOverviewClose(webView)
            }
            width: googleSignIn ? parent.width : browserArea.width
            height: googleSignIn ? parent.height : browserArea.height
            x: 0
            y: 0
            transformOrigin: Item.TopLeft
            scale: frameContainer ? frameContainer.width / Math.max(1, width) : 1
            visible: false
            enabled: !root.overviewVisible
            opacity: !hasLoadedFrame ? 0
                     : !root.overviewVisible ? 1
                     : overviewClosingCard ? 1
                     : root.overviewMatches(root.overviewSlot(webView))
                       ? webView === root.overviewSelectedView ? 1
                         : overviewEntrance
                       : 0
            profile: root.sharedProfile || figmaProfile
            settings.scrollAnimatorEnabled: !appSettings.reduceMotion
            backgroundColor: root.desktopSidebars && !googleSignIn ? "transparent" : "white"
            userScripts.collection: [{
                name: "resketch-appearance",
                sourceCode: root.figmaAppearanceScript,
                injectionPoint: WebEngineScript.DocumentReady,
                worldId: WebEngineScript.MainWorld,
                runsOnSubFrames: false
            }]
            transform: Translate { x: webView.frameContainer ? 0 : webView.slideX }

            onLoadingChanged: {
                if (!loading) {
                    if (lifecycleState !== WebEngineView.LifecycleState.Discarded
                            && String(url) && String(url) !== "about:blank")
                        hasLoadedFrame = true
                    root.syncFigmaTheme(webView)
                }
                const index = root.views.indexOf(webView)
                if (index >= 0) {
                    tabModel.setProperty(index, "loading", loading)
                    tabModel.setProperty(index, "progress", loading ? loadProgress : 100)
                }
                if (root.allFrozen && !loading)
                    lifecycleState = WebEngineView.LifecycleState.Frozen
                Qt.callLater(root.updateTabLifecycle)
            }

            onLoadProgressChanged: {
                const index = root.views.indexOf(webView)
                if (index >= 0)
                    tabModel.setProperty(index, "progress", loadProgress)
            }

            onTitleChanged: root.syncTab(webView)
            onLifecycleStateChanged: {
                if (lifecycleState === WebEngineView.LifecycleState.Active)
                    root.syncFigmaTheme(webView)
                else if (lifecycleState === WebEngineView.LifecycleState.Discarded)
                    hasLoadedFrame = false
            }
            onWindowCloseRequested: {
                if (authWindow)
                    Qt.callLater(() => authWindow.close())
            }
            onUrlChanged: {
                const address = String(url)
                if (dedicatedHome && Policy.isFileUrl(address)) {
                    url = lastHomeUrl
                    root.openTab(address, null, false, webView)
                    return
                }
                if (dedicatedHome && Policy.isFileBrowserUrl(address)) {
                    lastHomeUrl = url
                }
                root.syncTab(webView)
            }

            onNewWindowRequested: function(request) {
                const address = String(request.requestedUrl)
                if (Policy.isAuthGrantUrl(address))
                    root.openWebSignIn(webView)
                else if (!webView.googleSignIn && Policy.isFigmaUrl(address)
                         && address.includes("start_google_sso")
                         && !String(webView.url).startsWith(String(root.loginUrl)))
                    root.openWebSignIn(webView)
                else if (Policy.isGoogleSignInUrl(address) || address === "about:blank"
                         || address.includes("start_google_sso"))
                    root.openGoogleSignInWindow(request, "")
                else if (!webView.dedicatedHome
                         && (Policy.isFileBrowserUrl(webView.url)
                             || Policy.isNewFileTabUrl(webView.url))
                         && Policy.isFileUrl(address))
                    webView.url = address
                else if (Policy.isFigmaUrl(address) || address === "about:blank")
                    root.openTab("", request,
                                 request.destination === WebEngineNewWindowRequest.InNewBackgroundTab,
                                 webView)
            }

            onNavigationRequested: function(request) {
                if (!request.isMainFrame)
                    return
                const address = String(request.url)
                if (Policy.isAuthGrantUrl(address)) {
                    request.reject()
                    root.openWebSignIn(webView)
                } else if (!webView.googleSignIn && Policy.isFigmaUrl(address)
                           && address.includes("start_google_sso")
                           && !String(webView.url).startsWith(String(root.loginUrl))) {
                    request.reject()
                    root.openWebSignIn(webView)
                } else if (Policy.isGoogleSignInUrl(address) && !webView.googleSignIn) {
                    request.reject()
                    root.openGoogleSignInWindow(null, address)
                } else if (Policy.isGoogleSignInUrl(address)) {
                    return
                } else if (!Policy.isFigmaUrl(address) && address !== "about:blank") {
                    request.reject()
                } else if (webView.dedicatedHome && Policy.isFileUrl(address)) {
                    request.reject()
                    root.openTab(address, null, false, webView)
                }
            }

            onPermissionRequested: function(permission) {
                if (Policy.isFigmaUrl(permission.origin)
                        && (permission.permissionType === WebEnginePermission.ClipboardReadWrite // qmllint disable missing-property
                            || permission.permissionType === WebEnginePermission.LocalFontsAccess)) // qmllint disable missing-property
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
            transientParent: root
            property var authView: null

            Item {
                id: googleContent
                anchors.fill: parent
                anchors.topMargin: googleHeader.height
                clip: true
            }

            Rectangle {
                id: googleHeader
                width: parent.width
                height: appSettings.windowControlsInTabBar ? root.tabStripHeight : 0
                visible: height > 0
                color: Kirigami.Theme.backgroundColor

                Row {
                    anchors.fill: parent

                    Item {
                        width: parent.width - googleControls.width
                        height: parent.height

                        Controls.Label {
                            anchors.left: parent.left
                            anchors.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Google sign in")
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.25
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: googleWindow.startSystemMove()
                        }
                    }

                    WindowControls {
                        id: googleControls
                        targetWindow: googleWindow
                        buttonSize: root.tabStripHeight
                        showMinimizeMaximize: false
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
            }

            WindowResizeHandles {
                anchors.fill: parent
                active: googleWindow.framelessControls
                targetWindow: googleWindow
            }

            onClosing: {
                signInRefreshTimer.restart()
                Qt.callLater(() => googleWindow.destroy())
            }
        }
    }

    function openGoogleSignInWindow(request, address) {
        const window = googleWindowComponent.createObject(root)
        if (!window)
            return
        const view = webViewComponent.createObject(window.webContent,
                                                   {googleSignIn: true, authWindow: window, visible: true})
        if (!view) {
            window.destroy()
            return
        }
        window.authView = view
        if (request)
            view.acceptAsNewWindow(request)
        else
            view.url = address
        window.show()
        window.raise()
        window.requestActivate()
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
        tabModel.setProperty(index, "filePage", Policy.isFileUrl(view.url))
        tabModel.setProperty(index, "newFilePage", Policy.isNewFileTabUrl(view.url))
        tabModel.setProperty(index, "title", Policy.pageLabel(view.url, view.title))
    }

    function syncFigmaTheme(view) {
        if (!view || view.loading || view.lifecycleState !== WebEngineView.LifecycleState.Active
                || !Policy.isFigmaUrl(view.url))
            return
        view.runJavaScript(root.figmaAppearanceScript)
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
        if (download.state === WebEngineDownloadRequest.DownloadCompleted)
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
                           && (overviewVisible ? !!view.frameContainer
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
        const card = index >= 0 ? overviewCardRepeater.itemAt(index) : null
        if (!card)
            return false
        if (view.frameContainer.previewCard === card && view.frameContainer.parent === card)
            return true
        detachFrameForCard(card)
        view.visible = false
        view.frameContainer.previewCard = card
        view.frameContainer.parent = card
        view.visible = true
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

    function overviewMatches(slot) {
        const query = overviewSearch.text.trim().toLocaleLowerCase()
        if (slot === -1)
            return !!homeView
        if (slot < 0)
            return false
        const view = views[slot]
        if (!view || view.overviewClosingCard)
            return false
        if (!query)
            return true
        const title = Policy.pageLabel(view.url, view.title)
        return title.toLocaleLowerCase().includes(query)
               || String(view.url).toLocaleLowerCase().includes(query)
    }

    function overviewFilteredCount() {
        let count = homeView ? 1 : 0
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
        if (tabModel.count === 0)
            return (browserArea.width - overviewCardWidth) / 2
        return overviewMargin + (slot % overviewColumns) * (overviewCardWidth + overviewGap)
    }

    function overviewCardY(slot) {
        return overviewMargin + overviewSearchHeight + Math.floor(slot / overviewColumns)
                                * (overviewCardHeight + overviewGap)
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
        overviewSelectedView = activeView
        overviewClosing = false
        overviewProgress = 0
        overviewSearch.text = ""
        overviewFlickable.resetScroll()
        overviewVisible = true
        for (const view of [homeView].concat(views)) {
            if (!view)
                continue
            view.lifecycleState = WebEngineView.LifecycleState.Active
            view.visible = attachOverviewFrame(view)
        }
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
        if (!overviewVisible) {
            activateView(target, target === homeView ? -1 : views.indexOf(target))
            return
        }
        for (const view of [homeView].concat(views))
            view.finishOverviewEntrance()
        overviewFinishTimer.stop()
        overviewAnimation.stop()
        overviewWheelScroll.stop()
        overviewFlickable.wheelTargetY = overviewFlickable.contentY
        overviewSelectedView = target
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

    function refreshMemoryPressure() {
        const limit = appSettings.maxMemoryGb * 1000000000
        if (appMemoryBytes >= limit)
            memoryPressure = true
        else if (appMemoryBytes < limit * 0.9)
            memoryPressure = false
        updateTabLifecycle()
    }

    function updateTabLifecycle() {
        if (allFrozen)
            return
        const background = views.filter(view => view !== activeView && view !== outgoingView
                                                 && !view.visible)
        background.sort((a, b) => {
            if (a.loading !== b.loading)
                return a.loading ? -1 : 1
            const aDiscarded = a.lifecycleState === WebEngineView.LifecycleState.Discarded
            const bDiscarded = b.lifecycleState === WebEngineView.LifecycleState.Discarded
            if (aDiscarded !== bDiscarded)
                return aDiscarded ? 1 : -1
            return b.lastUsedAt - a.lastUsedAt || views.indexOf(b) - views.indexOf(a)
        })
        const now = Date.now()
        const maxBackground = memoryPressure ? 2 : views.length > 5 ? 4 : background.length
        const minimumBackground = Math.max(0, appSettings.minimumLoadedTabs - 1)
        let awake = 0
        for (const view of background) {
            const recent = now - view.lastUsedAt < appSettings.sleepMinutes * 60 * 1000
            const keepLoading = view.loading
            const discarded = view.lifecycleState === WebEngineView.LifecycleState.Discarded
            const fillMinimum = !memoryPressure && awake < minimumBackground
            const keepAwake = keepLoading || (awake < maxBackground
                              && (fillMinimum || (!discarded && recent)))
            if (keepAwake) {
                ++awake
                if (view.lifecycleState !== WebEngineView.LifecycleState.Active)
                    view.lifecycleState = WebEngineView.LifecycleState.Active
            } else if (memoryPressure) {
                if (view.lifecycleState !== WebEngineView.LifecycleState.Discarded)
                    view.lifecycleState = WebEngineView.LifecycleState.Discarded
            } else if (view.lifecycleState === WebEngineView.LifecycleState.Active) {
                view.lifecycleState = WebEngineView.LifecycleState.Frozen
            }
        }
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
            if (view.loading) {
                view.reloadAfterFreeze = true
                view.stop()
            }
            if (!view.loading)
                view.lifecycleState = WebEngineView.LifecycleState.Frozen
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
        settingsWindow.show()
        settingsWindow.raise()
        settingsWindow.requestActivate()
    }

    function openExportHistory() {
        exportHistoryWindow.show()
        exportHistoryWindow.raise()
        exportHistoryWindow.requestActivate()
    }

    function triggerHomeMenuAction(command) {
        if (command === "reload") {
            if (!allFrozen) triggerPageAction(WebEngineView.Reload)
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
        aboutWindow.show()
        aboutWindow.raise()
        aboutWindow.requestActivate()
    }

    function refreshTab(index) {
        if (index < 0 || index >= views.length || allFrozen)
            return
        const view = views[index]
        const discarded = view.lifecycleState === WebEngineView.LifecycleState.Discarded
        view.lifecycleState = WebEngineView.LifecycleState.Active
        if (!discarded)
            view.reload()
    }

    function createDetachedWindow(address, profile) {
        const component = Qt.createComponent(Qt.resolvedUrl("Main.qml"))
        if (component.status !== Component.Ready) {
            console.warn(component.errorString())
            return false
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
            return false
        }
        detachedWindows.push(window)
        window.raise()
        window.requestActivate()
        return true
    }

    function moveTabToNewWindow(index) {
        if (index < 0 || index >= views.length)
            return
        const view = views[index]
        const address = String(view.url)
        if (!Policy.isFigmaUrl(address))
            return
        const owner = primaryWindow || root
        if (owner.createDetachedWindow(address, view.profile))
            closeTab(index)
    }

    function toggleMaximize() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
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

    function activateView(next, index, animateWebSlide) {
        if (overviewVisible) {
            selectOverviewView(next)
            return
        }
        const allowWebSlide = !skipNextWebSlide && animateWebSlide !== false
        skipNextWebSlide = false
        const previous = activeView
        const previousIndex = activeIndex
        const waitForOpening = !appSettings.reduceMotion && !!next.tabOpening
        const animateSelection = previous && previous !== next && selectionBar.visible
                                 && !appSettings.reduceMotion
        const oldLeft = animateSelection ? selectionBar.x : 0
        const oldRight = animateSelection ? selectionBar.x + selectionBar.width : 0
        selectionGlide.stop()
        homeSelectionGlide = animateSelection && (previous === homeView || next === homeView)
        if (allFrozen) {
            homeSelectionGlide = false
            selectionBar.startOffset = 0
            selectionBar.endOffset = 0
            heldOpenSelection = null
            hideHeldSelection = false
            allFrozen = false
            activeView = next
            tabBar.currentIndex = index
            next.lastUsedAt = Date.now()
            next.lifecycleState = WebEngineView.LifecycleState.Active
            next.visible = true
            if (next.reloadAfterFreeze) {
                next.reloadAfterFreeze = false
                next.reload()
            }
            next.forceActiveFocus()
            updateTabLifecycle()
            return
        }
        resetSlide()
        activeView = next
        wheelScroll.stop()
        if (index >= 0) {
            const left = index * tabWidth
            const right = left + tabWidth
            if (left < tabsViewport.contentX)
                tabsViewport.contentX = left
            else if (right > tabsViewport.contentX + tabsViewport.width)
                tabsViewport.contentX = Math.max(0, right - tabsViewport.width)
        }
        tabsViewport.wheelTargetX = tabsViewport.contentX
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
        next.lastUsedAt = Date.now()
        next.lifecycleState = WebEngineView.LifecycleState.Active
        if (next.reloadAfterFreeze) {
            next.reloadAfterFreeze = false
            next.reload()
        }
        tabBar.currentIndex = index
        if (previous && previous !== next && browserArea.width > 0
                && !appSettings.reduceMotion && allowWebSlide) {
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

    function createBrowserView() {
        const frame = webFrameComponent.createObject(browserArea)
        if (!frame)
            return null
        const view = webViewComponent.createObject(frame) as WebEngineView
        if (!view) {
            frame.destroy()
            return null
        }
        view.frameContainer = frame
        frame.previewView = view
        return view
    }

    function openTab(address, request, background, sourceView) {
        const keepOverview = overviewVisible
        const insertIndex = !keepOverview
                            && (sourceView ? sourceView === homeView : activeView === homeView)
                            ? 0 : views.length
        if (keepOverview)
            overviewSearch.text = ""
        if (keepOverview && overviewClosing) {
            overviewFinishTimer.stop()
            overviewAnimation.stop()
            overviewClosing = false
            overviewProgress = 1
        }
        const view = createBrowserView()
        if (!view)
            return
        if (keepOverview && !appSettings.reduceMotion)
            view.overviewEntrance = 0
        view.tabOpening = !appSettings.reduceMotion
        views = views.slice(0, insertIndex).concat(view, views.slice(insertIndex))
        tabModel.insert(insertIndex, {tabView: view,
                                      title: Policy.pageLabel(address || newTabUrl, ""),
                                      filePage: Policy.isFileUrl(address || newTabUrl),
                                      newFilePage: Policy.isNewFileTabUrl(address || newTabUrl),
                                      loading: true, progress: 0,
                                      animateOpen: !appSettings.reduceMotion})
        if (!background && !keepOverview)
            activateTab(insertIndex)
        if (keepOverview) {
            view.lifecycleState = WebEngineView.LifecycleState.Active
            view.visible = attachOverviewFrame(view)
            Qt.callLater(root.syncOverviewFrames)
            if (!appSettings.reduceMotion)
                Qt.callLater(() => view.startOverviewEntrance())
        }
        if (request)
            view.acceptAsNewWindow(request)
        else
            view.url = address || newTabUrl
        syncTab(view)
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
        const card = overviewCardRepeater.itemAt(index + 1)
        if (appSettings.reduceMotion || !card) {
            finishOverviewClose(view)
            return
        }
        view.overviewCloseX = card.x
        view.overviewCloseY = card.y + 50 * (1 - card.entrance)
        view.overviewCloseWidth = card.width
        view.overviewCloseHeight = card.height
        view.overviewClosingCard = true
        overviewClosingCardCount++
        if (activeView === view) {
            const nextIndex = nextAvailableTab(index)
            activeView = nextIndex >= 0 ? views[nextIndex] : homeView
            tabBar.currentIndex = activeIndex
        }
        if (overviewSelectedView === view)
            overviewSelectedView = activeView
        view.startOverviewClose()
    }

    function finishOverviewClose(view) {
        const index = views.indexOf(view)
        if (index < 0)
            return
        view.stopOverviewClose()
        view.visible = false
        view.enabled = false
        view.lifecycleState = WebEngineView.LifecycleState.Discarded
        detachOverviewFrame(view)
        views = views.filter((_, position) => position !== index)
        tabModel.remove(index)
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
        const oldViews = views.slice()
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
        if (animatingCloseGap)
            closeGapTimer.restart()
        if (!appSettings.reduceMotion) {
            for (let next = 0; next < tabModel.count; ++next) {
                const tab = tabRepeater.itemAt(next)
                const distance = (oldViews.indexOf(views[next]) - next) * tabWidth
                if (tab && distance > 0)
                    tab.startCloseFill(distance)
            }
        }
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

    function tabPreviewOffset(index, width) {
        if (draggedTabIndex < 0 || tabDropIndex < 0)
            return 0
        if (index > draggedTabIndex && index <= tabDropIndex)
            return -width
        if (index < draggedTabIndex && index >= tabDropIndex)
            return width
        return 0
    }

    function reorderTab(from, to) {
        if (from < 0 || to < 0 || from >= views.length || to >= views.length || from === to)
            return
        selectionGlide.stop()
        homeSelectionGlide = false
        selectionBar.startOffset = 0
        selectionBar.endOffset = 0
        views.splice(to, 0, views.splice(from, 1)[0])
        views = views.slice()
        tabModel.move(from, to, 1)
        if (overviewVisible)
            Qt.callLater(root.syncOverviewFrames)
        tabBar.currentIndex = activeIndex
        Qt.callLater(root.processPendingClose)
    }

    Shortcut { sequence: "Ctrl+T"; onActivated: root.openTab(root.newTabUrl) }
    Shortcut { sequence: "Ctrl+W"; onActivated: root.closeTab(root.activeIndex) }
    Shortcut {
        sequence: "Ctrl+Shift+Alt+Left"
        context: Qt.ApplicationShortcut
        onActivated: root.cycleTab(-1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Alt+Right"
        context: Qt.ApplicationShortcut
        onActivated: root.cycleTab(1)
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: {
            if (root.views.length)
                root.activateTab((root.activeIndex + 1) % root.views.length)
        }
    }
    Shortcut {
        sequence: "Ctrl+Alt+Shift+Up"
        onActivated: root.toggleOverview()
    }
    Shortcut {
        sequence: "Ctrl+Alt+Shift+Down"
        enabled: root.activeIndex >= 0
        onActivated: root.moveTabToNewWindow(root.activeIndex)
    }
    Shortcut {
        sequence: "Ctrl+Alt+Shift+F"
        context: Qt.ApplicationShortcut
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
        show()
    }
}
