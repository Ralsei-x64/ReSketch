// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
(() => {
    if (location.protocol !== 'https:' || !/(^|\.)figma\.com$/.test(location.hostname)) return;
    let dragging = false, candidate = null;
    const stop = () => {
        candidate = null;
        if (!dragging) return;
        dragging = false;
        __resketchNative('numeric-scrub', 'stop');
    };
    document.addEventListener('pointerdown', event => {
        if (!event.isTrusted || event.button !== 0 || event.isPrimary === false
            || event.pointerType && event.pointerType !== 'mouse') return;
        if (!(event.target instanceof Element)
            || !/(?:^|,\s*)(?:ew-resize|col-resize)$/.test(getComputedStyle(event.target).cursor)) return;
        let numeric = false;
        // Stay within the field's small wrapper; sidebar resize handles must not capture.
        for (let node = event.target, depth = 0; node instanceof Element && depth < 4; node = node.parentElement, ++depth) {
            const input = node.matches('input') ? node : node.querySelector('input');
            numeric ||= !!input && (input.type === 'number' || /^(numeric|decimal)$/.test(input.inputMode)
                || /^[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:%|px|°)?$/.test(input.value.trim()));
        }
        if (numeric) candidate = {id:event.pointerId, x:event.clientX, y:event.clientY};
    }, true);
    document.addEventListener('pointermove', event => {
        if (!candidate || !event.isTrusted || event.pointerId !== candidate.id || !(event.buttons & 1)
            || Math.hypot(event.clientX - candidate.x, event.clientY - candidate.y) < 3) return;
        candidate = null;
        dragging = true;
        // Let Figma install its own pointer capture before the native cursor is held.
        queueMicrotask(() => { if (dragging) __resketchNative('numeric-scrub', 'start'); });
    }, true);
    document.addEventListener('pointerup', stop, true);
    document.addEventListener('pointercancel', stop, true);
    document.addEventListener('keydown', event => { if (event.key === 'Escape') stop(); }, true);
    window.addEventListener('blur', stop);
    document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
})()
