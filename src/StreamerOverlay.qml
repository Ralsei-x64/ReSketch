// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects

Item {
    id: overlay
    required property var targetWindow
    property bool preview: false
    property bool detached: false
    readonly property int entryCount: entries.count
    readonly property var style: appSettings.streamer.style
    readonly property bool horizontal: appSettings.streamer.spawnDirection >= 2
    readonly property real keyGap: 5
    readonly property real windowMarginX: detached ? style.marginX : 0
    readonly property real windowMarginY: detached ? style.marginY : 0
    readonly property real tileHeight: Math.max(style.minHeight, Math.ceil(keyFont.height) + style.paddingTop + style.paddingBottom)
    readonly property var keyWidths: {
        const widths = []
        for (let i = 0; i < entries.count; ++i)
            widths.push(Math.min(Math.max(0, availableWidth), Math.max(24, style.minWidth, Math.ceil(keyFont.advanceWidth(entries.get(i).label)) + style.paddingLeft + style.paddingRight)))
        return widths
    }
    readonly property real availableWidth: Math.max(0, queue.parent.width - windowMarginX * 2)
    readonly property real availableHeight: Math.max(0, queue.parent.height - windowMarginY * 2)
    readonly property real naturalWidth: !entries.count ? 0 : horizontal
        ? keyWidths.reduce((sum, width) => sum + width, 0) + Math.max(0, entries.count - 1) * keyGap
        : Math.max(...keyWidths)
    readonly property real naturalHeight: !entries.count ? 0 : horizontal ? tileHeight
        : entries.count * tileHeight + Math.max(0, entries.count - 1) * keyGap
    property var backdropSource: targetWindow ? targetWindow.streamerBackdrop ?? targetWindow.browserContent ?? null : null
    visible: preview || appSettings.streamer.enabled

    function alignedPosition(space, anchor, offset) {
        if (anchor === 2) return Math.max(0, Math.min(space, space / 2 + offset))
        const gap = Math.max(0, Math.min(space, offset))
        return anchor === 1 ? space - gap : gap
    }

    FontMetrics {
        id: keyFont
        font.family: overlay.style.fontFamily
        font.pixelSize: overlay.style.fontSize
        font.weight: Font.DemiBold
    }

    ListModel { id: entries }
    function appendEntry(label, scrollCount, isScroll, scrollModifiers) {
        while (entries.count >= appSettings.streamer.maximumEntries) entries.remove(0)
        entries.append({label: label, born: Date.now(), lifetime: appSettings.streamer.durationMs,
                        scrollCount: scrollCount, isScroll: isScroll, scrollModifiers: scrollModifiers})
    }
    Connections {
        target: appSettings.streamer
        enabled: !overlay.preview
        function onChanged() {
            while (entries.count > appSettings.streamer.maximumEntries) entries.remove(0)
        }
        function onCleared() { entries.clear() }
        function onPressed(window, label, replace) {
            if (window !== overlay.targetWindow) return
            if (replace && entries.count) entries.setProperty(entries.count - 1, "label", label)
            else {
                // Keep the overlay compact during bursts; every entry retains
                // its own original deadline even when a modifier joins it.
                overlay.appendEntry(label, 0, false, "")
            }
        }
        function onScrolled(window, steps, modifiers, replaceModifier) {
            if (window !== overlay.targetWindow) return
            const last = entries.count ? entries.get(entries.count - 1) : null
            const valid = last && Date.now() - last.born < last.lifetime
            const sameScroll = valid && last.isScroll && last.scrollModifiers === modifiers
            const replace = sameScroll || valid && replaceModifier && !last.isScroll
            const total = steps + (sameScroll ? last.scrollCount : 0)
            const label = (modifiers ? modifiers + " + " : "")
                + qsTr("Scroll: %1").arg((total > 0 ? "+" : "") + total)
            if (replace) entries.set(entries.count - 1, {label: label, scrollCount: total,
                born: Date.now(), lifetime: appSettings.streamer.durationMs,
                isScroll: true, scrollModifiers: modifiers})
            else overlay.appendEntry(label, total, true, modifiers)
        }
    }
    Timer {
        interval: 16
        repeat: true
        running: !overlay.preview && entries.count > 0
        onTriggered: {
            const now = Date.now()
            overlay.now = now
            for (let i = entries.count - 1; i >= 0; --i) {
                const entry = entries.get(i)
                if (now - entry.born >= entry.lifetime) entries.remove(i)
            }
            if (overlay.detached && overlay.style.blur > 0) separateWindow.updateBlur()
        }
    }
    property double now: Date.now()
    Component.onCompleted: if (preview) appendEntry("Ctrl + K", 0, false, "")

    Component {
        id: keyQueue
        Item {
            Repeater {
                model: entries
                Item {
                    id: keyEntry
                    required property int index
                    required property string label
                    required property double born
                    required property int lifetime
                    objectName: "streamerKeyEntry"
                    readonly property real precedingWidth: overlay.keyWidths.slice(0, index).reduce((sum, width) => sum + width, 0)
                        + index * overlay.keyGap
                    width: overlay.keyWidths[index] ?? 0
                    height: overlay.tileHeight
                    x: overlay.horizontal ? appSettings.streamer.spawnDirection === 3
                        ? overlay.naturalWidth - precedingWidth - width
                        : precedingWidth - Math.max(0, overlay.naturalWidth - queue.width)
                        : (overlay.style.sticky
                            ? overlay.alignedPosition(Math.max(0, queue.width - width), overlay.style.horizontalAnchor, 0) : 0)
                    y: (overlay.horizontal ? 0 : appSettings.streamer.spawnDirection === 1
                        ? (entries.count - 1 - index) * (height + overlay.keyGap)
                        : index * (height + overlay.keyGap) - Math.max(0, overlay.naturalHeight - queue.height))
                    Behavior on x {
                        enabled: !appSettings.reduceMotion
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: !appSettings.reduceMotion
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    opacity: overlay.preview ? 1 : Math.max(0, Math.min(1, (lifetime - (overlay.now - born)) / 350))
                    transformOrigin: Item.Center
                    NumberAnimation on scale {
                        id: entryPop
                        from: 0.88
                        to: 1
                        duration: 240
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.1
                        running: false
                    }
                    Component.onCompleted: if (!appSettings.reduceMotion) entryPop.start()
                    ShaderEffectSource {
                        id: backdrop
                        anchors.fill: parent
                        visible: false
                        sourceItem: overlay.style.blur > 0 && !overlay.detached ? overlay.backdropSource : null
                        readonly property point sourcePosition: sourceItem
                            ? sourceItem.mapFromItem(queue.parent, queue.x + keyEntry.x, queue.y + keyEntry.y) : Qt.point(0, 0)
                        sourceRect: Qt.rect(sourcePosition.x, sourcePosition.y, width, height)
                        live: !!sourceItem
                        hideSource: false
                    }
                    Rectangle {
                        id: blurMask
                        anchors.fill: parent
                        radius: overlay.style.radius
                        color: "white"
                    }
                    // Capture the rounded mask explicitly so hidden layers cannot leave it empty.
                    ShaderEffectSource {
                        id: maskTexture
                        anchors.fill: parent
                        sourceItem: blurMask
                        hideSource: true
                        visible: false
                        live: !!backdrop.sourceItem
                    }
                    MultiEffect {
                        objectName: "streamerBackgroundBlur"
                        anchors.fill: parent
                        visible: !!backdrop.sourceItem
                        source: backdrop
                        blurEnabled: true
                        blur: overlay.style.blur / 32
                        blurMax: 32
                        autoPaddingEnabled: false
                        maskEnabled: true
                        maskSource: maskTexture
                    }
                    Rectangle {
                        id: keySurface
                        objectName: "streamerKeyBackground"
                        anchors.fill: parent
                        radius: overlay.style.radius
                        readonly property color tint: overlay.style.background
                        color: Qt.rgba(tint.r, tint.g, tint.b, 1 - overlay.style.transparency / 100)
                        border.color: "#40ffffff"
                        layer.enabled: overlay.style.shadow
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "black"
                            shadowOpacity: overlay.style.shadowStrength / 100
                            shadowBlur: 0.7
                            shadowVerticalOffset: 3
                        }
                    }
                    Controls.Label {
                        id: keyLabel
                        objectName: "streamerKeyLabel"
                        anchors.fill: parent
                        anchors.leftMargin: overlay.style.paddingLeft
                        anchors.rightMargin: overlay.style.paddingRight
                        anchors.topMargin: overlay.style.paddingTop
                        anchors.bottomMargin: overlay.style.paddingBottom
                        horizontalAlignment: overlay.style.alignment === 0 ? Text.AlignHCenter
                            : overlay.style.alignment === 2 || overlay.style.alignment === 4 ? Text.AlignRight : Text.AlignLeft
                        verticalAlignment: overlay.style.alignment === 0 ? Text.AlignVCenter
                            : overlay.style.alignment >= 3 ? Text.AlignBottom : Text.AlignTop
                        text: label
                        color: overlay.style.textColor
                        font.family: overlay.style.fontFamily
                        font.pixelSize: overlay.style.fontSize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    Loader {
        id: queue
        objectName: "streamerKeyQueue"
        parent: overlay.detached ? separateWindow.contentItem : overlay
        width: Math.min(overlay.naturalWidth, overlay.availableWidth)
        height: Math.min(overlay.naturalHeight, overlay.availableHeight)
        clip: overlay.naturalWidth > width || overlay.naturalHeight > height
        readonly property real freeWidth: Math.max(0, overlay.availableWidth - width)
        readonly property real freeHeight: Math.max(0, overlay.availableHeight - height)
        x: overlay.preview ? freeWidth / 2 : overlay.windowMarginX + (overlay.style.sticky
            ? overlay.alignedPosition(freeWidth, overlay.style.horizontalAnchor, overlay.style.offsetX)
            : overlay.detached ? 0 : freeWidth * appSettings.streamer.xPosition / 100)
        y: overlay.preview ? freeHeight / 2 : overlay.windowMarginY + (overlay.style.sticky
            ? overlay.alignedPosition(freeHeight, overlay.style.verticalAnchor, overlay.style.offsetY)
            : overlay.detached ? freeHeight : freeHeight * appSettings.streamer.yPosition / 100)
        Behavior on x {
            enabled: !appSettings.reduceMotion
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: !appSettings.reduceMotion
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        sourceComponent: keyQueue
    }
    Window {
        id: separateWindow
        objectName: "streamerOverlayWindow"
        title: qsTr("ReSketch — Streamer Overlay")
        transientParent: null
        width: 384
        height: 328
        minimumWidth: 200
        minimumHeight: 100
        color: "transparent"
        flags: Qt.Window | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
        visible: !overlay.preview && overlay.detached && appSettings.streamer.enabled && overlay.targetWindow.visible
        function updateBlur() {
            appSettings.setStreamerBlur(separateWindow, visible && overlay.entryCount > 0 && overlay.style.blur > 0,
                                        Qt.rect(queue.x, queue.y, queue.width, queue.height))
        }
        onWidthChanged: updateBlur()
        onHeightChanged: updateBlur()
        onVisibleChanged: updateBlur()
        Connections {
            target: appSettings.streamer
            function onChanged() { separateWindow.updateBlur() }
        }
        onClosing: overlay.detached = false
    }
}
