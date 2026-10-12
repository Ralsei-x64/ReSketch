// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const policy = vm.createContext({})
vm.runInContext(fs.readFileSync('src/NotificationPolicy.js', 'utf8'), policy)

async function check() {
    let shown = 0, subscribed = 0
    class Notification {
        static permission = 'granted'
        static requestPermission() { return Promise.resolve('granted') }
        constructor() { ++shown }
    }
    class ServiceWorkerRegistration {
        showNotification() { ++shown; return Promise.resolve() }
    }
    class PushManager {
        subscribe() { ++subscribed; return Promise.resolve({endpoint: 'subscription'}) }
    }
    const window = {Notification, ServiceWorkerRegistration, PushManager}
    const context = vm.createContext({window, DOMException, Promise})
    const worker = new ServiceWorkerRegistration(), push = new PushManager()
    vm.runInContext(policy.script(true), context)
    new window.Notification('Home')
    await worker.showNotification('Home push')
    await push.subscribe()
    assert.equal(shown, 2)
    assert.equal(subscribed, 1)
    vm.runInContext(policy.script(false), context)
    assert.equal(window.Notification.permission, 'denied')
    assert.equal(await window.Notification.requestPermission(), 'denied')
    assert.throws(() => new window.Notification('File'), {name: 'NotAllowedError'})
    await assert.rejects(worker.showNotification('File push'), {name: 'NotAllowedError'})
    await assert.rejects(push.subscribe(), {name: 'NotAllowedError'})
    assert.equal(shown, 2)
    assert.equal(subscribed, 1)
    let disconnected = false
    window.__resketchHomeFeed = {unsubscribe: () => disconnected = true}
    vm.runInContext(policy.script(false), context)
    assert.equal(disconnected, true, 'Disabling notifications disconnects the Home listener')
    assert.equal(window.__resketchHomeFeed, null)
    vm.runInContext(policy.script(true), context)
    await worker.showNotification('Re-enabled')
    await push.subscribe()
    assert.equal(shown, 3)
    assert.equal(subscribed, 2)
    console.log('Home-only page, worker, push subscription and settings-toggle notification checks passed')
}
async function checkFeed() {
    let account = 'first', items = [], parameters
    const storage = new Map(), listeners = new Set()
    let bell = {}, notifications = {}, nonce = 0
    const api = {async getServerDrivenPlan(args) { parameters = args; return {data: {meta: items}} }}
    const runtime = () => ({api})
    runtime.m = {feed: function getServerDrivenPlan() { return '/api/user_notifications' }}
    const window = {rspackChunk_figma_web_bundler: {push: chunk => chunk[2](runtime)}}
    const context = vm.createContext({window, setTimeout, clearTimeout,
        sessionStorage: {getItem: key => storage.get(key) || null, setItem: (key, value) => storage.set(key, value)}, document: {
        createElement() { return {innerHTML: '', get content() {
            return {textContent: this.innerHTML.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&')}
        }} }
    }, currentStore: {
        getState: () => ({user: {id: account}, selectedView: {view: 'recents'},
            teamFeedBellStates: bell, userNotifications: notifications, teamFeedRefreshNonce: nonce}),
        subscribe: callback => {listeners.add(callback); return () => listeners.delete(callback)}
    }})
    const item = (id, unread = true) => ({notification_id: id, is_unread: unread,
        preferred_attachments: [{body: {title: [{html_text: '<b>Alice</b> mentioned you'}],
            subtitle: [{html_text: 'Design &amp; mockup'}], description: [{html_text: 'Please review.'}]}}],
        deeplink: {href: 'https://www.figma.com/design/Example/Test'}})
    async function poll() {
        vm.runInContext(policy.feedScript('function menuStore(){return currentStore}'), context)
        await new Promise(resolve => setImmediate(resolve))
        return JSON.parse(vm.runInContext(policy.drainFeedScript(), context))
    }
    items = [item('old')]
    assert.deepEqual((await poll()).notifications, [], 'Do not replay the existing feed')
    assert.deepEqual(JSON.parse(JSON.stringify(parameters)), {currentPlanId: '-1', currentView: 'recents', isPlanOrg: false})
    items = [item('new'), item('read', false), item('old')]
    const notification = (await poll()).notifications
    assert.equal(notification.length, 1)
    assert.equal(notification[0].title, 'Alice mentioned you')
    assert.equal(notification[0].body, 'Design & mockup\nPlease review.')
    assert.equal(notification[0].url, 'https://www.figma.com/design/Example/Test')
    assert.deepEqual((await poll()).notifications, [], 'Polling must not duplicate notifications')
    items[0].preferred_attachments[0].body.created_at = '2026-10-12T17:00:00Z'
    assert.equal((await poll()).notifications.length, 1, 'A new reply batched into an existing ID must notify')
    assert.deepEqual((await poll()).notifications, [], 'Unchanged batched activity is deduplicated')
    items[0].preferred_attachments[0].body.description = [{html_text: 'A second comment.'}]
    assert.equal((await poll()).notifications[0].body, 'Design & mockup\nA second comment.')
    items[1].is_unread = true
    assert.equal((await poll()).notifications.length, 1, 'New unread activity on an existing notification must notify')
    items.unshift(null, {notification_id: 'incomplete', preferred_attachments: []})
    assert.deepEqual((await poll()).notifications, [], 'An incomplete item must not interrupt the feed')
    items[1] = item('incomplete')
    assert.equal((await poll()).notifications.length, 1, 'An incomplete item can recover instead of being permanently suppressed')
    assert.equal(listeners.size, 1, 'Only one Home store listener is installed')
    for (const callback of listeners) callback()
    assert.equal(JSON.parse(vm.runInContext(policy.drainFeedScript(), context)).refresh, false,
        'Unrelated store updates do not fetch the notification feed')
    for (const change of [() => bell = {}, () => notifications = {}, () => ++nonce]) {
        change()
        for (const callback of listeners) callback()
        assert.equal(JSON.parse(vm.runInContext(policy.drainFeedScript(), context)).refresh, true,
            'Home notification events request an immediate refresh')
        await poll()
    }
    window.__resketchHomeFeed.unsubscribe()
    window.__resketchHomeFeed = null // A Home document reload.
    items.unshift(item('arrived-during-reload'))
    assert.equal((await poll()).notifications.length, 1, 'Reloading Home preserves the baseline and catches new activity')
    assert.equal(listeners.size, 1)
    account = 'second'; items = [item('other-account')]
    assert.deepEqual((await poll()).notifications, [], 'Account changes establish a new baseline')
    api.getServerDrivenPlan = async () => { throw new Error('Offline') }
    assert.deepEqual(await poll(), {pending: false, refresh: false, notifications: []})
    api.getServerDrivenPlan = async () => ({data: {meta: []}})
    assert.deepEqual(await poll(), {pending: false, refresh: false, notifications: []}, 'Recover after a network error')
    console.log('Home notification activity updates, immediate refresh, reload recovery, filtering and deduplication checks passed')
}
Promise.all([check(), checkFeed()]).catch(error => { console.error(error); process.exitCode = 1 })
