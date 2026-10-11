const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const calls = []
const state = {selectedView: {view: 'fullscreen'}, mirror: {appModel: {isReadOnly: false}}}
const items = [{name: 'view-menu', displayText: 'View', children: [
    {action: 'toggle-rulers', displayText: 'Rulers', isChecked: true, shortcut: 'Shift+R'},
    {separator: true},
    {name: 'nested', displayText: 'Nested', children: [
        {action: 'disabled', displayText: 'Unavailable', disabled: true},
        {action: 'callback-and-action', displayText: 'Export', args: {format: 'svg'},
         callback: (...args) => calls.push(['callback', ...args.slice(0, 3)])}
    ]},
    {render: () => {}, displayText: 'Custom widget'},
    {name: 'no-handler', displayText: 'Unsupported'}
]}]
const dispatch = () => {}
const store = {getState: () => state, dispatch}
const root = {__reactFiberStore: {memoizedProps: {store}}}
const context = vm.createContext({
    qsTr: text => text,
    location: {hostname: 'www.figma.com'},
    document: {body: {dataset: {}}, querySelector: () => root,
               createTreeWalker: () => ({nextNode: () => null})},
    MouseEvent: class {},
    window: {
        get _fullscreen_() { throw new Error("Debug facade must not be touched") },
        get store() { throw new Error("Debug store must not be touched") },
        __resketchMenus: {
            build: () => items, visible: () => true, filter: value => value,
            actions: {get: (...args) => () => calls.push(['action', ...args])}
        }
    }
})
vm.runInContext(fs.readFileSync('src/FigmaMenu.js', 'utf8'), context)
const run = command => JSON.parse(vm.runInContext(context.script(command), context))

const snapshot = run()
const children = snapshot.menus[0].children
assert.equal(children.length, 3)
assert.equal(children[0].checked, true)
assert.equal(children[0].shortcut, 'Shift+R')
assert.equal(children[1].separator, true)
assert.equal(children[2].children[0].enabled, false)
assert.equal(run(children[2].children[0].id).executed, false)
assert.equal(run('figma/view-menu/missing').executed, false)
assert.deepEqual(calls, [])
assert.equal(run(children[0].id).executed, true)
assert.deepEqual(calls.pop().slice(0, 3), ['action', 'toggle-rulers', 'os-menu'])
assert.equal(run(children[2].children[1].id).executed, true)
assert.equal(calls[0][0], 'callback')
assert.equal(calls[0][1], 'callback-and-action')
assert.equal(calls[0][3], dispatch)
assert.equal(calls[1][0], 'action')

// Recheck availability at invocation; a previously enabled command may change.
items[0].children[0].disabled = true
assert.equal(run(children[0].id).executed, false)
context.location.hostname = 'accounts.google.com'
assert.deepEqual(run().menus, [])
context.location.hostname = 'www.figma.com'
state.selectedView.view = 'files'
assert.deepEqual(run().menus, [])

// Home retains only actions that do not depend on an editor or a selection.
const homeMenus = context.homeMenus('dark', true)
assert.deepEqual(Array.from(homeMenus, menu => menu.text), ['View', 'Preferences', 'Help'])
const themeItems = homeMenus[1].children[0].children
assert.deepEqual(Array.from(themeItems, item => item.checked), [false, false, true])
assert.equal(homeMenus[2].children.find(item => item.id === 'home/account-settings').enabled, true)
assert.equal(context.homeMenus('auto', false)[2].children.find(item => item.id === 'home/sign-out').enabled, false)

const dispatched = []
const user = {id: 'test-user'}
const settings = {sE: {type: 'account-modal'}, c3: {ACCOUNT: 'account'}}
const openModal = options => {
    // optOutOfPrevModal, showModalsBeneath: signature of Figma's modal creator.
    return options
}
const modules = {
    settings: () => { /* accountModalSubViewData ChangeAddressModal */ },
    modals: () => { /* optOutOfPrevModal showModalsBeneath */ },
    accounts: () => { /* logoutOneUser autosave_modal_shown */ }
}
const runtime = id => ({settings, modals: {openModal}, accounts: {q: options => options}}[id])
runtime.m = modules
context.window.__resketchHomeMenuRuntime = runtime
root.__reactFiberStore.memoizedProps.store = {
    getState: () => ({user}), dispatch: action => dispatched.push(action)
}
context.location.pathname = '/files/recent'
const homeRun = command => JSON.parse(vm.runInContext(context.homeScript(command), context))
assert.equal(homeRun().authenticated, true)
assert.equal(homeRun('home/account-settings').executed, true)
assert.equal(dispatched[0].type, settings.sE)
assert.equal(dispatched[0].data.tab, 'account')
assert.equal(homeRun('home/sign-out').executed, true)
assert.equal(dispatched[1].user, user)
assert.equal(homeRun('figma/view-menu/toggle-rulers').executed, false)
context.location.pathname = '/design/file-id'
assert.equal(homeRun('home/sign-out').executed, false)
assert.equal(dispatched.length, 2)
console.log('Figma menu bridge checks passed')
