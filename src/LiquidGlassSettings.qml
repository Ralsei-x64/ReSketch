// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

SettingsGroup {
    id: glass
    title: qsTr("Canvas liquid glass")
    readonly property var style: appSettings.sidebarLiquidGlass
    function setStyle(key, value) {
        const updated = Object.assign({}, style)
        updated[key] = value
        appSettings.sidebarLiquidGlass = updated
    }

    component GlassNumber: RowLayout {
        required property string title
        required property string field
        property int minimum: 0
        property int maximum: 100
        property bool blurControl: false
        readonly property int settingValue: blurControl ? appSettings.sidebarCanvasBlur : glass.style[field]
        function save(newValue) {
            if (blurControl) appSettings.sidebarCanvasBlur = newValue
            else glass.setStyle(field, newValue)
        }
        Layout.fillWidth: true
        spacing: 10
        enabled: blurControl || glass.style.enabled
        Controls.Label { text: title; Layout.preferredWidth: 180; wrapMode: Text.WordWrap }
        Controls.Slider {
            objectName: blurControl ? "sidebarCanvasBlurControl" : "liquidGlassSlider-" + field
            Layout.fillWidth: true
            from: minimum; to: maximum; stepSize: 1
            value: settingValue
            onMoved: save(Math.round(value))
            Accessible.name: title
        }
        Controls.SpinBox {
            objectName: "liquidGlass-" + field
            Layout.preferredWidth: 132
            from: minimum; to: maximum; editable: true
            value: settingValue
            onValueModified: {
                save(value)
                value = Qt.binding(() => settingValue)
            }
            Accessible.name: title
        }
    }

    Controls.CheckBox {
        objectName: "liquidGlassToggle"
        text: qsTr("Enable liquid glass on sidebars and toolbox")
        checked: glass.style.enabled
        onToggled: glass.setStyle("enabled", checked)
    }
    Controls.Label {
        Layout.fillWidth: true
        text: qsTr("Uses the Figma canvas behind the panels. Lower Canvas backdrop opacity to reveal the effect. Corner radius applies only to floating sidebars. Changes apply immediately to all tabs.")
        opacity: 0.72
        wrapMode: Text.WordWrap
    }
    GlassNumber { title: qsTr("Blur strength (px)"); field: "blurStrength"; maximum: 40; blurControl: true }
    GlassNumber { title: qsTr("Noise strength (%)"); field: "noiseStrength" }
    GlassNumber { title: qsTr("Brightness (%)"); field: "brightness"; maximum: 200 }
    GlassNumber { title: qsTr("Saturation (%)"); field: "saturation"; maximum: 300 }
    GlassNumber { title: qsTr("Contrast (%)"); field: "contrast"; maximum: 200 }
    GlassNumber {
        title: qsTr("Corner radius (px)"); field: "cornerRadius"; maximum: 80
        enabled: glass.style.enabled && appSettings.floatingSidebars
    }
    GlassNumber { title: qsTr("Refraction strength (px)"); field: "refractionStrength" }
    RowLayout {
        Layout.fillWidth: true
        enabled: glass.style.enabled
        Controls.Label { text: qsTr("Refraction mode"); Layout.preferredWidth: 180 }
        Controls.ComboBox {
            objectName: "liquidGlass-refractionMode"
            Layout.fillWidth: true
            model: [qsTr("Basic"), qsTr("Concave")]
            currentIndex: glass.style.refractionMode === "concave" ? 1 : 0
            onActivated: glass.setStyle("refractionMode", currentIndex === 1 ? "concave" : "basic")
            Accessible.name: qsTr("Refraction mode")
        }
    }
    GlassNumber { title: qsTr("Refraction edge size (px)"); field: "refractionEdgeSize"; minimum: 1; maximum: 200 }
    GlassNumber { title: qsTr("Refraction falloff (%)"); field: "refractionFalloff"; minimum: 1; maximum: 400 }
    GlassNumber { title: qsTr("Refraction corner radius (px)"); field: "refractionCornerRadius"; maximum: 200 }
    GlassNumber { title: qsTr("RGB fringing strength (px)"); field: "rgbFringingStrength"; maximum: 20 }

    Kirigami.Heading { text: qsTr("Inner shadow"); level: 4 }
    Controls.Label {
        Layout.fillWidth: true
        text: qsTr("Position moves the shadow horizontally and vertically. Scale controls its size and softness; strength 0% turns it off.")
        opacity: 0.72
        wrapMode: Text.WordWrap
    }
    GlassNumber { title: qsTr("Position X (px)"); field: "innerShadowX"; minimum: -100 }
    GlassNumber { title: qsTr("Position Y (px)"); field: "innerShadowY"; minimum: -100 }
    GlassNumber { title: qsTr("Scale (px)"); field: "innerShadowScale" }
    GlassNumber { title: qsTr("Brightness (%)"); field: "innerShadowBrightness"; maximum: 200 }
    GlassNumber { title: qsTr("Strength (%)"); field: "innerShadowStrength" }
    RowLayout {
        Layout.fillWidth: true
        enabled: glass.style.enabled
        Controls.Label { text: qsTr("Color"); Layout.preferredWidth: 180 }
        Rectangle {
            width: 28; height: 28; radius: 5
            color: glass.style.innerShadowColor
            border.color: Kirigami.Theme.textColor
        }
        Controls.Button {
            objectName: "liquidGlass-innerShadowColor"
            text: qsTr("Choose…")
            Accessible.name: qsTr("Inner shadow color")
            onClicked: glass.setStyle("innerShadowColor", appSettings.chooseColor(glass.style.innerShadowColor,
                glass.Window.window, qsTr("Inner shadow color")))
        }
    }
}
