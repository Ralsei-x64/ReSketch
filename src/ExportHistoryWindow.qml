// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: historyWindow
    transientParent: null
    objectName: "exportHistoryWindow"
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    property int activeRemovals: 0
    readonly property int removalDuration: 350
    width: 740
    height: 560
    minimumWidth: 500
    minimumHeight: 320
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: qsTr("ReSketch — Export History")
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    ListModel { id: historyModel }

    // Keep delegates stable when the persisted QVariantList changes.
    function syncHistory(animateRemovals) {
        const query = exportSearch.text.trim().toLowerCase()
        const items = appSettings.exportHistory.filter(item => !query ||
            [item.name, item.fileType, item.originName, item.path].join(" ").toLowerCase().includes(query))
        const paths = new Set(items.map(item => item.path))
        for (let i = historyModel.count - 1; i >= 0; --i) {
            if (paths.has(historyModel.get(i).modelData.path)) continue
            const entry = exportsList.itemAtIndex(i)
            if (entry)
                entry.animateRemoval = animateRemovals && historyWindow.visible &&
                    entry.y + entry.height > exportsList.contentY && entry.y < exportsList.contentY + exportsList.height
            if (items.length) historyModel.remove(i)
        }
        if (!items.length) historyModel.clear()
        for (let i = 0; i < items.length; ++i) {
            let existing = i
            while (existing < historyModel.count && historyModel.get(existing).modelData.path !== items[i].path) ++existing
            if (existing === historyModel.count) historyModel.insert(i, {modelData: items[i]})
            else {
                if (existing !== i) historyModel.move(existing, i, 1)
                historyModel.set(i, {modelData: items[i]})
            }
        }
    }

    function clearHistory() {
        const visibleEntries = exportsList.contentItem.children.filter(entry =>
            entry.objectName === "exportHistoryEntry" && !entry.ListView.delayRemove &&
            entry.y + entry.height > exportsList.contentY && entry.y < exportsList.contentY + exportsList.height)
        visibleEntries.sort((a, b) => a.y - b.y)
        visibleEntries.forEach((entry, index) => entry.removalDelay = index * 50)
        appSettings.clearExports()
    }

    Component.onCompleted: syncHistory(false)
    Connections {
        target: appSettings
        function onExportHistoryChanged() { historyWindow.syncHistory(true) }
    }

    pageStack.initialPage: Kirigami.Page {
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        padding: 0
        header: ExternalWindowHeader {
            id: historyHeader
            targetWindow: historyWindow
            title: qsTr("Export History")
            iconName: "document-export"
            actions: [TabBarButton {
                objectName: "clearExportsButton"
                dragWindow: historyWindow
                width: historyHeader.height
                height: historyHeader.height
                icon.name: "edit-clear-all"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                icon.color: Kirigami.Theme.negativeTextColor
                enabled: appSettings.exportHistory.length > 0
                Accessible.name: qsTr("Clear exports")
                Controls.ToolTip.text: qsTr("Clear the history without deleting exported files")
                Controls.ToolTip.visible: hovered
                onClicked: historyWindow.clearHistory()
            }]
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    Kirigami.Heading {
                        Layout.fillWidth: true
                        text: qsTr("Export History")
                        level: 1
                        elide: Text.ElideRight
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: (exportsList.count === 1 ? qsTr("1 export") : qsTr("%1 exports").arg(exportsList.count)) + " · " + qsTr("All Figma files")
                        opacity: 0.72
                        elide: Text.ElideRight
                    }
                }
                Controls.TextField {
                    id: exportSearch
                    objectName: "exportSearch"
                    Layout.preferredWidth: Math.min(260, historyWindow.width * 0.4)
                    placeholderText: qsTr("Search exports")
                    leftPadding: 12 + Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                    selectByMouse: true
                    enabled: historyWindow.activeRemovals === 0
                    onTextChanged: historyWindow.syncHistory(false)
                    Kirigami.Icon {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: "edit-find"
                        opacity: 0.65
                    }
                }
            }

            ListView {
                id: exportsList
                objectName: "exportsList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing
                clip: true
                model: historyModel
                boundsBehavior: Flickable.StopAtBounds
                interactive: historyWindow.activeRemovals === 0
                removeDisplaced: Transition {
                    NumberAnimation { properties: "y"; duration: appSettings.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic }
                }
                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    id: exportsScrollBar
                }
                delegate: Controls.ItemDelegate {
                    id: entry
                    objectName: "exportHistoryEntry"
                    required property var modelData
                    property bool animateRemoval: false
                    property int removalDelay: 0
                    property real slideOffset: 0
                    // Release all removed rows together so staggered exits cannot shift later rows.
                    ListView.delayRemove: animateRemoval && historyWindow.activeRemovals > 0
                    ListView.onRemove: {
                        if (animateRemoval && !appSettings.reduceMotion) removalAnimation.start()
                    }
                    enabled: !animateRemoval
                    transform: Translate { x: entry.slideOffset }
                    SequentialAnimation {
                        id: removalAnimation
                        onStarted: historyWindow.activeRemovals++
                        onFinished: historyWindow.activeRemovals--
                        PauseAnimation { duration: entry.removalDelay }
                        ParallelAnimation {
                            NumberAnimation { target: entry; property: "slideOffset"; to: entry.width; duration: historyWindow.removalDuration; easing.type: Easing.OutCubic }
                            NumberAnimation { target: entry; property: "opacity"; to: 0; duration: historyWindow.removalDuration; easing.type: Easing.InQuad }
                        }
                    }
                    width: exportsList.width - (exportsScrollBar.visible ? exportsScrollBar.width + Kirigami.Units.smallSpacing : 0)
                    padding: Kirigami.Units.largeSpacing
                    hoverEnabled: true
                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing * 1.5
                        color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, entry.hovered ? 0.05 : 0.025))
                        border.width: 1
                        border.color: entry.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Rectangle {
                            Layout.preferredWidth: 96
                            Layout.preferredHeight: 80
                            radius: Kirigami.Units.smallSpacing
                            color: Kirigami.Theme.backgroundColor
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                            clip: true
                            Image {
                                id: preview
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                source: entry.modelData.url
                                sourceSize.width: 192
                                sourceSize.height: 160
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                            }
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 40
                                height: 40
                                source: "text-x-generic"
                                visible: preview.status !== Image.Ready
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: Kirigami.Units.smallSpacing / 2
                            Controls.Label {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Rectangle {
                                    implicitWidth: typeLabel.implicitWidth + 12
                                    implicitHeight: typeLabel.implicitHeight + 4
                                    radius: 4
                                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.12)
                                    Controls.Label {
                                        id: typeLabel
                                        anchors.centerIn: parent
                                        text: entry.modelData.fileType || qsTr("File")
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                                Controls.Label {
                                    objectName: "exportOriginLabel"
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: qsTr("From %1").arg(entry.modelData.originName || qsTr("Unknown origin"))
                                    elide: Text.ElideRight
                                    opacity: 0.7
                                    font: Kirigami.Theme.smallFont
                                    Controls.ToolTip.text: text
                                    Controls.ToolTip.visible: originHover.hovered
                                    HoverHandler {
                                        id: originHover
                                    }
                                }
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: entry.modelData.path
                                elide: Text.ElideMiddle
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                Controls.ToolTip.text: text
                                Controls.ToolTip.visible: pathHover.hovered
                                HoverHandler {
                                    id: pathHover
                                }
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: Qt.formatDateTime(new Date(entry.modelData.exportedAt), "MMM d, yyyy · hh:mm")
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                            }
                        }
                        RowLayout {
                            spacing: 0
                            Controls.ToolButton {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                icon.name: "folder-open"
                                icon.width: Kirigami.Units.iconSizes.smallMedium
                                icon.height: Kirigami.Units.iconSizes.smallMedium
                                Accessible.name: qsTr("Open export folder")
                                Controls.ToolTip.text: Accessible.name
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    if (!appSettings.openExport(entry.modelData.path, true))
                                        historyWindow.showPassiveNotification(qsTr("Could not open the export folder."));
                                }
                            }
                            Controls.ToolButton {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                icon.name: "document-open"
                                icon.width: Kirigami.Units.iconSizes.smallMedium
                                icon.height: Kirigami.Units.iconSizes.smallMedium
                                Accessible.name: qsTr("Open exported file")
                                Controls.ToolTip.text: Accessible.name
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    if (!appSettings.openExport(entry.modelData.path, false))
                                        historyWindow.showPassiveNotification(qsTr("Could not open the exported file."));
                                }
                            }
                            Controls.ToolButton {
                                objectName: "deleteExportButton"
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                icon.name: "edit-delete"
                                icon.width: Kirigami.Units.iconSizes.smallMedium
                                icon.height: Kirigami.Units.iconSizes.smallMedium
                                Accessible.name: qsTr("Delete exported file")
                                Controls.ToolTip.text: Accessible.name
                                Controls.ToolTip.visible: hovered
                                onClicked: {
                                    if (!appSettings.deleteExport(entry.modelData.path))
                                        historyWindow.showPassiveNotification(qsTr("Could not delete the exported file."));
                                }
                            }
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: eventPoint => entryMenu.popup(eventPoint.position.x, eventPoint.position.y)
                    }
                    Controls.Menu {
                        id: entryMenu
                        objectName: "exportItemMenu"
                        Controls.MenuItem {
                            text: qsTr("Copy file path")
                            icon.name: "edit-copy"
                            onTriggered: appSettings.copyToClipboard(entry.modelData.path)
                        }
                    }
                }
                Kirigami.PlaceholderMessage {
                    objectName: "exportsPlaceholder"
                    anchors.centerIn: parent
                    width: parent.width - 48
                    visible: exportsList.count === 0 && historyWindow.activeRemovals === 0 && exportsList.contentHeight <= 0
                    icon.name: "document-export"
                    text: exportSearch.text.trim() ? qsTr("No matching exports") : qsTr("No exports yet")
                    explanation: exportSearch.text.trim() ? qsTr("Try another filename, file type, or Figma file.")
                                                         : qsTr("Export a document or object to see it here.")
                }
            }
        }
    }
    WindowResizeHandles {
        parent: historyWindow.contentItem
        anchors.fill: parent
        active: historyWindow.framelessControls
        targetWindow: historyWindow
    }
}
