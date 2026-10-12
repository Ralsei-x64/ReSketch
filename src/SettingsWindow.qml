// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: settingsWindow
    objectName: "settingsWindow"
    property int selectedSection: 0
    readonly property var sections: [
        {title: "Appearance", icon: "preferences-desktop-theme", keywords: "theme colors CSS transparency opacity blur window controls decorations motion"},
        {title: "Tabs", icon: "tab-duplicate", keywords: "sleep remember restore loaded Home"},
        {title: "Performance", icon: "preferences-system-performance", keywords: "memory preview quality menus Chromium GPU Vulkan canvas flags switches"},
        {title: "Notifications", icon: "preferences-desktop-notification", keywords: "desktop alerts enable disable Home"}
    ]
    readonly property var filteredSections: sections.map((section, index) => ({title: section.title, icon: section.icon, keywords: section.keywords, section: index}))
        .filter(section => (section.title + " " + section.keywords).toLowerCase().includes(settingsSearch.text.toLowerCase()))
    onClosing: {
        cssSaveTimer.stop()
        appSettings.figmaCustomCss = customCssEditor.text
    }
    readonly property int chromeHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property bool framelessControls: !appSettings.safeMode && appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    width: 880
    height: 700
    minimumWidth: 650
    minimumHeight: 420
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: appSettings.safeMode ? "ReSketch — Safe Mode Settings" : "ReSketch — Settings"
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    pageStack.initialPage: Kirigami.Page {
        padding: 0
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
        header: Rectangle {
            height: settingsWindow.chromeHeight
            color: Kirigami.Theme.backgroundColor

            Row {
                anchors.fill: parent

                Item {
                    width: parent.width - settingsControls.width
                    height: parent.height

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Kirigami.Units.iconSizes.smallMedium
                            height: width
                            source: "configure"
                        }
                        Controls.Label {
                            text: appSettings.safeMode ? "Safe Mode Settings" : "Settings"
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPressed: settingsWindow.startSystemMove()
                    }
                }

                WindowControls {
                    id: settingsControls
                    targetWindow: settingsWindow
                    buttonSize: settingsWindow.chromeHeight
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
        RowLayout {
            anchors.fill: parent
            spacing: 0
            ColumnLayout {
                Layout.preferredWidth: 164
                Layout.fillHeight: true
                spacing: 4
                Controls.TextField {
                    id: settingsSearch
                    objectName: "settingsSearch"
                    Layout.fillWidth: true
                    Layout.margins: 6
                    placeholderText: "Search settings…"
                    onTextChanged: {
                        if (settingsWindow.filteredSections.length)
                            settingsWindow.selectedSection = settingsWindow.filteredSections[0].section
                    }
                }
                Repeater {
                    model: settingsWindow.filteredSections
                    Controls.ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 76
                        id: sectionButton
                        highlighted: settingsWindow.selectedSection === modelData.section
                        onClicked: settingsWindow.selectedSection = modelData.section
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
                }
                Item { Layout.fillHeight: true }
            }
            Kirigami.Separator { Layout.fillHeight: true }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 14
                spacing: 12
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
                Controls.ScrollView {
                    id: sectionScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: sectionScroll.availableWidth
                        spacing: Kirigami.Units.largeSpacing
                        Controls.Frame {
                            Layout.fillWidth: true
                            visible: settingsWindow.selectedSection === 0
                            padding: 0
                            background: Item { }
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.FormLayout {
                                    Layout.fillWidth: true
                                    wideMode: width >= 560

                                    Controls.ComboBox {
                                        Kirigami.FormData.label: "App theme:"
                                        model: ["Auto", "Light", "Dark"]
                                        currentIndex: Math.max(0, ["auto", "light", "dark"].indexOf(appSettings.theme))
                                        onActivated: appSettings.theme = ["auto", "light", "dark"][currentIndex]
                                    }

                                    Controls.CheckBox {
                                        Kirigami.FormData.label: "Motion:"
                                        text: "Reduce motion"
                                        checked: appSettings.reduceMotion
                                        onToggled: appSettings.reduceMotion = checked
                                    }

                                    Controls.CheckBox {
                                        Kirigami.FormData.label: "Figma colors:"
                                        text: "Use KDE colors (experimental)"
                                        checked: appSettings.figmaSystemColors
                                        onToggled: appSettings.figmaSystemColors = checked
                                    }

                                    Controls.CheckBox {
                                        Kirigami.FormData.label: "Figma CSS:"
                                        text: "Enable custom CSS (experimental)"
                                        checked: appSettings.figmaCustomCssEnabled
                                        onToggled: appSettings.figmaCustomCssEnabled = checked
                                    }

                                    Controls.ScrollView {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 140
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
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: Math.max(200, sectionScroll.availableWidth - 210)
                                        text: "Figma appearance changes apply immediately to all tabs. Custom CSS overrides KDE colors."
                                        opacity: 0.72
                                        wrapMode: Text.WordWrap
                                    }

                                    RowLayout {
                                        Kirigami.FormData.label: "Background opacity:"
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: Math.max(200, sectionScroll.availableWidth - 210)
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
                                        Kirigami.FormData.label: "Figma sidebars:"
                                        text: "Translucent left and right sidebars"
                                        checked: appSettings.translucentSidebars
                                        onToggled: appSettings.translucentSidebars = checked
                                    }

                                    Controls.ComboBox {
                                        Kirigami.FormData.label: "Sidebar backdrop:"
                                        enabled: appSettings.translucentSidebars
                                        model: ["Desktop", "Figma canvas"]
                                        currentIndex: appSettings.sidebarBackdrop === "canvas" ? 1 : 0
                                        onActivated: appSettings.sidebarBackdrop = currentIndex === 1 ? "canvas" : "desktop"
                                    }

                                    Controls.Label {
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: Math.max(200, sectionScroll.availableWidth - 210)
                                        text: "Background opacity controls the toolbar and enabled sidebars. Canvas uses the canvas background where Figma's canvas does not extend behind the sidebars."
                                        opacity: 0.72
                                        wrapMode: Text.WordWrap
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
                                }
                            }
                        }
                        Controls.Frame {
                            Layout.fillWidth: true
                            visible: settingsWindow.selectedSection === 1
                            padding: 0
                            background: Item { }
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.FormLayout {
                                    Layout.fillWidth: true
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

                                    Controls.CheckBox {
                                        text: "Show sleeping tabs in overview"
                                        checked: appSettings.sleepingTabPreviews
                                        onToggled: appSettings.sleepingTabPreviews = checked
                                        Controls.ToolTip.text: "Show saved, blurred previews with a sleep icon. When disabled, opening the overview wakes tabs to show normal live previews; the tab limit resumes when the overview closes."
                                        Controls.ToolTip.visible: hovered
                                    }
                                }

                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: "The maximum tab count takes priority over the minimum loaded tabs."
                                    opacity: 0.72
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                        Controls.Frame {
                            Layout.fillWidth: true
                            visible: settingsWindow.selectedSection === 3
                            padding: 0
                            background: Item { }
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.largeSpacing
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
                        Controls.Frame {
                            Layout.fillWidth: true
                            visible: settingsWindow.selectedSection === 2
                            padding: 0
                            background: Item { }
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.FormLayout {
                                    Layout.fillWidth: true
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
                                        Controls.ToolTip.text: "Limit sleeping-preview effects to 640 × 480 pixels. Turn off for full display resolution during animations."
                                        Controls.ToolTip.visible: hovered
                                    }

                                    RowLayout {
                                        Kirigami.FormData.label: "Overview preview quality:"
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: Math.max(200, sectionScroll.availableWidth - 210)
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

                                    Controls.CheckBox {
                                        Kirigami.FormData.label: "Menus:"
                                        text: "Integrate Figma menus with Plasma"
                                        checked: appSettings.menuIntegration
                                        onToggled: appSettings.menuIntegration = checked
                                        Controls.ToolTip.text: "Export Figma actions to the global menu. Changes apply immediately."
                                        Controls.ToolTip.visible: hovered
                                    }

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
                                }

                                Controls.Label {
                                    Layout.fillWidth: true
                                    text: "UI memory options apply immediately. Extra switches override the Chromium toggles. Restart ReSketch to apply Chromium changes."
                                    opacity: 0.72
                                    wrapMode: Text.WordWrap
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
