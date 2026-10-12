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
    vm.runInContext(policy.script(true), context)
    await worker.showNotification('Re-enabled')
    await push.subscribe()
    assert.equal(shown, 3)
    assert.equal(subscribed, 2)
    console.log('Home-only page, worker, push subscription and settings-toggle notification checks passed')
}
async function checkFeed() {
    let account = 'first', items = [], parameters
    const api = {async getServerDrivenPlan(args) { parameters = args; return {data: {meta: items}} }}
    const runtime = () => ({api})
    runtime.m = {feed: function getServerDrivenPlan() { return '/api/user_notifications' }}
    const window = {rspackChunk_figma_web_bundler: {push: chunk => chunk[2](runtime)}}
    const context = vm.createContext({window, setTimeout, clearTimeout, document: {
        createElement() { return {innerHTML: '', get content() {
            return {textContent: this.innerHTML.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&')}
        }} }
    }, currentStore: {getState: () => ({user: {id: account}, selectedView: {view: 'recents'}})}})
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
    account = 'second'; items = [item('other-account')]
    assert.deepEqual((await poll()).notifications, [], 'Account changes establish a new baseline')
    api.getServerDrivenPlan = async () => { throw new Error('Offline') }
    assert.deepEqual(await poll(), {pending: false, notifications: []})
    api.getServerDrivenPlan = async () => ({data: {meta: []}})
    assert.deepEqual(await poll(), {pending: false, notifications: []}, 'Recover after a network error')
    console.log('Home notification feed baseline, unread filtering, text, duplicates, accounts and offline recovery checks passed')
}
Promise.all([check(), checkFeed()]).catch(error => { console.error(error); process.exitCode = 1 })
