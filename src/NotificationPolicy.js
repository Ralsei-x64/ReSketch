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
        window.__resketchSetNotifications = value => {
            enabled = value;
            if (!enabled) window.__resketchHomeFeed = null;
        };
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

function feedScript(storeSource) {
    return `(() => {
        ${storeSource}
        const state = window.__resketchHomeFeed ||= {seen: null, queue: [], pending: false};
        if (state.pending) return JSON.stringify({pending: true});
        const user = menuStore()?.getState();
        if (!user?.user?.id) return JSON.stringify({pending: false});
        if (state.user !== user.user.id) {
            state.user = user.user.id;
            state.seen = null;
        }
        try {
            if (!state.api) {
                let require = window.__resketchHomeMenuRuntime;
                if (!require) window.rspackChunk_figma_web_bundler.push([
                    ['resketch-home-notifications'], {}, runtime => require = runtime
                ]);
                const id = Object.keys(require.m).find(id => {
                    const source = require.m[id].toString();
                    return source.includes('getServerDrivenPlan') && source.includes('/api/user_notifications');
                });
                state.api = Object.values(require(id)).find(value => typeof value?.getServerDrivenPlan === 'function');
            }
            function text(blocks) {
                const template = document.createElement('template');
                template.innerHTML = (blocks || []).map(block => block.html_text || block.emoji_shortcode || '').join('');
                return template.content.textContent.replace(/\\s+/g, ' ').trim();
            }
            state.pending = true;
            const account = state.user;
            const request = state.request = (state.request || 0) + 1;
            const timeout = setTimeout(() => { if (state.request === request) state.pending = false; }, 15000);
            state.api.getServerDrivenPlan({currentPlanId: '-1', currentView: user.selectedView?.view || 'recents', isPlanOrg: false})
                .then(({data}) => {
                    if (window.__resketchHomeFeed !== state || !state.pending || state.request !== request
                        || menuStore()?.getState()?.user?.id !== account || !Array.isArray(data.meta)) return;
                    const baseline = !state.seen;
                    state.seen ||= new Set();
                    for (const item of data.meta) {
                        const id = String(item.notification_id || '');
                        if (!id || state.seen.has(id)) continue;
                        state.seen.add(id);
                        if (baseline || !item.is_unread) continue;
                        const body = item.preferred_attachments?.find(attachment => attachment.body?.title)?.body;
                        const title = text(body?.title);
                        if (title) state.queue.push({id, title, body: [text(body?.subtitle), text(body?.description)].filter(Boolean).join('\\n'),
                                                   url: item.deeplink?.href || ''});
                    }
                    while (state.seen.size > 500) state.seen.delete(state.seen.values().next().value);
                })
                .catch(() => {})
                .finally(() => { clearTimeout(timeout); if (state.request === request) state.pending = false; });
        } catch (_) { state.pending = false; }
        return JSON.stringify({pending: state.pending});
    })()`;
}

function drainFeedScript() {
    return `JSON.stringify({pending: !!window.__resketchHomeFeed?.pending,
                           notifications: window.__resketchHomeFeed?.queue.splice(0) || []})`;
}
