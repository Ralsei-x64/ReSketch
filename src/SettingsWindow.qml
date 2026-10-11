import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: settingsWindow
    readonly property int chromeHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations
    readonly property color cardBorder: Qt.rgba(Kirigami.Theme.textColor.r,
                                                 Kirigami.Theme.textColor.g,
                                                 Kirigami.Theme.textColor.b, 0.16)
    width: 640
    height: 680
    minimumWidth: 480
    minimumHeight: 420
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: "ReSketch — Settings"
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

                    Controls.Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Settings"
                        font.pixelSize: Kirigami.Units.gridUnit
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

                        RowLayout {
                            Kirigami.FormData.label: "Toolbar opacity:"
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
                            Kirigami.FormData.label: "Toolbar blur:"
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
                        Kirigami.Heading { text: "Tabs and memory"; level: 3 }
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
                            Kirigami.FormData.label: "Sleep after (minutes):"
                            from: 1
                            to: 240
                            editable: true
                            value: appSettings.sleepMinutes
                            onValueModified: appSettings.sleepMinutes = value
                        }

                        Controls.SpinBox {
                            Kirigami.FormData.label: "Maximum memory (GB):"
                            from: 1
                            to: 64
                            editable: true
                            value: appSettings.maxMemoryGb
                            onValueModified: appSettings.maxMemoryGb = value
                        }
                    }

                    Controls.Label {
                        Layout.fillWidth: true
                        text: "The memory limit takes priority over the minimum loaded tabs."
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
                            Kirigami.FormData.label: "Menus:"
                            text: "Integrate Figma menus with Plasma"
                            checked: appSettings.menuIntegration
                            onToggled: appSettings.menuIntegration = checked
                            Controls.ToolTip.text: "Export Figma actions to the global menu. Changes apply immediately."
                            Controls.ToolTip.visible: hovered
                        }

                        Controls.Switch {
                            Kirigami.FormData.label: "Display:"
                            text: "High refresh interface animations"
                            checked: appSettings.highRefreshRate
                            onToggled: appSettings.highRefreshRate = checked
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
                        text: "Interface animations follow the display; web page animation depends on Qt WebEngine. Extra switches override the Chromium toggles. Restart ReSketch to apply performance changes."
                        opacity: 0.72
                        wrapMode: Text.WordWrap
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
