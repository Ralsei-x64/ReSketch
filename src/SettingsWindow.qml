// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import "Shortcuts.js" as Shortcuts

Kirigami.ApplicationWindow {
    id: settingsWindow
    transientParent: null
    objectName: "settingsWindow"
    component SectionButton: Controls.ItemDelegate {
        required property var modelData
        required property int index
        objectName: "settingsSection-" + index
        Layout.fillWidth: true
        Layout.preferredHeight: 76
        id: sectionButton
        highlighted: settingsWindow.selectedSection === index
        onClicked: settingsWindow.selectedSection = index
        contentItem: Column {
            spacing: 5
            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28; height: 28
                source: modelData.icon
                color: sectionButton.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
            Controls.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.title
                color: sectionButton.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
        }
    }
    property int selectedSection: 0
    property int previousSection: 0
    onSelectedSectionChanged: {
        sectionTransition.stop()
        if (visible && !appSettings.reduceMotion) {
            sectionSlide.x = selectedSection < previousSection ? -24 : 24
            sectionBody.opacity = 0.7
            sectionTransition.start()
        }
        previousSection = selectedSection
        sectionScroll.contentItem.contentY = 0
    }
    onVisibleChanged: if (!visible) sectionTransition.stop()
    Connections {
        target: appSettings
        function onChanged() { if (appSettings.reduceMotion) sectionTransition.stop() }
    }
    property var streamerOverlay: null
    property string shortcutError: ""
    function setShortcut(id, sequence) {
        const conflict = sequence && Shortcuts.items.find(item => item.id !== id
            && appSettings.shortcutSequenceText(Shortcuts.sequence(appSettings, item.id)) === sequence)
        if (conflict) {
            shortcutError = qsTr("This shortcut is already assigned to %1.").arg(conflict.title)
            return
        }
        const overrides = Object.assign({}, appSettings.shortcutOverrides)
        if (sequence === Shortcuts.items.find(item => item.id === id).defaultSequence) delete overrides[id]
        else overrides[id] = sequence
        appSettings.shortcutOverrides = overrides
        shortcutError = ""
    }
    function resetShortcut(id) {
        setShortcut(id, appSettings.shortcutSequenceText(Shortcuts.items.find(item => item.id === id).defaultSequence))
    }
    property int toolbarDraggedIndex: -1
    property int toolbarDropIndex: -1
    function moveToolbarItem(from, to) {
        const items = appSettings.toolbarItems.slice()
        if (from < 0 || to < 0 || from >= items.length || to >= items.length || from === to) return
        items.splice(to, 0, items.splice(from, 1)[0])
        appSettings.toolbarItems = items
    }
    function toggleToolbarItem(id, checked) {
        appSettings.toolbarItems = appSettings.toolbarItems.map(item => item.id === id
            ? Object.assign({}, item, {enabled: checked}) : item)
    }
    readonly property var sections: [
        {title: "Home", icon: "go-home"},
        {title: "Appearance", icon: "preferences-desktop-theme"},
        {title: "Tabs", icon: "tab-duplicate"},
        {title: "Performance", icon: "preferences-system-performance"},
        {title: "Notifications", icon: "preferences-desktop-notification"},
        {title: "Toolbar", icon: "configure"},
        {title: "Shortcuts", icon: "preferences-desktop-keyboard"},
        {title: "Streamer", icon: "preferences-desktop-keyboard"},
        {title: "Updates", icon: "view-refresh"}
    ]
    onClosing: {
        cssSaveTimer.stop()
        appSettings.figmaCustomCss = customCssEditor.text
    }
    readonly property bool framelessControls: !appSettings.safeMode && appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    width: 880
    height: 700
    minimumWidth: 650
    minimumHeight: 420
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: appSettings.safeMode ? "ReSketch — Safe Mode Settings" : "ReSketch — Settings"
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    ScrollGestureArea {
        parent: sectionScroll
        flickable: sectionScroll.contentItem
        nestedFlickables: [cssScroll.contentItem]
    }
    ScrollGestureArea {
        parent: sectionNavigation
        flickable: sectionNavigation.contentItem
    }

    Timer {
        interval: 5000
        repeat: true
        running: settingsWindow.visible && settingsWindow.selectedSection === 3
        onRunningChanged: if (running) appSettings.refreshMemoryUsage()
        onTriggered: appSettings.refreshMemoryUsage()
    }

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        header: ExternalWindowHeader {
            targetWindow: settingsWindow
            title: appSettings.safeMode ? qsTr("Safe Mode Settings") : qsTr("Settings")
            iconName: "configure"
        }
        RowLayout {
            anchors.fill: parent
            spacing: 0
            ColumnLayout {
                objectName: "settingsNavigation"
                Layout.minimumWidth: 164
                Layout.maximumWidth: 164
                Layout.preferredWidth: 164
                Layout.fillHeight: true
                spacing: 4
                Controls.ScrollView {
                    id: sectionNavigation
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: sectionNavigation.availableWidth
                        spacing: 4
                        Repeater {
                            model: settingsWindow.sections
                            SectionButton {}
                        }
                    }
                }
            }
            Kirigami.Separator { Layout.fillHeight: true }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.fillHeight: true
                Layout.margins: 14
                spacing: 12
                Item {
                    objectName: "settingsSectionViewport"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.fillHeight: true
                    clip: true
                    ColumnLayout {
                        id: sectionBody
                        objectName: "settingsSectionBody"
                        anchors.fill: parent
                        spacing: 12
                        transform: Translate { id: sectionSlide; objectName: "settingsSectionSlide" }
                        ParallelAnimation {
                            id: sectionTransition
                            objectName: "settingsSectionTransition"
                            NumberAnimation { target: sectionSlide; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: sectionBody; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                            onStopped: { sectionSlide.x = 0; sectionBody.opacity = 1 }
                        }
                        Kirigami.Heading {
                            text: settingsWindow.sections[settingsWindow.selectedSection].title
                            level: 2
                        }
                        Kirigami.Separator { Layout.fillWidth: true }
                        Kirigami.InlineMessage {
                            Layout.fillWidth: true
                            visible: appSettings.safeMode
                            text: "Safe mode: GPU acceleration and the Figma interface are disabled. Change saved settings, then restart ReSketch normally."
                            type: Kirigami.MessageType.Information
                        }
                        ColumnLayout {
                            visible: settingsWindow.selectedSection === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Kirigami.Units.largeSpacing
                            Controls.Frame {
                                Layout.fillWidth: true
                                padding: Kirigami.Units.largeSpacing
                                contentItem: ColumnLayout {
                                    spacing: Kirigami.Units.largeSpacing
                                    RowLayout {
                                        spacing: Kirigami.Units.largeSpacing
                                        Image {
                                            Layout.preferredWidth: 80
                                            Layout.preferredHeight: 80
                                            source: "qrc:/Branding/SketchbookPNG/Folder-256.png"
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        Kirigami.Heading { text: qsTr("ReSketch"); level: 1 }
                                    }
                                    Controls.Label {
                                        Layout.fillWidth: true
                                        text: qsTr("An open-source Figma client for Linux. Work with your designs in a native desktop window, with tabs, customizable shortcuts and tools that fit your workflow.")
                                        wrapMode: Text.WordWrap
                                    }
                                    Controls.Button {
                                        objectName: "settingsGitHubButton"
                                        text: qsTr("View GitHub")
                                        icon.name: "internet-web-browser"
                                        onClicked: Qt.openUrlExternally("https://github.com/Ralsei-x64/ReSketch")
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                            Controls.Label {
                                objectName: "settingsHomeVersion"
                                Layout.alignment: Qt.AlignHCenter
                                text: qsTr("Version %1 · Commit %2").arg(Qt.application.version).arg(appSettings.buildCommit)
                                opacity: 0.75
                            }
                        }
                        Controls.Frame {
                            visible: settingsWindow.selectedSection === 7
                            Layout.fillWidth: true
                            padding: Kirigami.Units.largeSpacing
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Heading { text: qsTr("Live key preview"); level: 3 }
                                Rectangle {
                                    id: previewBackdrop
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(160, Math.max(88, keyPreview.tileHeight + 24))
                                    color: Kirigami.Theme.alternateBackgroundColor
                                    radius: 4
                                    clip: true
                                    Rectangle {
                                        id: previewScene
                                        anchors.fill: parent
                                        color: previewBackdrop.color
                                        Repeater {
                                            model: Math.ceil(previewScene.width / 40)
                                            Rectangle {
                                                required property int index
                                                x: index * 40
                                                width: 20; height: previewScene.height
                                                color: Kirigami.Theme.textColor
                                                opacity: 0.12
                                            }
                                        }
                                    }
                                    StreamerOverlay {
                                        id: keyPreview
                                        objectName: "streamerSettingsPreview"
                                        anchors.centerIn: parent
                                        scale: Math.max(0.01, Math.min(1, parent.height / (tileHeight + 24)))
                                        width: parent.width / scale
                                        height: parent.height / scale
                                        preview: true
                                        targetWindow: settingsWindow
                                        backdropSource: previewScene
                                    }
                                }
                            }
                        }
                        Controls.ScrollView {
                            id: sectionScroll
                            Layout.minimumWidth: 0
                            visible: settingsWindow.selectedSection !== 0
                            objectName: "settingsSectionScroll"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            ColumnLayout {
                                width: sectionScroll.availableWidth
                                spacing: Kirigami.Units.largeSpacing
                                StreamerSettings {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 7
                                    overlay: settingsWindow.streamerOverlay
                                }
                                UpdateSettings {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 8
                                    updater: appSettings.updates
                                }
                                Controls.Frame {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 6
                                    padding: 0
                                    background: Item {}
                                    contentItem: ColumnLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Click a shortcut to record new keys. Use its clear button to disable it.")
                                            wrapMode: Text.WordWrap
                                        }
                                        Kirigami.InlineMessage {
                                            Layout.fillWidth: true
                                            visible: !!settingsWindow.shortcutError
                                            type: Kirigami.MessageType.Error
                                            text: settingsWindow.shortcutError
                                        }
                                        Repeater {
                                            model: [...new Set(Shortcuts.items.map(item => item.category))]
                                            SettingsGroup {
                                                id: categoryFrame
                                                required property string modelData
                                                objectName: "shortcutCategory-" + modelData
                                                title: modelData
                                                Repeater {
                                                    model: Shortcuts.items.filter(item => item.category === categoryFrame.modelData)
                                                    RowLayout {
                                                        id: shortcutRow
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        Controls.Label {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            text: shortcutRow.modelData.title
                                                            wrapMode: Text.WordWrap
                                                        }
                                                        KQuickControls.KeySequenceItem {
                                                            objectName: "shortcutEditor-" + shortcutRow.modelData.id
                                                            Layout.preferredWidth: 220
                                                            keySequence: Shortcuts.sequence(appSettings, shortcutRow.modelData.id)
                                                            modifierlessAllowed: true
                                                            multiKeyShortcutsAllowed: false
                                                            checkForConflictsAgainst: 0
                                                            Accessible.name: shortcutRow.modelData.title
                                                            onKeySequenceModified: {
                                                                settingsWindow.setShortcut(shortcutRow.modelData.id,
                                                                    appSettings.shortcutSequenceText(keySequence))
                                                                keySequence = Qt.binding(() => Shortcuts.sequence(appSettings, shortcutRow.modelData.id))
                                                            }
                                                        }
                                                        Controls.ToolButton {
                                                            objectName: "resetShortcut-" + shortcutRow.modelData.id
                                                            icon.name: "edit-undo"
                                                            enabled: Object.prototype.hasOwnProperty.call(appSettings.shortcutOverrides, shortcutRow.modelData.id)
                                                            Accessible.name: qsTr("Reset %1 shortcut").arg(shortcutRow.modelData.title)
                                                            Controls.ToolTip.text: qsTr("Reset to %1").arg(shortcutRow.modelData.defaultSequence)
                                                            Controls.ToolTip.visible: hovered
                                                            onClicked: settingsWindow.resetShortcut(shortcutRow.modelData.id)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Controls.Button {
                                            objectName: "resetAllShortcuts"
                                            Layout.topMargin: Kirigami.Units.largeSpacing
                                            text: qsTr("Reset all shortcuts to defaults")
                                            icon.name: "edit-undo"
                                            onClicked: {
                                                appSettings.shortcutOverrides = {}
                                                settingsWindow.shortcutError = ""
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 5
                                    spacing: Kirigami.Units.largeSpacing

                                    SettingsGroup {
                                        title: qsTr("Toolbar buttons")
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Choose which buttons appear next to the tabs. Drag the handles or use the arrows to change their order.")
                                            wrapMode: Text.WordWrap
                                        }

                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Changes apply immediately. Right-click Home or empty space in the tab bar to configure the toolbar again.")
                                            opacity: 0.72
                                            wrapMode: Text.WordWrap
                                        }

                                        Item {
                                            objectName: "toolbarSettingsList"
                                            Layout.fillWidth: true
                                            implicitHeight: appSettings.toolbarItems.length * 48
                                            Repeater {
                                                objectName: "toolbarSettingsRepeater"
                                                model: appSettings.toolbarItems.length
                                                Rectangle {
                                                    id: toolbarRow
                                                    required property int index
                                                    readonly property var item: appSettings.toolbarItems[index]
                                                    objectName: "toolbarSettingsRow-" + item.id
                                                    x: 0; y: index * 48
                                                    width: parent.width; height: 44
                                                    radius: Kirigami.Units.smallSpacing
                                                    color: settingsWindow.toolbarDropIndex === index ? Kirigami.Theme.alternateBackgroundColor
                                                                                                   : Kirigami.Theme.backgroundColor
                                                    border.width: 1
                                                    border.color: settingsWindow.toolbarDropIndex === index ? Kirigami.Theme.highlightColor
                                                                                                          : Qt.rgba(Kirigami.Theme.textColor.r,
                                                                                                                    Kirigami.Theme.textColor.g,
                                                                                                                    Kirigami.Theme.textColor.b, 0.15)
                                                    z: toolbarRowDrag.active ? 2 : 0
                                                    transform: Translate { y: toolbarRowDrag.active ? toolbarRowDrag.activeTranslation.y : 0 }
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        spacing: 8
                                                        Item {
                                                            objectName: "toolbarDragHandle-" + toolbarRow.item.id
                                                            Layout.preferredWidth: 28
                                                            Layout.fillHeight: true
                                                            Accessible.name: qsTr("Drag to move %1").arg(toolbarRow.item.title)
                                                            Kirigami.Icon {
                                                                anchors.centerIn: parent
                                                                width: 18; height: width
                                                                source: "drag-handle-symbolic"
                                                            }
                                                            DragHandler {
                                                                id: toolbarRowDrag
                                                                target: null
                                                                acceptedButtons: Qt.LeftButton
                                                                onActiveChanged: {
                                                                    if (active) {
                                                                        settingsWindow.toolbarDraggedIndex = toolbarRow.index
                                                                        settingsWindow.toolbarDropIndex = toolbarRow.index
                                                                    } else if (settingsWindow.toolbarDraggedIndex === toolbarRow.index) {
                                                                        const destination = settingsWindow.toolbarDropIndex
                                                                        settingsWindow.toolbarDraggedIndex = -1
                                                                        settingsWindow.toolbarDropIndex = -1
                                                                        settingsWindow.moveToolbarItem(toolbarRow.index, destination)
                                                                    }
                                                                }
                                                                onActiveTranslationChanged: if (active)
                                                                    settingsWindow.toolbarDropIndex = Math.max(0, Math.min(appSettings.toolbarItems.length - 1,
                                                                        Math.round(toolbarRow.index + activeTranslation.y / 48)))
                                                            }
                                                        }
                                                        Kirigami.Icon {
                                                            Layout.preferredWidth: 20
                                                            Layout.preferredHeight: 20
                                                            source: toolbarRow.item.icon
                                                        }
                                                        Controls.CheckBox {
                                                            objectName: "toolbarToggle-" + toolbarRow.item.id
                                                            Layout.fillWidth: true
                                                            text: toolbarRow.item.title
                                                            checked: toolbarRow.item.enabled
                                                            onToggled: settingsWindow.toggleToolbarItem(toolbarRow.item.id, checked)
                                                        }
                                                        Controls.ToolButton {
                                                            objectName: "toolbarMoveUp-" + toolbarRow.item.id
                                                            icon.name: "go-up"
                                                            enabled: toolbarRow.index > 0
                                                            Accessible.name: qsTr("Move %1 up").arg(toolbarRow.item.title)
                                                            Controls.ToolTip.text: Accessible.name
                                                            Controls.ToolTip.visible: hovered
                                                            onClicked: settingsWindow.moveToolbarItem(toolbarRow.index, toolbarRow.index - 1)
                                                        }
                                                        Controls.ToolButton {
                                                            objectName: "toolbarMoveDown-" + toolbarRow.item.id
                                                            icon.name: "go-down"
                                                            enabled: toolbarRow.index < appSettings.toolbarItems.length - 1
                                                            Accessible.name: qsTr("Move %1 down").arg(toolbarRow.item.title)
                                                            Controls.ToolTip.text: Accessible.name
                                                            Controls.ToolTip.visible: hovered
                                                            onClicked: settingsWindow.moveToolbarItem(toolbarRow.index, toolbarRow.index + 1)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Desktop menus")
                                        Controls.CheckBox {
                                            text: "Integrate Figma menus with Plasma"
                                            checked: appSettings.menuIntegration
                                            onToggled: appSettings.menuIntegration = checked
                                            Controls.ToolTip.text: "Export Figma actions to the global menu. Changes apply immediately."
                                            Controls.ToolTip.visible: hovered
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 1
                                    spacing: Kirigami.Units.largeSpacing

                                    SettingsGroup {
                                        title: qsTr("Theme")
                                        Kirigami.FormLayout {
                                            id: themeForm
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                objectName: "useSystemColorsCheck"
                                                Kirigami.FormData.label: qsTr("Colors:")
                                                text: qsTr("Use system colors")
                                                checked: appSettings.useSystemColors
                                                onToggled: appSettings.useSystemColors = checked
                                            }

                                            Controls.ComboBox {
                                                objectName: "appThemeCombo"
                                                Kirigami.FormData.label: "App theme:"
                                                enabled: !appSettings.useSystemColors
                                                model: [qsTr("Light"), qsTr("Dark")]
                                                currentIndex: appSettings.theme === "dark" ? 1 : 0
                                                onActivated: appSettings.theme = ["light", "dark"][currentIndex]
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Motion and scrolling")
                                        Kirigami.FormLayout {
                                            id: motionForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Motion:"
                                                text: "Reduce motion"
                                                checked: appSettings.reduceMotion
                                                onToggled: appSettings.reduceMotion = checked
                                            }

                                            Controls.CheckBox {
                                                objectName: "smoothScrollingCheck"
                                                Kirigami.FormData.label: "Scrolling:"
                                                text: qsTr("Smooth scrolling")
                                                checked: appSettings.smoothScrolling
                                                onToggled: appSettings.smoothScrolling = checked
                                            }

                                            Controls.CheckBox {
                                                objectName: "inertialScrollingCheck"
                                                text: qsTr("Scroll inertia")
                                                checked: appSettings.inertialScrolling
                                                onToggled: appSettings.inertialScrolling = checked
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, motionForm.width - (motionForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: qsTr("Applies to Figma and the app interface. Reduce motion pauses these effects. Scrolling direction follows your desktop settings.")
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, motionForm.width - (motionForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: qsTr("Scroll speed:")
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    objectName: "mouseScrollSensitivityControl"
                                                    Layout.fillWidth: true
                                                    from: 25
                                                    to: 500
                                                    stepSize: 5
                                                    value: appSettings.mouseScrollSensitivity
                                                    onMoved: appSettings.mouseScrollSensitivity = Math.round(value)
                                                    Accessible.name: qsTr("Scroll speed")
                                                }
                                                Controls.Label {
                                                    text: appSettings.mouseScrollSensitivity + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, motionForm.width - (motionForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: qsTr("Gesture sensitivity:")
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    objectName: "gestureSensitivityControl"
                                                    Layout.fillWidth: true
                                                    from: 25
                                                    to: 300
                                                    stepSize: 5
                                                    value: appSettings.gestureSensitivity
                                                    onMoved: appSettings.gestureSensitivity = Math.round(value)
                                                    Accessible.name: qsTr("Gesture sensitivity")
                                                }
                                                Controls.Label {
                                                    text: appSettings.gestureSensitivity + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, motionForm.width - (motionForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: qsTr("Gesture sensitivity adjusts pinch zoom, pinch overview and sidebar tab swipes. 100% is the normal sensitivity.")
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Window appearance")
                                        Kirigami.FormLayout {
                                            id: windowAppearanceForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, windowAppearanceForm.width - (windowAppearanceForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Background opacity:"
                                                Layout.fillWidth: true
                                                spacing: Kirigami.Units.smallSpacing

                                                Controls.Slider {
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 100
                                                    stepSize: 1
                                                    value: appSettings.toolbarOpacity
                                                    onMoved: appSettings.toolbarOpacity = Math.round(value)
                                                }

                                                Controls.Label {
                                                    text: appSettings.toolbarOpacity + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Background blur:"
                                                text: "Ignore blur"
                                                checked: appSettings.ignoreToolbarBlur
                                                onToggled: appSettings.ignoreToolbarBlur = checked
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Window controls:"
                                                text: "Show in tab bar"
                                                checked: appSettings.windowControlsInTabBar
                                                onToggled: appSettings.windowControlsInTabBar = checked
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Title bar:"
                                                text: "Keep window decorations"
                                                enabled: appSettings.windowControlsInTabBar
                                                checked: appSettings.keepWindowDecorations
                                                onToggled: appSettings.keepWindowDecorations = checked
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, windowAppearanceForm.width - (windowAppearanceForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: qsTr("Background opacity applies to the toolbar and desktop backdrop.")
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Figma customization")
                                        Kirigami.FormLayout {
                                            id: figmaCustomizationForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Figma colors:"
                                                text: qsTr("Use app colors (experimental)")
                                                checked: appSettings.figmaSystemColors
                                                onToggled: appSettings.figmaSystemColors = checked
                                            }

                                            Controls.CheckBox {
                                                objectName: "useSystemCursorToggle"
                                                Kirigami.FormData.label: "Canvas cursor:"
                                                text: "Use the system cursor instead of Figma's cursor"
                                                checked: appSettings.useSystemCursor
                                                onToggled: appSettings.useSystemCursor = checked
                                                Controls.ToolTip.text: "Figma's custom canvas cursors are shown by default. Text and resize cursors still follow the current tool."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Figma CSS:"
                                                text: "Enable custom CSS (experimental)"
                                                checked: appSettings.figmaCustomCssEnabled
                                                onToggled: appSettings.figmaCustomCssEnabled = checked
                                            }

                                            Controls.ScrollView {
                                                Layout.maximumWidth: Math.max(180, figmaCustomizationForm.width - (figmaCustomizationForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 140
                                                implicitHeight: 140
                                                id: cssScroll
                                                objectName: "customCssScroll"
                                                visible: appSettings.figmaCustomCssEnabled
                                                Controls.TextArea {
                                                    id: customCssEditor
                                                    objectName: "customCssEditor"
                                                    text: appSettings.figmaCustomCss
                                                    placeholderText: "/* Custom CSS for Figma's interface */"
                                                    font.family: "monospace"
                                                    wrapMode: TextEdit.Wrap
                                                    selectByMouse: true
                                                    onTextChanged: cssSaveTimer.restart()
                                                    Timer {
                                                        id: cssSaveTimer
                                                        interval: 350
                                                        onTriggered: appSettings.figmaCustomCss = customCssEditor.text
                                                    }
                                                }
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, figmaCustomizationForm.width - (figmaCustomizationForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: "Figma appearance changes apply immediately to all tabs. Custom CSS overrides KDE colors."
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Sidebar layout")
                                        Kirigami.FormLayout {
                                            id: sidebarLayoutForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Figma sidebars:"
                                                text: "Translucent left and right sidebars"
                                                checked: appSettings.translucentSidebars
                                                onToggled: appSettings.translucentSidebars = checked
                                            }

                                            Controls.CheckBox {
                                                objectName: "floatingSidebarsToggle"
                                                Kirigami.FormData.label: "Floating sidebars:"
                                                text: "Float sidebars over the Figma file canvas"
                                                checked: appSettings.floatingSidebars
                                                onToggled: appSettings.floatingSidebars = checked
                                            }

                                            Controls.ComboBox {
                                                objectName: "sidebarBackdropControl"
                                                Kirigami.FormData.label: "Sidebar backdrop:"
                                                enabled: appSettings.translucentSidebars || appSettings.floatingSidebars
                                                model: ["Desktop", "Figma canvas"]
                                                currentIndex: appSettings.sidebarBackdrop === "canvas" ? 1 : 0
                                                onActivated: appSettings.sidebarBackdrop = currentIndex === 1 ? "canvas" : "desktop"
                                            }

                                            Controls.SpinBox {
                                                objectName: "sidebarCornerRadiusControl"
                                                Kirigami.FormData.label: "Corner radius (px):"
                                                enabled: appSettings.floatingSidebars
                                                from: 0
                                                to: 40
                                                editable: true
                                                value: appSettings.sidebarCornerRadius
                                                onValueModified: appSettings.sidebarCornerRadius = value
                                            }

                                            Controls.SpinBox {
                                                objectName: "sidebarMarginControl"
                                                Kirigami.FormData.label: "Sidebar margin (px):"
                                                enabled: appSettings.floatingSidebars
                                                from: 0
                                                to: 40
                                                editable: true
                                                value: appSettings.sidebarMargin
                                                onValueModified: appSettings.sidebarMargin = value
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Sidebar effects")
                                        Kirigami.FormLayout {
                                            id: sidebarEffectsForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, sidebarEffectsForm.width - (sidebarEffectsForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Canvas backdrop blur:"
                                                visible: appSettings.sidebarBackdrop === "canvas"
                                                enabled: appSettings.translucentSidebars || appSettings.floatingSidebars
                                                Layout.fillWidth: true

                                                Controls.Slider {
                                                    objectName: "sidebarCanvasBlurControl"
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 40
                                                    stepSize: 1
                                                    value: appSettings.sidebarCanvasBlur
                                                    onMoved: appSettings.sidebarCanvasBlur = Math.round(value)
                                                    Accessible.name: "Canvas backdrop blur"
                                                }
                                                Controls.Label {
                                                    text: appSettings.sidebarCanvasBlur + " px"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, sidebarEffectsForm.width - (sidebarEffectsForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Canvas backdrop opacity:"
                                                visible: appSettings.sidebarBackdrop === "canvas"
                                                enabled: appSettings.translucentSidebars || appSettings.floatingSidebars
                                                Layout.fillWidth: true

                                                Controls.Slider {
                                                    objectName: "sidebarCanvasOpacityControl"
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 100
                                                    stepSize: 1
                                                    value: appSettings.sidebarCanvasOpacity
                                                    onMoved: appSettings.sidebarCanvasOpacity = Math.round(value)
                                                    Accessible.name: "Canvas backdrop opacity"
                                                }
                                                Controls.Label {
                                                    text: appSettings.sidebarCanvasOpacity + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, sidebarEffectsForm.width - (sidebarEffectsForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Shadow transparency:"
                                                enabled: appSettings.floatingSidebars
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    objectName: "sidebarShadowTransparencyControl"
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 100
                                                    stepSize: 1
                                                    value: appSettings.sidebarShadowTransparency
                                                    onMoved: appSettings.sidebarShadowTransparency = Math.round(value)
                                                    Accessible.name: "Floating sidebar shadow transparency"
                                                }
                                                Controls.Label {
                                                    text: appSettings.sidebarShadowTransparency + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, sidebarEffectsForm.width - (sidebarEffectsForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Shadow strength:"
                                                enabled: appSettings.floatingSidebars
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    objectName: "sidebarShadowStrengthControl"
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 100
                                                    stepSize: 1
                                                    value: appSettings.sidebarShadowStrength
                                                    onMoved: appSettings.sidebarShadowStrength = Math.round(value)
                                                    Accessible.name: "Floating sidebar shadow strength"
                                                }
                                                Controls.Label {
                                                    text: appSettings.sidebarShadowStrength + "%"
                                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, sidebarEffectsForm.width - (sidebarEffectsForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: "Canvas backdrop blur and opacity apply to floating and docked sidebars. Shadow strength controls its size and softness; 0% turns it off."
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Scrollbars")
                                        Kirigami.FormLayout {
                                            id: scrollbarsForm
                                            twinFormLayouts: [themeForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                objectName: "hideSidebarScrollbarsToggle"
                                                Kirigami.FormData.label: qsTr("Sidebar scrollbars:")
                                                text: qsTr("Hide Figma sidebar scrollbars")
                                                checked: appSettings.hideSidebarScrollbars
                                                onToggled: appSettings.hideSidebarScrollbars = checked
                                            }

                                            Controls.CheckBox {
                                                objectName: "hideFloatingScrollbarsToggle"
                                                Kirigami.FormData.label: "Canvas scrollbars:"
                                                text: "Hide Figma canvas scrollbars in floating mode"
                                                enabled: appSettings.floatingSidebars
                                                checked: appSettings.hideFloatingScrollbars
                                                onToggled: appSettings.hideFloatingScrollbars = checked
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, scrollbarsForm.width - (scrollbarsForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: "File tabs reload to apply this setting. Sleeping tabs apply it when selected. Canvas scrolling stays enabled."
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 2
                                    spacing: Kirigami.Units.largeSpacing

                                    SettingsGroup {
                                        title: qsTr("Startup and restore")
                                        Kirigami.FormLayout {
                                            id: startupForm
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                objectName: "rememberOpenedTabs"
                                                text: "Remember opened tabs"
                                                checked: appSettings.rememberOpenedTabs
                                                onToggled: appSettings.rememberOpenedTabs = checked
                                                Controls.ToolTip.text: "Restore file tabs and their groups on startup. Empty tabs, Home, and the new-file screen are not saved."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.CheckBox {
                                                objectName: "deferRestoredTabs"
                                                text: "Load restored tabs only when selected"
                                                enabled: appSettings.rememberOpenedTabs
                                                checked: appSettings.deferRestoredTabs
                                                onToggled: appSettings.deferRestoredTabs = checked
                                                Controls.ToolTip.text: "On startup, leave remembered files unloaded until you select their tab or overview card."
                                                Controls.ToolTip.visible: hovered
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Tab sleeping")
                                        Kirigami.FormLayout {
                                            id: sleepingForm
                                            twinFormLayouts: [startupForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.SpinBox {
                                                Kirigami.FormData.label: "Minimum loaded tabs:"
                                                from: 1
                                                to: 5
                                                value: appSettings.minimumLoadedTabs
                                                onValueModified: appSettings.minimumLoadedTabs = value
                                            }

                                            Controls.SpinBox {
                                                Kirigami.FormData.label: "Maximum loaded tabs:"
                                                from: 1
                                                to: 100
                                                editable: true
                                                value: appSettings.maximumLoadedTabs
                                                onValueModified: appSettings.maximumLoadedTabs = value
                                                Controls.ToolTip.text: "Sleep the least recently used tabs immediately when this limit is exceeded, including in the overview."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.SpinBox {
                                                Kirigami.FormData.label: "Sleep after (minutes):"
                                                from: 1
                                                to: 240
                                                editable: true
                                                value: appSettings.sleepMinutes
                                                onValueModified: appSettings.sleepMinutes = value
                                            }

                                            Controls.CheckBox {
                                                text: "Keep Home running"
                                                enabled: !appSettings.desktopNotifications
                                                checked: appSettings.keepHomeAwake
                                                onToggled: appSettings.keepHomeAwake = checked
                                                Controls.ToolTip.text: appSettings.desktopNotifications
                                                                      ? "Home stays running while desktop notifications are enabled."
                                                                      : "Keep Home awake regardless of the sleep timer or loaded-tab limit. Turn off to let Home sleep like other tabs."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, sleepingForm.width - (sleepingForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: "The maximum tab count takes priority over the minimum loaded tabs."
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Overview previews")
                                        Kirigami.FormLayout {
                                            id: overviewForm
                                            twinFormLayouts: [startupForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                text: "Show sleeping tabs in overview"
                                                checked: appSettings.sleepingTabPreviews
                                                onToggled: appSettings.sleepingTabPreviews = checked
                                                Controls.ToolTip.text: "Show saved, blurred previews with a sleep icon. When disabled, opening the overview wakes tabs to show normal live previews; the tab limit resumes when the overview closes."
                                                Controls.ToolTip.visible: hovered
                                            }
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 4
                                    spacing: Kirigami.Units.largeSpacing

                                    SettingsGroup {
                                        title: qsTr("Desktop notifications")
                                        Controls.CheckBox {
                                            objectName: "desktopNotifications"
                                            text: "Enable desktop notifications"
                                            checked: appSettings.desktopNotifications
                                            onToggled: appSettings.desktopNotifications = checked
                                        }

                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: "Receive Figma activity through your desktop's notification system. Home stays running to receive updates. Turning this off stops notification checks and desktop alerts immediately."
                                            wrapMode: Text.WordWrap
                                            opacity: 0.72
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: settingsWindow.selectedSection === 3
                                    spacing: Kirigami.Units.largeSpacing

                                    SettingsGroup {
                                        title: qsTr("Memory limit")
                                        Kirigami.FormLayout {
                                            id: memoryForm
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, memoryForm.width - (memoryForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Total memory limit:"
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    id: memoryLimitSlider
                                                    objectName: "memoryLimitSlider"
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 32768
                                                    stepSize: 512
                                                    snapMode: Controls.Slider.SnapAlways
                                                    value: appSettings.memoryLimitMiB
                                                    onMoved: if (!pressed) appSettings.memoryLimitMiB = Math.round(value)
                                                    onPressedChanged: if (!pressed) appSettings.memoryLimitMiB = Math.round(value)
                                                }
                                                Controls.Label {
                                                    Layout.preferredWidth: 68
                                                    horizontalAlignment: Text.AlignRight
                                                    text: memoryLimitSlider.value === 0 ? qsTr("Unlimited")
                                                          : qsTr("%1 GiB").arg((memoryLimitSlider.value / 1024).toFixed(1))
                                                }
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, memoryForm.width - (memoryForm.wideMode ? 210 : 0))
                                                objectName: "totalMemoryUsageLabel"
                                                Layout.fillWidth: true
                                                text: qsTr("Current total: %1 MiB").arg(Math.round(appSettings.totalAppMemoryMiB))
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, memoryForm.width - (memoryForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: qsTr("Includes the app and all Chromium processes, counting shared memory once. Unloads the least recently used background tabs until usage falls below the limit. Unloaded tabs reload when selected. Active tabs and Home kept running are protected, so this is a target rather than a hard cap.")
                                                wrapMode: Text.WordWrap
                                                opacity: 0.72
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Interface and preview resources")
                                        Kirigami.FormLayout {
                                            id: interfaceResourcesForm
                                            twinFormLayouts: [memoryForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "UI memory:"
                                                text: "Release closed secondary windows"
                                                checked: appSettings.releaseClosedWindows
                                                onToggled: appSettings.releaseClosedWindows = checked
                                                Controls.ToolTip.text: "Free Settings, About, and Export History after closing them. They are created again when opened; settings and window size are preserved."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.CheckBox {
                                                text: "Release effects for offscreen overview cards"
                                                checked: appSettings.cullOffscreenOverviewEffects
                                                onToggled: appSettings.cullOffscreenOverviewEffects = checked
                                                Controls.ToolTip.text: "Allocate clipping and blur textures only for visible cards. Tabs continue running normally."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.CheckBox {
                                                text: "Use compact sleeping-preview textures"
                                                checked: appSettings.compactPreviewTextures
                                                onToggled: appSettings.compactPreviewTextures = checked
                                                Controls.ToolTip.text: "Limit sleeping-preview effects to 640 × 480 pixels. Live card quality is controlled by the overview preview quality slider."
                                                Controls.ToolTip.visible: hovered
                                            }

                                            RowLayout {
                                                Layout.maximumWidth: Math.max(180, interfaceResourcesForm.width - (interfaceResourcesForm.wideMode ? 210 : 0))
                                                Kirigami.FormData.label: "Overview preview quality:"
                                                Layout.fillWidth: true
                                                Controls.Slider {
                                                    id: overviewQualitySlider
                                                    objectName: "overviewPreviewQuality"
                                                    Layout.fillWidth: true
                                                    from: 25
                                                    to: 100
                                                    stepSize: 5
                                                    value: appSettings.overviewPreviewQuality
                                                    onMoved: appSettings.overviewPreviewQuality = Math.round(value)
                                                    Controls.ToolTip.text: "Lower quality uses less memory for live and sleeping previews. Normal tabs stay at full resolution."
                                                    Controls.ToolTip.visible: hovered
                                                }
                                                Controls.Label { text: Math.round(overviewQualitySlider.value) + "%" }
                                            }
                                        }
                                    }

                                    SettingsGroup {
                                        title: qsTr("Chromium rendering")
                                        Kirigami.FormLayout {
                                            id: chromiumForm
                                            twinFormLayouts: [memoryForm]
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wideMode: width >= 560

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Chromium:"
                                                text: "GPU rasterization"
                                                checked: appSettings.gpuRasterization
                                                onToggled: appSettings.gpuRasterization = checked
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Raster tiles:"
                                                text: "Zero-copy rendering"
                                                checked: appSettings.zeroCopyRasterization
                                                onToggled: appSettings.zeroCopyRasterization = checked
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Canvas:"
                                                text: "Experimental canvas features"
                                                checked: appSettings.experimentalCanvasFeatures
                                                onToggled: appSettings.experimentalCanvasFeatures = checked
                                                Controls.ToolTip.text: "--enable-experimental-canvas-features"
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.CheckBox {
                                                Kirigami.FormData.label: "Graphics:"
                                                text: "Use Vulkan"
                                                checked: appSettings.useVulkan
                                                onToggled: appSettings.useVulkan = checked
                                                Controls.ToolTip.text: "--use-vulkan=native (with ANGLE and Vulkan compositing)"
                                                Controls.ToolTip.visible: hovered
                                            }

                                            Controls.TextField {
                                                Kirigami.FormData.label: "Extra switches:"
                                                Layout.fillWidth: true
                                                text: appSettings.chromiumFlags
                                                placeholderText: "--enable-features=..."
                                                onTextEdited: appSettings.chromiumFlags = text
                                            }

                                            Controls.Label {
                                                Layout.maximumWidth: Math.max(180, chromiumForm.width - (chromiumForm.wideMode ? 210 : 0))
                                                Layout.fillWidth: true
                                                text: qsTr("Restart ReSketch to apply Chromium changes. Extra switches override the options above.")
                                                opacity: 0.72
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true
                    Controls.Button {
                        objectName: "resetSettingsButton"
                        text: "Defaults"
                        icon.name: "edit-undo"
                        Controls.ToolTip.text: "Reset preferences. Sign-in data, export history, and remembered export folders are kept."
                        Controls.ToolTip.visible: hovered
                        onClicked: {
                            cssSaveTimer.stop()
                            appSettings.resetSettings()
                            customCssEditor.text = Qt.binding(() => appSettings.figmaCustomCss)
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: "Changes apply immediately."
                        opacity: 0.7
                    }
                    Controls.Button {
                        text: "Close"
                        icon.name: "window-close"
                        onClicked: settingsWindow.close()
                    }
                }
            }
        }
    }

    WindowResizeHandles {
        parent: settingsWindow.contentItem
        anchors.fill: parent
        active: settingsWindow.framelessControls
        targetWindow: settingsWindow
    }
}
