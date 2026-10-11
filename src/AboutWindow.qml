import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: aboutWindow
    readonly property int chromeHeight: Math.max(40, Math.round(Kirigami.Units.gridUnit * 2.25))
    readonly property bool framelessControls: appSettings.windowControlsInTabBar && !appSettings.keepWindowDecorations

    width: 440
    height: 340
    minimumWidth: 360
    minimumHeight: 300
    flags: framelessControls ? Qt.Window | Qt.FramelessWindowHint
                             : Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    title: qsTr("About ReSketch")
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    pageStack.initialPage: Kirigami.Page {
        globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

        header: Rectangle {
            height: aboutWindow.chromeHeight
            color: Kirigami.Theme.backgroundColor

            Row {
                anchors.fill: parent

                Item {
                    width: parent.width - aboutControls.width
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
                            source: "help-about"
                        }
                        Controls.Label {
                            text: qsTr("About")
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onPressed: aboutWindow.startSystemMove()
                    }
                }

                WindowControls {
                    id: aboutControls
                    targetWindow: aboutWindow
                    buttonSize: aboutWindow.chromeHeight
                    showMinimizeMaximize: false
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 112
                Layout.preferredHeight: 112
                source: "qrc:/Branding/SketchbookPNG/Folder-256.png"
                sourceSize.width: 256
                sourceSize.height: 256
                fillMode: Image.PreserveAspectFit
            }
            Kirigami.Heading {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("ReSketch")
                level: 1
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Open-source Figma client for Linux!")
            }
            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                text: qsTr("By Ralsei-x64")
                opacity: 0.75
            }
        }
    }

    WindowResizeHandles {
        parent: aboutWindow.contentItem
        anchors.fill: parent
        active: aboutWindow.framelessControls
        targetWindow: aboutWindow
    }
}
