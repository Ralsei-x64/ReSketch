// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const policy = vm.createContext({})
vm.runInContext(fs.readFileSync('src/Policy.js', 'utf8'), policy)

assert.equal(policy.isFigmaUrl('https://www.figma.com/design/abc'), true)
assert.equal(policy.isFigmaUrl('https://figma.com.evil.test/'), false)
assert.equal(policy.isFigmaUrl('https://evil.test/?next=figma.com'), false)
assert.equal(policy.isFigmaUrl('file:///etc/passwd'), false)
assert.equal(policy.isFileUrl('https://www.figma.com/design/abc/My-File'), true)
assert.equal(policy.isFileUrl('https://www.figma.com/board/abc/My-Jam'), true)
assert.equal(policy.isFileUrl('https://www.figma.com/make/abc/My-App'), true)
assert.equal(policy.isFileUrl('https://www.figma.com/'), false)
assert.equal(policy.fileKey('https://www.figma.com/design/File_A1/Old-Name?node-id=1-2'), 'File_A1')
assert.equal(policy.fileKey('https://www.figma.com/proto/File_A1/New-Name'), 'File_A1')
assert.equal(policy.fileKey('https://www.figma.com/board/File_B2'), 'File_B2')
assert.equal(policy.fileKey('https://www.figma.com/files/recent'), '')
assert.equal(policy.fileKey('https://figma.com.evil.test/design/File_A1'), '')
assert.equal(policy.isFileBrowserUrl('https://www.figma.com/files/recent'), true)
assert.equal(policy.isFileBrowserUrl('https://www.figma.com/files/team/abc'), true)
assert.equal(policy.isFileBrowserUrl('https://www.figma.com/'), true)
assert.equal(policy.isFileBrowserUrl('https://www.figma.com'), true)
assert.equal(policy.isFileBrowserUrl('https://www.figma.com/design/abc/My-File'), false)
assert.equal(policy.isNewFileTabUrl('https://www.figma.com/desktop_new_tab?fuid=123'), true)
assert.equal(policy.isNewFileTabUrl('https://www.figma.com/files/recent'), false)
assert.equal(policy.pageLabel('https://www.figma.com/', 'Figma'), 'Home')
assert.equal(policy.pageLabel('https://www.figma.com/desktop_new_tab', 'Figma'), 'New file')
assert.equal(policy.pageLabel('https://www.figma.com/design/abc/My-File', 'My File – Figma'), 'My File')
assert.equal(policy.windowTitle('https://www.figma.com/', 'Figma'), 'ReSketch — Home')
assert.equal(policy.windowTitle('https://www.figma.com/desktop_new_tab', 'Figma'), 'ReSketch — New file')
assert.equal(policy.windowTitle('https://accounts.google.com/signin', ''), 'ReSketch — Google sign in')
assert.equal(policy.windowTitle('https://www.figma.com/design/abc/My-File', 'My File – Figma'), 'ReSketch — My File')
assert.equal(policy.windowTitle('https://www.figma.com/design/abc/My-File', 'Figma'), 'ReSketch — My File')
assert.equal(policy.windowTitle('https://www.figma.com/board/abc/My-Jam', 'My Jam — FigJam'), 'ReSketch — My Jam')
assert.equal(policy.windowTitle('https://www.figma.com/design/abc/Figma-Notes', 'Figma Notes – Figma'), 'ReSketch — Figma Notes')
assert.equal(policy.isAuthGrantUrl('https://www.figma.com/app_auth/abc-123/grant'), true)
assert.equal(policy.isGoogleSignInUrl('https://accounts.google.com/o/oauth2/v2/auth'), true)
assert.equal(policy.isGoogleSignInUrl('https://accounts.google.com:443/signin/v2'), true)
assert.equal(policy.isGoogleSignInUrl('https://accounts.google.com.evil.test/'), false)
assert.equal(policy.isGoogleSignInUrl('http://accounts.google.com/'), false)
assert.equal(policy.isGoogleSignInUrl('https://www.google.com/'), false)
for (const address of ['https://example.com/path', 'http://example.com/',
                      'https://figma.com.evil.test/', 'https://accounts.google.com.evil.test/',
                      'https://example.com/start_google_sso'])
    assert.equal(policy.isExternalWebUrl(address), true)
for (const address of ['https://www.figma.com/design/abc', 'https://help.figma.com/',
                      'https://accounts.google.com/o/oauth2/v2/auth', 'about:blank',
                      'file:///etc/passwd', 'javascript:alert(1)', 'data:text/html,hello',
                      'blob:https://www.figma.com/example', 'figma://file/abc/name'])
    assert.equal(policy.isExternalWebUrl(address), false)
assert.equal(policy.tabTitle('12345678901234567890'), '12345678901234567890')
assert.equal(policy.tabTitle('123456789012345678901'), '1234567890123456789…')
assert.equal(policy.deepLink('figma://file/abc/name'), 'https://www.figma.com/file/abc/name')
assert.equal(policy.deepLink('https://evil.test/'), '')
assert.equal(policy.redeemSecret('figma://app_auth/redeem?g_secret=abc_123&locale=en'), 'abc_123')

// Bursts of file opens are diverted before Home's document or route changes.
let homeNavigation, listeners = 0, homeRoute = 'recents'
const opens = []
const microtasks = []
const homeState = {view: 'recents'}
const home = vm.createContext({
    history: {state: homeState},
    queueMicrotask: callback => microtasks.push(callback),
    PopStateEvent: class { constructor(type, options) { this.type = type; this.state = options.state } },
    window: {dispatchEvent(event) {
        assert.equal(event.type, 'popstate')
        homeRoute = event.state.view
    }}, navigation: {addEventListener(type, listener) {
        assert.equal(type, 'navigate'); ++listeners; homeNavigation = listener
    }}, __resketchNative(kind, address) { assert.equal(kind, 'home-file'); opens.push(address) }
})
home.window.navigation = home.navigation
vm.runInContext(policy.homeNavigationScript(true), home)
vm.runInContext(policy.homeNavigationScript(true), home)
assert.equal(listeners, 1)
for (let i = 0; i < 20; ++i) {
    let prevented = false
    const url = `https://www.figma.com/design/Burst_${i}/File`
    // Like Figma, commit app state even when pushState's navigation is cancelled.
    homeRoute = 'fullscreen'
    homeNavigation({destination: {url, sameDocument: true}, cancelable: true, preventDefault() { prevented = true }})
    assert.equal(prevented, true)
    assert.equal(opens[i], url)
    homeRoute = 'fullscreen'
    microtasks.splice(0).forEach(callback => callback())
    assert.equal(homeRoute, 'recents', 'Home restores its app route, not only its URL')
}
for (const url of ['https://www.figma.com/files/recent', 'https://accounts.google.com/signin',
                   'https://figma.com.evil.test/design/abc', 'https://www.figma.com:444/design/abc'])
    homeNavigation({destination: {url}, cancelable: true, preventDefault() { assert.fail(url) }})
assert.equal(opens.length, 20)
homeNavigation({destination: {url: 'https://www.figma.com/design/Document/File', sameDocument: false},
                cancelable: true, preventDefault() {}})
assert.equal(microtasks.length, 0, 'Cancelled document loads do not need a route restoration')
assert.equal(policy.homeNavigationScript(false), '')
console.log('Home file navigation burst checks passed')
