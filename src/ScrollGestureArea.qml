// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
import QtQuick

// Share wheel easing and touchpad momentum across the app's Flickables.
MouseArea {
    id: area
    objectName: "scrollGestureArea"
    parent: flickable
    anchors.fill: parent
    z: 100
    acceptedButtons: Qt.NoButton
    required property var flickable
    property var nestedFlickables: []
    property var scrollTarget: null
    readonly property var view: scrollTarget || flickable
    property real wheelStep: 120
    property bool horizontal: false
    readonly property bool smoothEnabled: appSettings.smoothScrolling && !appSettings.reduceMotion
    readonly property bool inertiaEnabled: appSettings.inertialScrolling && !appSettings.reduceMotion
    property int gestureAxis: 0
    property real velocity: 0
    property int samples: 0
    property double updatedAt: 0
    property bool platformMomentum: false
    property bool gestureEnded: false
    enabled: !!flickable && flickable.interactive && (horizontal
        ? flickable.contentWidth > flickable.width : flickable.contentHeight > flickable.height)
    onSmoothEnabledChanged: stop()
    onInertiaEnabledChanged: stop()
    onEnabledChanged: if (!enabled) stop()
    onVisibleChanged: if (!visible) stop()

    function stop() {
        releaseTimer.stop()
        easing.stop()
        velocity = 0
        samples = 0
        updatedAt = 0
        platformMomentum = false
        gestureEnded = false
        gestureAxis = 0
        if (!view) return
        view.cancelFlick()
        if (typeof view.scrollBy === "function") view.scrollBy(0, true)
    }
    function scrollBy(distance, direct) {
        if (typeof view.scrollBy === "function") {
            view.scrollBy(distance, direct)
            return
        }
        const origin = (horizontal ? view.originX : view.originY) || 0
        const limit = origin + Math.max(0, horizontal ? view.contentWidth - view.width
                                                     : view.contentHeight - view.height)
        const current = horizontal ? view.contentX : view.contentY
        const next = Math.max(origin, Math.min(limit, (!direct && easing.running ? easing.to : current) - distance))
        if (direct || !smoothEnabled) {
            easing.stop()
            if (horizontal) view.contentX = next
            else view.contentY = next
        } else {
            easing.to = next
            easing.start()
        }
    }
    SmoothedAnimation {
        id: easing
        target: area.view
        property: area.horizontal ? "contentX" : "contentY"
        velocity: -1
        duration: 200
        maximumEasingTime: 120
        reversingMode: SmoothedAnimation.Immediate
    }
    Timer {
        id: releaseTimer
        interval: 40
        onTriggered: {
            if (area.inertiaEnabled && !area.platformMomentum && area.samples >= 2
                && Date.now() - area.updatedAt < 120 && Math.abs(area.velocity) >= 80) {
                if (area.horizontal) area.view.flick(area.velocity, 0)
                else area.view.flick(0, area.velocity)
            }
            area.samples = 0
            area.gestureAxis = 0
        }
    }
    Connections {
        target: area.view
        function onDraggingChanged() { if (area.view.dragging) area.stop() }
    }
    onWheel: event => {
        const target = nestedFlickables.find(item => item && item.visible
            && item.contentHeight > item.height && item.contains(item.mapFromItem(area, event.x, event.y))) || flickable
        if (target !== view) { stop(); scrollTarget = target }
        const pixels = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
        const continuous = pixels || event.phase !== Qt.NoScrollPhase
                           || event.device.type === PointerDevice.TouchPad
        const now = Date.now()
        if (event.phase === Qt.ScrollBegin || gestureEnded && event.phase !== Qt.ScrollMomentum
            || continuous && now - updatedAt > 150
            && event.phase !== Qt.ScrollEnd && event.phase !== Qt.ScrollMomentum) stop()
        if (event.phase === Qt.ScrollMomentum) {
            releaseTimer.stop()
            platformMomentum = true
            if (!inertiaEnabled) { event.accepted = true; return }
        }
        const delta = pixels ? event.pixelDelta : event.angleDelta
        let axis = horizontal && Math.abs(delta.x) > Math.abs(delta.y) ? 1 : 2
        if (continuous && (delta.x !== 0 || delta.y !== 0)) {
            if (!gestureAxis) gestureAxis = axis
            axis = gestureAxis
        }
        const distance = (axis === 1 ? delta.x : delta.y) * (pixels ? 1 : wheelStep / 120)
                         * (event.modifiers & Qt.ControlModifier ? 1 : appSettings.mouseScrollSensitivity / 100)
        if (distance || continuous && event.phase === Qt.ScrollBegin) {
            view.cancelFlick()
            if (continuous) easing.stop()
            scrollBy(distance, continuous)
        }
        if (continuous && distance && event.phase !== Qt.ScrollMomentum) {
            releaseTimer.stop()
            const elapsed = now - updatedAt
            if (samples && elapsed <= 120) {
                if (velocity * distance < 0) velocity = 0
                velocity = Math.max(-5000, Math.min(5000, velocity * 0.5 + distance * 500 / Math.max(8, elapsed)))
            }
            updatedAt = now
            ++samples
            if (event.phase === Qt.NoScrollPhase) releaseTimer.restart()
        }
        if (event.phase === Qt.ScrollEnd) {
            gestureEnded = true
            gestureAxis = 0
            if (!platformMomentum) releaseTimer.restart()
            else { samples = 0; gestureAxis = 0 }
        }
        event.accepted = true
    }
}
