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
check().catch(error => { console.error(error); process.exitCode = 1 })
