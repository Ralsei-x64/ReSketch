// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: settingsWindow
    objectName: "settingsWindow"
    onClosing: {
        cssSaveTimer.stop()
        appSettings.figmaCustomCss = customCssEditor.text
    }
    readonly property int chromeHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property bool framelessControls: !appSettings.safeMode && appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    readonly property color cardBorder: Qt.rgba(Kirigami.Theme.textColor.r,
                                                 Kirigami.Theme.textColor.g,
                                                 Kirigami.Theme.textColor.b, 0.16)
    width: 640
    height: 680
    minimumWidth: 480
    minimumHeight: 420
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: appSettings.safeMode ? "ReSketch — Safe Mode Settings" : "ReSketch — Settings"
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: "Settings"
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

        ColumnLayout {
            width: Math.max(1, settingsWindow.width - 48)
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Kirigami.Heading {
                    text: "Settings"
                    level: 1
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: "Choose how ReSketch looks and uses system resources."
                    opacity: 0.72
                    wrapMode: Text.WordWrap
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: appSettings.safeMode
                text: "Safe mode: GPU acceleration and the Figma interface are disabled. These controls edit your saved settings. Close this window and restart normally to apply them."
                type: Kirigami.MessageType.Information
            }

            Controls.Frame {
                Layout.fillWidth: true
                padding: Kirigami.Units.largeSpacing
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing * 1.5
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: settingsWindow.cardBorder
                }
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "preferences-desktop-theme"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        Kirigami.Heading { text: "Appearance"; level: 3 }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Kirigami.FormLayout {
                        Layout.fillWidth: true

                        Controls.ComboBox {
                            Kirigami.FormData.label: "App theme:"
                            model: ["Auto", "Light", "Dark"]
                            currentIndex: Math.max(0, ["auto", "light", "dark"].indexOf(appSettings.theme))
                            onActivated: appSettings.theme = ["auto", "light", "dark"][currentIndex]
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Motion:"
                            text: "Reduce motion"
                            checked: appSettings.reduceMotion
                            onToggled: appSettings.reduceMotion = checked
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Figma colors:"
                            text: "Use KDE colors (experimental)"
                            checked: appSettings.figmaSystemColors
                            onToggled: appSettings.figmaSystemColors = checked
                        }

                        Controls.Switch {
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
                            text: "Figma appearance changes apply immediately to all tabs. Custom CSS overrides KDE colors."
                            opacity: 0.72
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Kirigami.FormData.label: "Background opacity:"
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

                        Controls.Switch {
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
                            text: "Background opacity controls the toolbar and enabled sidebars. Canvas uses the canvas background where Figma's canvas does not extend behind the sidebars."
                            opacity: 0.72
                            wrapMode: Text.WordWrap
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Background blur:"
                            text: "Ignore blur"
                            checked: appSettings.ignoreToolbarBlur
                            onToggled: appSettings.ignoreToolbarBlur = checked
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Window controls:"
                            text: "Show in tab bar"
                            checked: appSettings.windowControlsInTabBar
                            onToggled: appSettings.windowControlsInTabBar = checked
                        }

                        Controls.Switch {
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
                padding: Kirigami.Units.largeSpacing
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing * 1.5
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: settingsWindow.cardBorder
                }
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "tab-duplicate"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        Kirigami.Heading { text: "Tabs"; level: 3 }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Kirigami.FormLayout {
                        Layout.fillWidth: true

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
                            Controls.ToolTip.text: "Restore file tabs on startup. Empty tabs, Home, and the new-file screen are not saved."
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.CheckBox {
                            text: "Keep Home running"
                            checked: appSettings.keepHomeAwake
                            onToggled: appSettings.keepHomeAwake = checked
                            Controls.ToolTip.text: "Keep Home awake regardless of the sleep timer or loaded-tab limit. Turn off to let Home sleep like other tabs."
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
                padding: Kirigami.Units.largeSpacing
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing * 1.5
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: settingsWindow.cardBorder
                }
                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: "preferences-system-performance"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        Kirigami.Heading { text: "Performance"; level: 3 }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    Kirigami.FormLayout {
                        Layout.fillWidth: true

                        Controls.Switch {
                            Kirigami.FormData.label: "UI memory:"
                            text: "Release closed secondary windows"
                            checked: appSettings.releaseClosedWindows
                            onToggled: appSettings.releaseClosedWindows = checked
                            Controls.ToolTip.text: "Free Settings, About, and Export History after closing them. They are created again when opened; settings and window size are preserved."
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.Switch {
                            text: "Release effects for offscreen overview cards"
                            checked: appSettings.cullOffscreenOverviewEffects
                            onToggled: appSettings.cullOffscreenOverviewEffects = checked
                            Controls.ToolTip.text: "Allocate clipping and blur textures only for visible cards. Tabs continue running normally."
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.Switch {
                            text: "Use compact sleeping-preview textures"
                            checked: appSettings.compactPreviewTextures
                            onToggled: appSettings.compactPreviewTextures = checked
                            Controls.ToolTip.text: "Limit sleeping-preview effects to 640 × 480 pixels. Turn off for full display resolution during animations."
                            Controls.ToolTip.visible: hovered
                        }

                        RowLayout {
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

                        Controls.Switch {
                            Kirigami.FormData.label: "Menus:"
                            text: "Integrate Figma menus with Plasma"
                            checked: appSettings.menuIntegration
                            onToggled: appSettings.menuIntegration = checked
                            Controls.ToolTip.text: "Export Figma actions to the global menu. Changes apply immediately."
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Chromium:"
                            text: "GPU rasterization"
                            checked: appSettings.gpuRasterization
                            onToggled: appSettings.gpuRasterization = checked
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Raster tiles:"
                            text: "Zero-copy rendering"
                            checked: appSettings.zeroCopyRasterization
                            onToggled: appSettings.zeroCopyRasterization = checked
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Canvas:"
                            text: "Experimental canvas features"
                            checked: appSettings.experimentalCanvasFeatures
                            onToggled: appSettings.experimentalCanvasFeatures = checked
                            Controls.ToolTip.text: "--enable-experimental-canvas-features"
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.Switch {
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

            Kirigami.Separator { Layout.fillWidth: true }

            Controls.Label {
                Layout.fillWidth: true
                text: "Restore default preferences. Sign-in data, export history, and remembered export folders are kept. Restart to apply Chromium changes."
                wrapMode: Text.WordWrap
                opacity: 0.72
            }
            Controls.Button {
                objectName: "resetSettingsButton"
                text: "Reset Settings"
                icon.name: "edit-undo"
                onClicked: {
                    cssSaveTimer.stop()
                    appSettings.resetSettings()
                    customCssEditor.text = Qt.binding(() => appSettings.figmaCustomCss)
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
