// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtWebEngine
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: tools
    required property string mode
    property var inspectedView: null
    property var ownerWindow: null
    property var tasks: []
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    objectName: mode === "tasks" ? "chromiumTaskManagerWindow" : "developerToolsWindow"
    transientParent: null
    modality: Qt.NonModal
    title: mode === "tasks" ? qsTr("Chromium Task Manager") : qsTr("Developer Tools")
    width: 900; height: 640
    minimumWidth: 580; minimumHeight: 360
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    onVisibleChanged: if (!visible) inspectedView = null

    function refreshTasks() {
        if (mode !== "tasks" || !visible) return
        const selectedView = tasks[tabList.currentIndex]?.view
        const resources = appSettings.chromiumTabResources()
        tasks = (ownerWindow?.chromiumPages || []).map(page => {
            const resource = resources.find(task => task.pid === page.pid)
            const view = page.view
            const unloaded = !!String(view.deferredRestoreUrl) || view.lifecycleState === WebEngineView.LifecycleState.Discarded
            const sleeping = view.lifecycleState === WebEngineView.LifecycleState.Frozen
            return {view: view, home: page.home, title: page.title, pid: resource ? page.pid : 0,
                    cpu: resource?.cpu, memory: resource?.memory,
                    state: unloaded ? qsTr("Unloaded") : sleeping ? qsTr("Sleeping") : view.loading ? qsTr("Loading") : qsTr("Running")}
        })
        tabList.currentIndex = tasks.findIndex(task => task.view === selectedView)
    }
    Timer { interval: 2000; running: tools.visible && tools.mode === "tasks"; repeat: true; onTriggered: tools.refreshTasks() }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        header: ExternalWindowHeader {
            targetWindow: tools
            iconName: tools.mode === "tasks" ? "view-process-all" : "tools-report-bug"
            showMinimizeMaximize: true
        }

        Loader {
            anchors.fill: parent
            active: tools.mode === "devtools"
            sourceComponent: WebEngineView {
                objectName: "chromiumDeveloperTools"
                inspectedView: tools.inspectedView
                backgroundColor: Kirigami.Theme.backgroundColor
                onNavigationRequested: request => {
                    if (/^https?:/.test(String(request.url))) {
                        request.reject()
                        Qt.openUrlExternally(request.url)
                    }
                }
                onNewWindowRequested: request => {
                    if (/^https?:/.test(String(request.requestedUrl))) Qt.openUrlExternally(request.requestedUrl)
                }
            }
        }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            visible: tools.mode === "tasks"
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                Controls.Label { Layout.fillWidth: true; text: qsTr("Tab"); font.bold: true }
                Controls.Label { Layout.preferredWidth: 85; text: qsTr("CPU"); font.bold: true }
                Controls.Label { Layout.preferredWidth: 100; text: qsTr("Memory"); font.bold: true }
                Controls.Label { Layout.preferredWidth: 90; text: qsTr("Status"); font.bold: true }
            }
            Kirigami.Separator { Layout.fillWidth: true }
            ListView {
                id: tabList
                objectName: "chromiumTabList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: tools.tasks
                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                delegate: Controls.ItemDelegate {
                    required property var modelData
                    required property int index
                    width: tabList.width
                    highlighted: tabList.currentIndex === index
                    onClicked: tabList.currentIndex = index
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            source: modelData.home ? "go-home" : "text-x-generic"
                        }
                        Controls.Label { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.title }
                        Controls.Label { Layout.preferredWidth: 85; text: modelData.pid ? Number(modelData.cpu).toFixed(1) + "%" : "—" }
                        Controls.Label { Layout.preferredWidth: 100; text: modelData.pid ? Number(modelData.memory).toFixed(1) + " MiB" : "—" }
                        Controls.Label { Layout.preferredWidth: 90; text: modelData.state }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    Layout.fillWidth: true
                    text: qsTr("CPU and memory describe the tab’s renderer. Tabs sharing a renderer show the same usage.")
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
                Controls.Button {
                    objectName: "showTaskManagerTabButton"
                    text: qsTr("Show tab")
                    icon.name: "view-visible"
                    readonly property var selectedTask: tools.tasks[tabList.currentIndex]
                    enabled: !!selectedTask?.view && !!tools.ownerWindow
                             && (selectedTask.view === tools.ownerWindow.homeView || tools.ownerWindow.views.includes(selectedTask.view))
                    onClicked: {
                        tools.ownerWindow.dismissOverview()
                        tools.ownerWindow.activateView(selectedTask.view, tools.ownerWindow.views.indexOf(selectedTask.view))
                        tools.ownerWindow.show()
                        tools.ownerWindow.raise()
                        tools.ownerWindow.requestActivate()
                        tools.refreshTasks()
                    }
                }
                Controls.Button {
                    objectName: "closeTaskManagerTabButton"
                    text: qsTr("Close tab")
                    icon.name: "process-stop"
                    readonly property var selectedTask: tools.tasks[tabList.currentIndex]
                    enabled: !!selectedTask && !selectedTask.home && !!tools.ownerWindow && tools.ownerWindow.views.includes(selectedTask.view)
                    onClicked: {
                        tools.ownerWindow.closeTab(tools.ownerWindow.views.indexOf(selectedTask.view))
                        tools.refreshTasks()
                    }
                }
            }
        }
    }
    WindowResizeHandles { parent: tools.contentItem; anchors.fill: parent; active: tools.framelessControls; targetWindow: tools }
}
