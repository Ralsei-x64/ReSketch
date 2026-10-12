// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

function script(allowed) {
    return `(() => {
        if (window.__resketchSetNotifications) {
            window.__resketchSetNotifications(${!!allowed});
            return;
        }
        const NativeNotification = window.Notification;
        if (!NativeNotification) return;
        let enabled = ${!!allowed};
        window.__resketchSetNotifications = value => enabled = value;
        function Notification(title, options) {
            if (!enabled) throw new DOMException('Notifications are handled by ReSketch Home.', 'NotAllowedError');
            return new NativeNotification(title, options);
        }
        Notification.prototype = NativeNotification.prototype;
        Object.setPrototypeOf(Notification, NativeNotification);
        Object.defineProperty(Notification, 'permission', {get: () => enabled ? NativeNotification.permission : 'denied'});
        Notification.requestPermission = callback => {
            if (enabled) return NativeNotification.requestPermission(callback);
            if (callback) callback('denied');
            return Promise.resolve('denied');
        };
        window.Notification = Notification;
    })()`;
}
