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
        // File tabs share Home's origin and permission, but must not register
        // push subscriptions or display foreground worker notifications themselves.
        const worker = window.ServiceWorkerRegistration?.prototype;
        if (worker) {
            const show = worker.showNotification;
            worker.showNotification = function(...args) {
                return enabled ? show.apply(this, args)
                               : Promise.reject(new DOMException('Notifications are handled by ReSketch Home.', 'NotAllowedError'));
            };
        }
        const push = window.PushManager?.prototype;
        if (push) {
            const subscribe = push.subscribe;
            push.subscribe = function(...args) {
                return enabled ? subscribe.apply(this, args)
                               : Promise.reject(new DOMException('Notifications are handled by ReSketch Home.', 'NotAllowedError'));
            };
        }
    })()`;
}
