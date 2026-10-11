// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const source = fs.readFileSync('src/Main.qml', 'utf8')
const functions = ['closeTabByMiddleClick', 'activateTab'].map(name => {
    const start = source.indexOf(`    function ${name}(`)
    assert.notEqual(start, -1)
    const end = source.indexOf('\n    function ', start + 1)
    return source.slice(start, end)
}).join('\n')

function run(queue, clickedIndex) {
    const views = Array.from({length: 4}, () => ({}))
    const closed = []
    const activated = []
    const context = vm.createContext({
        views,
        activeView: views[2],
        pendingCloseViews: [],
        closingViews: [],
        readyCloseViews: [],
        closeTab: index => closed.push(index),
        activateView: view => activated.push(views.indexOf(view))
    })
    if (queue)
        context[queue].push(views[1])
    vm.runInContext(`${functions}\ncloseTabByMiddleClick(views[${clickedIndex}]); activateTab(${clickedIndex})`, context)
    return {closed, activated}
}

for (const queue of ['pendingCloseViews', 'closingViews', 'readyCloseViews']) {
    assert.deepEqual(run(queue, 1), {closed: [], activated: []})
    assert.deepEqual(run(queue, 0), {closed: [0], activated: [0]})
}
assert.deepEqual(run(null, 2), {closed: [2], activated: [2]})
