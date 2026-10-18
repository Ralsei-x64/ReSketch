// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: settings
    property var overlay: null
    readonly property var style: appSettings.streamer.style
    readonly property bool detached: !!overlay && overlay.detached
    function setStyle(key, value) {
        const updated = Object.assign({}, appSettings.streamer.style)
        updated[key] = value
        appSettings.streamer.style = updated
    }
    spacing: Kirigami.Units.largeSpacing

    component ValueField: Controls.SpinBox {
        property int settingValue
        signal edited(int newValue)
        Layout.preferredWidth: 100
        editable: true
        value: settingValue
        onValueModified: {
            edited(value)
            // The desktop style assigns value while typing, removing its binding.
            value = Qt.binding(() => settingValue)
        }
    }
    component StyleNumber: RowLayout {
        required property string title
        required property string field
        property int maximum: 100
        property int minimum: 0
        objectName: "streamerStyleRow-" + field
        Layout.fillWidth: true
        spacing: 10
        Controls.Label { text: title; Layout.preferredWidth: 140; wrapMode: Text.WordWrap }
        Controls.Slider {
            objectName: "streamerStyleSlider-" + field
            Layout.fillWidth: true
            from: minimum; to: maximum
            value: settings.style[field]
            onMoved: settings.setStyle(field, Math.round(value))
            Accessible.name: title
        }
        ValueField {
            objectName: "streamerStyle-" + field
            Layout.preferredWidth: 100
            from: minimum; to: maximum; editable: true
            settingValue: settings.style[field]
            onEdited: newValue => settings.setStyle(field, newValue)
            Accessible.name: title
        }
    }
    component StyleColor: RowLayout {
        required property string title
        required property string field
        Layout.fillWidth: true
        Controls.Label { text: title; Layout.fillWidth: true }
        Rectangle { width: 28; height: 28; radius: 5; color: settings.style[field]; border.color: "#808080" }
        Controls.Button {
            objectName: "streamerStyle-" + field
            text: qsTr("Choose…")
            Accessible.name: title
            onClicked: settings.setStyle(field, appSettings.chooseColor(settings.style[field], settings.Window.window, title))
        }
    }

    Controls.Button {
        objectName: "streamerModeToggle"
        text: checked ? qsTr("Streamer mode on") : qsTr("Enable streamer mode")
        icon.name: "preferences-desktop-keyboard"
        checkable: true
        checked: appSettings.streamer.enabled
        onClicked: appSettings.streamer.enabled = checked
        Accessible.description: qsTr("Show keyboard and mouse presses from this ReSketch window.")
    }
    Controls.Label {
        Layout.fillWidth: true
        text: qsTr("Show key combinations, mouse presses and a scroll counter in a small, click-through overlay. Only input inside each ReSketch main window is shown.")
        wrapMode: Text.WordWrap
    }
    Controls.Button {
        objectName: "streamerDetachButton"
        text: settings.detached ? qsTr("Move overlay back into this window") : qsTr("Move overlay to a separate window")
        icon.name: "window-new"
        enabled: appSettings.streamer.enabled && !!settings.overlay
        onClicked: settings.overlay.detached = !settings.overlay.detached
    }

    SettingsGroup {
        title: qsTr("Display")
        Controls.Label { text: qsTr("Keypress duration") }
        RowLayout {
            Layout.fillWidth: true
            Controls.Slider {
                objectName: "streamerDurationSlider"
                Layout.fillWidth: true
                from: 500; to: 10000
                value: appSettings.streamer.durationMs
                onMoved: appSettings.streamer.durationMs = Math.round(value / 100) * 100
                Accessible.name: qsTr("Keypress display duration, milliseconds")
            }
            Controls.Label {
                Layout.preferredWidth: 72
                text: qsTr("%1 s").arg((appSettings.streamer.durationMs / 1000).toFixed(1))
                horizontalAlignment: Text.AlignRight
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Keys fade after the selected duration. Scroll counters fade after scrolling stops.")
            wrapMode: Text.WordWrap
        }
        Controls.Label { text: qsTr("Maximum keys shown") }
        RowLayout {
            Layout.fillWidth: true
            Controls.Slider {
                objectName: "streamerMaximumEntriesSlider"
                Layout.fillWidth: true
                from: 1; to: 32
                value: appSettings.streamer.maximumEntries
                onMoved: appSettings.streamer.maximumEntries = Math.round(value)
                Accessible.name: qsTr("Maximum keys shown")
            }
            ValueField {
                objectName: "streamerMaximumEntriesValue"
                Layout.preferredWidth: 100
                from: 1; to: 32; editable: true
                settingValue: appSettings.streamer.maximumEntries
                onEdited: newValue => appSettings.streamer.maximumEntries = newValue
                Accessible.name: qsTr("Maximum keys shown")
            }
        }
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Combinations and scroll counters each count as one entry. The oldest entries disappear when the limit is reached.")
            wrapMode: Text.WordWrap
        }
        Controls.Label { text: qsTr("Spawn direction") }
        Controls.ComboBox {
            objectName: "streamerSpawnDirection"
            Layout.fillWidth: true
            model: [qsTr("Toward the bottom"), qsTr("Toward the top"), qsTr("Left to right"), qsTr("Right to left")]
            currentIndex: appSettings.streamer.spawnDirection
            onActivated: appSettings.streamer.spawnDirection = currentIndex
            Accessible.name: qsTr("Keypress spawn direction")
        }
    }

    SettingsGroup {
        title: qsTr("Separate window")
        StyleNumber { title: qsTr("Default width (px)"); field: "windowWidth"; minimum: 200; maximum: 3840 }
        StyleNumber { title: qsTr("Default height (px)"); field: "windowHeight"; minimum: 100; maximum: 2160 }
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Used when opening the separate overlay. Changing these values also resizes it while open.")
            wrapMode: Text.WordWrap
        }
        Controls.Label { visible: settings.detached; text: qsTr("Window margins"); font.bold: true }
        StyleNumber { visible: settings.detached; title: qsTr("Horizontal (px)"); field: "marginX" }
        StyleNumber { visible: settings.detached; title: qsTr("Vertical (px)"); field: "marginY" }
    }

    SettingsGroup {
        title: qsTr("Position")
        Controls.CheckBox {
            objectName: "streamerStickyPosition"
            text: qsTr("Stick to window edges or center")
            checked: settings.style.sticky
            onToggled: settings.setStyle("sticky", checked)
        }
        GridLayout {
            visible: settings.style.sticky
            Layout.fillWidth: true
            columns: 2
            Controls.Label { text: qsTr("Horizontal") }
            Controls.ComboBox {
                objectName: "streamerHorizontalAnchor"
                Layout.fillWidth: true
                model: [qsTr("Left"), qsTr("Right"), qsTr("Center")]
                currentIndex: settings.style.horizontalAnchor
                onActivated: settings.setStyle("horizontalAnchor", currentIndex)
                Accessible.name: qsTr("Sticky horizontal alignment")
            }
            Controls.Label { text: qsTr("Vertical") }
            Controls.ComboBox {
                objectName: "streamerVerticalAnchor"
                Layout.fillWidth: true
                model: [qsTr("Top"), qsTr("Bottom"), qsTr("Center")]
                currentIndex: settings.style.verticalAnchor
                onActivated: settings.setStyle("verticalAnchor", currentIndex)
                Accessible.name: qsTr("Sticky vertical alignment")
            }
        }
        StyleNumber {
            visible: settings.style.sticky
            title: qsTr("X offset (px)"); field: "offsetX"
            minimum: settings.style.horizontalAnchor === 2 ? -2000 : 0
            maximum: 2000
        }
        StyleNumber {
            visible: settings.style.sticky
            title: qsTr("Y offset (px)"); field: "offsetY"
            minimum: settings.style.verticalAnchor === 2 ? -2000 : 0
            maximum: 2000
        }
        Controls.Label {
            Layout.fillWidth: true
            text: settings.style.sticky
                ? qsTr("Offsets stay fixed when resizing. Center offsets can be negative to move left or up, or positive to move right or down.")
                : qsTr("Use X and Y to position the overlay. 0% is left/top; 100% is right/bottom.")
            wrapMode: Text.WordWrap
        }
        GridLayout {
            visible: !settings.style.sticky
            Layout.fillWidth: true
            columns: 3
            Controls.Label { text: qsTr("X (%)") }
            Controls.Slider {
                objectName: "streamerXSlider"
                Layout.fillWidth: true
                from: 0; to: 100
                value: appSettings.streamer.xPosition
                onMoved: appSettings.streamer.xPosition = Math.round(value)
                Accessible.name: qsTr("Overlay horizontal position")
            }
            ValueField {
                objectName: "streamerXPosition"
                Layout.preferredWidth: 100
                from: 0; to: 100; editable: true
                settingValue: appSettings.streamer.xPosition
                onEdited: newValue => appSettings.streamer.xPosition = newValue
                Accessible.name: qsTr("Overlay X position, percent")
            }
            Controls.Label { text: qsTr("Y (%)") }
            Controls.Slider {
                objectName: "streamerYSlider"
                Layout.fillWidth: true
                from: 0; to: 100
                value: appSettings.streamer.yPosition
                onMoved: appSettings.streamer.yPosition = Math.round(value)
                Accessible.name: qsTr("Overlay vertical position")
            }
            ValueField {
                objectName: "streamerYPosition"
                Layout.preferredWidth: 100
                from: 0; to: 100; editable: true
                settingValue: appSettings.streamer.yPosition
                onEdited: newValue => appSettings.streamer.yPosition = newValue
                Accessible.name: qsTr("Overlay Y position, percent")
            }
        }
    }

    SettingsGroup {
        title: qsTr("Key padding")
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Space inside each key, between the text and each edge.")
            wrapMode: Text.WordWrap
        }
        StyleNumber { title: qsTr("Top (px)"); field: "paddingTop" }
        StyleNumber { title: qsTr("Right (px)"); field: "paddingRight" }
        StyleNumber { title: qsTr("Bottom (px)"); field: "paddingBottom" }
        StyleNumber { title: qsTr("Left (px)"); field: "paddingLeft" }
    }
    SettingsGroup {
        title: qsTr("Key size")
        StyleNumber { title: qsTr("Minimum width (px)"); field: "minWidth"; maximum: 400 }
        StyleNumber { title: qsTr("Minimum height (px)"); field: "minHeight"; maximum: 200 }
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Use minimum key dimensions to give text alignment more room.")
            wrapMode: Text.WordWrap
        }
    }
    SettingsGroup {
        title: qsTr("Text")
        Controls.Label { text: qsTr("Alignment") }
        Controls.ComboBox {
            objectName: "streamerTextAlignment"
            Layout.fillWidth: true
            model: [qsTr("Center"), qsTr("Top left"), qsTr("Top right"), qsTr("Bottom left"), qsTr("Bottom right")]
            currentIndex: settings.style.alignment
            onActivated: settings.setStyle("alignment", currentIndex)
            Accessible.name: qsTr("Key text alignment")
        }
        Controls.Label { text: qsTr("Font") }
        Controls.ComboBox {
            objectName: "streamerTextFont"
            Layout.fillWidth: true
            editable: true
            model: Qt.fontFamilies()
            currentIndex: Math.max(0, model.indexOf(settings.style.fontFamily))
            onActivated: settings.setStyle("fontFamily", currentText)
            onAccepted: settings.setStyle("fontFamily", editText)
            Accessible.name: qsTr("Key text font")
        }
        StyleNumber { title: qsTr("Text size (px)"); field: "fontSize"; minimum: 8; maximum: 96 }
        StyleColor { title: qsTr("Text color"); field: "textColor" }
    }
    SettingsGroup {
        title: qsTr("Appearance")
        StyleColor { title: qsTr("Background color"); field: "background" }
        StyleNumber { title: qsTr("Corner radius (px)"); field: "radius" }
        StyleNumber { title: qsTr("Transparency (%)"); field: "transparency" }
        StyleNumber { title: qsTr("Background blur"); field: "blur"; maximum: 32 }
        Controls.Label {
            Layout.fillWidth: true
            text: qsTr("Blur softens the content behind the keys. Desktop blur in the separate window depends on your compositor.")
            wrapMode: Text.WordWrap
        }
        Controls.CheckBox {
            objectName: "streamerShadow"
            text: qsTr("Key shadow")
            checked: settings.style.shadow
            onToggled: settings.setStyle("shadow", checked)
        }
        StyleNumber { visible: settings.style.shadow; title: qsTr("Shadow strength (%)"); field: "shadowStrength" }
    }
}
