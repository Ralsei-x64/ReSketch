// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

function page(hostname = 'www.figma.com', native = true) {
    const elements = new Map()
    const children = []
    let observer, queued = [], dispatches = 0, lookups = 0
    const body = {
        theme: 'light', style: {},
        getAttribute() { return this.theme },
        setAttribute(key, value) { this.theme = value }
    }
    const head = {
        appendChild(style) {
            const index = children.indexOf(style)
            if (index >= 0) children.splice(index, 1)
            children.push(style)
            style.parentNode = head
            elements.set(style.id, style)
        }
    }
    const nested = {theme: 'light'}
    const store = {getState: () => ({}), dispatch(action) {
        ++dispatches
        body.theme = action.theme
        nested.theme = action.theme
        body.style.colorScheme = action.theme
    }}
    const provider = {__reactFiberStore: {memoizedProps: {store}}}
    const runtime = () => ({D6: 'on-theme-update-ipc-key', id: options => options})
    runtime.m = {theme: {toString() {
        ++lookups
        return 'global-debug-theme-preference on-theme-update-ipc-key'
    }}}
    const context = vm.createContext({
        location: {hostname},
        window: native ? {rspackChunk_figma_web_bundler: {push(chunk) { chunk[2](runtime) }}} : {},
        document: {
            body, head, documentElement: {style: {}},
            querySelector: () => provider,
            createTreeWalker: () => ({nextNode: () => null}),
            getElementById: id => elements.get(id),
            createElement: () => ({textContent: '', remove() {
                elements.delete(this.id)
                children.splice(children.indexOf(this), 1)
            }})
        },
        MutationObserver: class {
            constructor(callback) { this.callback = callback; observer = this }
            observe() {}
            disconnect() {}
        },
        setTimeout: fn => { queued.push(fn); return fn },
        clearTimeout: fn => { queued = queued.filter(item => item !== fn) }
    })
    vm.runInContext(fs.readFileSync('src/FigmaMenu.js', 'utf8'), context)
    const storeSource = context.storeSource
    vm.runInContext(fs.readFileSync('src/FigmaTheme.js', 'utf8'), context)
    return {
        context, body, nested, elements, children,
        run: options => vm.runInContext(context.script(options, storeSource), context),
        mutate: () => observer.callback(),
        drain: () => { for (let i = 0; queued.length && i < 100; ++i) queued.shift()() },
        dispatches: () => dispatches, lookups: () => lookups, pending: () => queued.length
    }
}

const app = page()
vm.runInContext(app.context.sidebarMaskSource, app.context)
const viewport = {left: 0, top: 0, width: 1000, height: 700}
const panels = [{left: 0, top: 0, right: 200, bottom: 700},
                {left: 800, top: 0, right: 1000, bottom: 700}]
assert.match(app.context.sidebarMask(viewport, panels), /^polygon\(evenodd,/)
assert.match(app.context.sidebarMask(viewport, panels), /800px 0px, 1000px 0px/)
assert.equal(app.context.sidebarMask({left: 200, top: 0, width: 600, height: 700}, panels), 'none',
             'inset Figma canvas must not be clipped or resized')
assert.match(app.context.sidebarMask({left: 150, top: 20, width: 700, height: 500}, panels),
             /0px 0px, 50px 0px, 50px 500px/, 'holes must use canvas-local coordinates')
const floating = [{left:8, top:8, right:192, bottom:692, radius:22}]
assert.match(app.context.sidebarMask(viewport, floating), /^path\(evenodd,/)
assert.match(app.context.sidebarMask(viewport, floating), /M30 8 H170 A22 22/,
             'rounded holes follow the actual floating surface, leaving the surrounding canvas opaque')
assert.equal(app.context.sidebarMask({left:200, top:0, width:600, height:700}, floating), 'none')

// The native render buffer and coordinate system must expand together. Native
// layout flags are temporary; the actual panel state and stored widths stay intact.
const flags = {left: false, right: true}
const observable = key => ({getCopy: () => flags[key], set: value => { flags[key] = value }})
const uiState = {leftPanelCollapsed: observable('left'), showPropertiesPanel: observable('right')}
class NativeUi { getLeftRailWidth() { return 49 } }
const widths = []
let failLayout = false
const layoutApi = {updateLayoutForMinimizeUI() {
    if (failLayout) throw Error('Renderer unavailable')
    widths.push(1280 - (flags.left ? 0 : 280) - (flags.right ? 241 : 0) - new NativeUi().getLeftRailWidth())
}}
const originalLayout = layoutApi.updateLayoutForMinimizeUI, originalRail = NativeUi.prototype.getLeftRailWidth
const engine = {uiState: () => uiState, editorPreferences: () => ({})}
const runtime = id => id === '17' ? {engine} : {layoutApi}
runtime.m = {
    17: function() { return '__getProperty_leftPanelCollapsed' },
    23: function(e, exports, require) { const module = require(29); module.layoutApi.updateLayoutForMinimizeUI() },
    29: function() {}
}
const layoutContext = vm.createContext({window: {__resketchAppearance: {runtime},
    _fullscreen_: {_getTsApisForWasm: () => ({FigmaAppUi: () => new NativeUi()})}}})
vm.runInContext(app.context.sidebarLayoutSource, layoutContext)
const overlay = vm.runInContext('floatingCanvasLayout()', layoutContext)
assert.ok(overlay)
overlay.update()
layoutApi.updateLayoutForMinimizeUI()
assert.deepEqual(widths, [1280, 1280], 'both the initial layout and later native updates use the entire canvas')
assert.deepEqual(flags, {left: false, right: true}, 'panels stay visible without changing their actual state')
failLayout = true
assert.throws(() => overlay.update(), /Renderer unavailable/)
assert.deepEqual(flags, {left: false, right: true}, 'layout failures still restore UI flags')
failLayout = false
flags.left = true
overlay.dispose()
assert.equal(widths.at(-1), 990, 'disabling floating mode restores normal insets, including current user choices')
assert.equal(layoutApi.updateLayoutForMinimizeUI, originalLayout)
assert.equal(NativeUi.prototype.getLeftRailWidth, originalRail)
app.run({dark: true})
assert.equal(app.body.theme, 'dark')
assert.equal(app.nested.theme, 'dark', 'Figma state must update nested text/theme scopes')
app.run({dark: false})
assert.equal(app.nested.theme, 'light')
app.run({dark: false})
assert.equal(app.dispatches(), 2, 'unchanged theme must not dispatch repeatedly')
assert.equal(app.lookups(), 1, 'module lookup is cached per document')
app.body.theme = 'dark'
app.mutate()
assert.equal(app.body.theme, 'light', 'Figma must keep following the selected app theme')

app.run({dark: false, systemColors: true, palette: {text: '#123456', window: '#abcdef'},
         customCssEnabled: true, customCss: 'body { --color-text: #654321 !important; }'})
assert.match(app.elements.get('resketch-system-colors').textContent, /--color-text:#123456 !important/)
assert.doesNotMatch(app.elements.get('resketch-system-colors').textContent, /canvas/)
assert.equal(app.children.at(-1).id, 'resketch-custom-css')
app.run({dark: true})
assert.equal(app.elements.size, 0, 'disabling overrides restores Figma styles')
assert.doesNotMatch(app.context.paletteCss({text: 'red; } body {display:none'}), /display:none/)

// Both screenshot cases: dark theme with a pale highlight, light theme with a dark one.
for (const palette of [
    {dark: true, window: '#13181c', base: '#0b0f11', text: '#a4acb2', secondaryText: '#6f767c',
     accent: '#a1c9e1', accentText: '#1a4559', link: '#4ca6db', tooltip: '#181e23', tooltipText: '#dfe6ed'},
    {dark: false, window: '#e7ecf2', base: '#f4f6fa', text: '#586066', secondaryText: '#75838f',
     accent: '#2b647f', accentText: '#f4faff', link: '#006fa9', tooltip: '#ffffff', tooltipText: '#303840'},
    {dark: true, window: '#31363b', base: '#232629', text: '#fcfcfc', secondaryText: '#a1a9b1',
     accent: '#3daee9', accentText: '#ffffff', link: '#1d99f3', tooltip: '#31363b', tooltipText: '#fcfcfc'}
]) {
    const css = app.context.paletteCss(palette)
    const tokens = Object.fromEntries(Array.from(css.matchAll(/--color-([\w-]+):(#[\da-f]{6}) !important;/gi), match => [match[1], match[2]]))
    assert.notEqual(tokens['bg-selected'], palette.accent, 'ordinary selections need a tint')
    assert.notEqual(tokens['bg-hover'], tokens.bg, 'hover must stay visible even when AlternateBase equals Window')
    assert.notEqual(tokens['bg-brand-hover'], tokens['bg-brand'])
    assert.equal(tokens['loading-progress-bar'], palette.accent)
    assert.equal(tokens['loading-progress-accent'], tokens['bg-brand-hover'])
    assert.notEqual(tokens['loading-progress-wrapper'], tokens['loading-progress-bar'])
    assert.equal(tokens.bgtoolbarmodeswitcher, tokens['bg-hover'], 'mode switcher uses a themed surface')
    assert.equal(tokens.bordertranslucent, tokens.border, 'inset editor and navigation separators match')
    assert.ok(app.context.contrast(tokens.border, tokens.bg) >= 1.6, 'web UI borders remain visible')
    for (const state of ['', '-hover', '-pressed']) {
        assert.ok(app.context.contrast(tokens['text-onbrand'], tokens['bg-brand' + state]) >= 4.5)
        assert.ok(app.context.contrast(tokens['text-onselected'], tokens['bg-selected' + state]) >= 4.5)
        for (const surface of ['menu', 'toolbar', 'tooltip'])
            assert.ok(app.context.contrast(tokens['icon-' + surface + '-onselected'], tokens['bg-' + surface + '-selected' + state]) >= 4.5)
    }
    assert.equal(tokens['bg-tooltip'], palette.tooltip)
    assert.ok(app.context.contrast(tokens['text-tooltip-secondary'], tokens['bg-tooltip']) >= 4.5)
    assert.doesNotMatch(css, /--color-(?:bg|text|icon|border)-(?:component|danger|warning|success|fs-|canvas)/)
    assert.match(css, /sidebarRowSelected.*color:var\(--color-text-onselected\)/)
    assert.match(css, /file-icon.*--color-icon:var\(--color-icon-onbrand\)/)
    app.run({dark: !palette.dark, systemColors: true, palette})
    assert.equal(app.body.theme, palette.dark ? 'dark' : 'light', 'native theme must match the actual KDE surface')
}

const login = page('www.figma.com', false)
login.run({dark: true})
assert.equal(login.body.theme, 'dark')
assert.equal(login.body.style.colorScheme, 'dark')
login.drain()
assert.equal(login.pending(), 0, 'runtime retries must end on pages without Figma app code')
const google = page('accounts.google.com')
google.run({dark: true, customCssEnabled: true, customCss: 'body{display:none}'})
assert.equal(google.body.theme, 'light')
assert.equal(google.elements.size, 0, 'never inject CSS into the Google sign-in page')
app.run({opacity: 50, translucentSidebars: false})
assert.ok(app.elements.has('resketch-loading-background'), 'loading transparency is independent of sidebars')
app.run({opacity: 100})
assert.equal(app.elements.has('resketch-loading-background'), false, 'opaque setting restores original loading backgrounds')
console.log('Figma theme synchronization and appearance checks passed')
