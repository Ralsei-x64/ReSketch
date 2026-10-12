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
            if (!enabled) {
                window.__resketchHomeFeed?.unsubscribe?.();
                window.__resketchHomeFeed = null;
            }
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
        const store = menuStore();
        const user = store?.getState();
        if (!user?.user?.id) return JSON.stringify({pending: false});
        if (state.user !== user.user.id) {
            state.user = user.user.id;
            state.seen = null;
            state.queue = [];
            // Keep the baseline over Home reloads so activity arriving during a
            // reload is not mistaken for old notification history.
            try {
                const saved = JSON.parse(sessionStorage.getItem('resketch-notifications-' + state.user));
                if (Array.isArray(saved)) state.seen = new Map(saved);
            } catch (_) {}
        }
        if (state.store !== store) {
            state.unsubscribe?.();
            state.store = store;
            let previous = user;
            state.unsubscribe = store.subscribe?.(() => {
                const next = store.getState();
                if (next.teamFeedBellStates !== previous.teamFeedBellStates
                    || next.teamFeedRefreshNonce !== previous.teamFeedRefreshNonce
                    || next.userNotifications !== previous.userNotifications
                    || next.user?.id !== previous.user?.id) state.dirty = true;
                previous = next;
            });
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
                template.innerHTML = (Array.isArray(blocks) ? blocks : []).map(block => block?.html_text || block?.emoji_shortcode || '').join('');
                return template.content.textContent.replace(/\\s+/g, ' ').trim();
            }
            state.pending = true;
            state.dirty = false;
            const account = state.user;
            const request = state.request = (state.request || 0) + 1;
            const timeout = setTimeout(() => { if (state.request === request) state.pending = false; }, 15000);
            state.api.getServerDrivenPlan({currentPlanId: '-1', currentView: user.selectedView?.view || 'recents', isPlanOrg: false})
                .then(({data}) => {
                    if (window.__resketchHomeFeed !== state || !state.pending || state.request !== request
                        || menuStore()?.getState()?.user?.id !== account || !Array.isArray(data.meta)) return;
                    const baseline = !state.seen;
                    state.seen ||= new Map();
                    for (const item of data.meta) {
                        const id = String(item?.notification_id || '');
                        if (!id) continue;
                        const body = item.preferred_attachments?.find(attachment => attachment?.body?.title)?.body;
                        const title = text(body?.title);
                        if (!title) continue;
                        const message = [text(body?.subtitle), text(body?.description)].filter(Boolean).join('\\n');
                        const url = item.deeplink?.href || '';
                        // Figma batches new replies into existing IDs. Deduplicate
                        // the activity, not just the notification's ID.
                        const signature = JSON.stringify([body.created_at, title, message, url]);
                        const previous = state.seen.get(id);
                        state.seen.set(id, {signature, unread: !!item.is_unread});
                        if (!baseline && item.is_unread && (!previous || !previous.unread || previous.signature !== signature))
                            state.queue.push({id, title, body: message, url});
                    }
                    while (state.seen.size > 500) state.seen.delete(state.seen.keys().next().value);
                    try { sessionStorage.setItem('resketch-notifications-' + account, JSON.stringify([...state.seen])); } catch (_) {}
                })
                .catch(() => {})
                .finally(() => { clearTimeout(timeout); if (state.request === request) state.pending = false; });
        } catch (_) { state.pending = false; }
        return JSON.stringify({pending: state.pending});
    })()`;
}

function drainFeedScript() {
    return `JSON.stringify({pending: !!window.__resketchHomeFeed?.pending,
                           refresh: !!window.__resketchHomeFeed?.dirty,
                           notifications: window.__resketchHomeFeed?.queue.splice(0) || []})`;
}
