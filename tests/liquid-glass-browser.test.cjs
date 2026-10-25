// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
// Run against an isolated ReSketch about:blank tab: node tests/liquid-glass-browser.test.cjs PORT
const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const theme = vm.createContext({})
vm.runInContext(fs.readFileSync('src/FigmaTheme.js', 'utf8'), theme)

async function check() {
    const port = Number(process.argv[2])
    assert.ok(port > 0 && port < 65536, 'Supply the isolated app DevTools port')
    const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
    const page = pages.find(page => page.type === 'page' && page.url === 'about:blank')
    assert.ok(page, 'An isolated about:blank tab is required')
    const socket = new WebSocket(page.webSocketDebuggerUrl)
    await new Promise(resolve => socket.addEventListener('open', resolve, {once:true}))
    let serial = 0
    const pending = new Map()
    socket.addEventListener('message', ({data}) => {
        const message = JSON.parse(data)
        if (message.id) { pending.get(message.id)(message); pending.delete(message.id) }
    })
    const js = expression => new Promise((resolve, reject) => {
        const id = ++serial
        pending.set(id, message => {
            if (message.error || message.result.exceptionDetails) reject(message.error || message.result.exceptionDetails)
            else resolve(message.result.result.value)
        })
        socket.send(JSON.stringify({id, method:'Runtime.evaluate', params:{expression, returnByValue:true, awaitPromise:true}}))
    })
    const settle = () => js('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))')
    try {
        await js('window.__resketchSidebars?.dispose();delete window.__resketchSidebars')
        await js(`document.body.innerHTML = '<style>body{margin:0;--color-bg:#fff;--color-border:#888}.gpu-view-content{position:absolute;inset:0;background:repeating-linear-gradient(90deg,#2040a0 0 10px,#e0b040 10px 20px)}[data-testid="navigation-bar"]{position:absolute;left:20px;top:20px;width:48px;height:600px;z-index:6}.left_panel_container--sizeContainer--test{position:absolute;left:68px;top:20px;width:240px;height:600px;z-index:6}.toolbelt--root--test{border-radius:9px;position:absolute;left:400px;top:500px;width:400px;height:60px;z-index:6}</style><div class="gpu-view-content"></div><div data-testid="navigation-bar">Rail</div><div class="left_panel_container--sizeContainer--test">Layers</div><div class="toolbelt--root--test">Toolbox</div>'`)
        await js(theme.sidebarSource + ';floatingFilePage=()=>true;floatingCanvasLayout=()=>null;loadingAppearance=()=>{};')
        const options = {translucentSidebars:true, floatingSidebars:true, sidebarBackdrop:'canvas', opacity:20,
            sidebarCanvasBlur:15, sidebarMargin:8, sidebarCornerRadius:15, sidebarShadowStrength:0,
            sidebarLiquidGlass:theme.normalizedLiquidGlass({enabled:true})}
        await js(`window.testOptions=${JSON.stringify(options)};window.stylesheet=(id,css)=>{let node=document.getElementById(id);if(!node){node=document.createElement('style');node.id=id;document.head.append(node)}node.textContent=css};sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        const state = () => js(`(()=>{const group=document.querySelector('[data-resketch-shared-sidebar]'),rail=document.querySelector('[data-testid="navigation-bar"]'),left=document.querySelector('[class*="left_panel_container--sizeContainer--"]');return {rail:getComputedStyle(rail).backdropFilter,left:getComputedStyle(left).backdropFilter,group:getComputedStyle(group).backdropFilter,visible:getComputedStyle(group).display,filters:document.querySelectorAll('filter').length,width:group.getBoundingClientRect().width,joined:left.getAttribute('data-resketch-sidebar-join')}})()`)
        const first = await state()
        assert.equal(first.rail, 'none')
        assert.equal(first.left, 'none')
        assert.equal(first.joined, 'end', 'Recognize the current Figma layers-panel wrapper')
        assert.equal(first.filters, 2, 'One filter for the combined sidebar and one for the toolbox')
        assert.match(first.group, /blur\(15px\).*url/)
        assert.equal(first.width, 272)
        await js(`document.querySelector('[class*="toolbelt--root--"]').style.boxShadow='0 3px 12px rgba(0,0,0,0.25)'`)
        await js(`Object.assign(testOptions.sidebarLiquidGlass,{innerShadowX:-8,innerShadowY:6,innerShadowScale:24,innerShadowBrightness:150,innerShadowStrength:40,innerShadowColor:'#80c020'});sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        const shadows = await js(`[...document.querySelectorAll('[data-resketch-liquid-glass]')].map(node=>getComputedStyle(node).boxShadow)`)
        assert.equal(shadows.length, 2, 'Only the shared sidebar and toolbox receive inner shadows')
        for (const shadow of shadows) assert.match(shadow, /rgba\(192, 255, 48, 0\.4\) -8px 6px 24px 0px inset/)
        assert.match(await js(`getComputedStyle(document.querySelector('[class*="toolbelt--root--"]')).boxShadow`),
            /rgba\(0, 0, 0, 0\.25\) 0px 3px 12px 0px/, 'The toolbox keeps its native outer shadow')
        assert.doesNotMatch(await js(`getComputedStyle(document.querySelector('[data-testid="navigation-bar"]')).boxShadow`), /inset/,
            'The navigation rail does not add a shadow at the shared seam')
        await js(`{const right=document.createElement('div');right.dataset.testid='properties-panel';right.style.cssText='position:absolute;right:20px;top:20px;width:240px;height:400px;z-index:6';document.body.append(right);testOptions.sidebarShadowStrength=40;testOptions.sidebarShadowTransparency=65;sidebarAppearance(testOptions,stylesheet)}`)
        await settle()
        const rightShadow = await js(`getComputedStyle(document.querySelector('[data-testid="properties-panel"]')).boxShadow`)
        assert.match(rightShadow, /inset/)
        assert.match(rightShadow, /rgba\(0, 0, 0, 0\.35\) 0px 4px 16px 0px/, 'The inner shadow preserves the existing outer shadow')
        for (const [backdrop, glass, opacity] of [['canvas', true, 20], ['canvas', false, 20], ['desktop', false, 20], ['desktop', false, 100], ['canvas', true, 100]]) {
            await js(`testOptions.sidebarBackdrop='${backdrop}';testOptions.sidebarLiquidGlass.enabled=${glass};testOptions.opacity=${opacity};sidebarAppearance(testOptions,stylesheet)`)
            await settle()
            const menusEscape = await js(`(()=>{
                return ['[data-resketch-sidebar-join="end"]','[data-testid="properties-panel"]'].every(selector=>{
                    const panel=document.querySelector(selector),menu=document.createElement('div');
                    menu.setAttribute('role','menu');menu.style.cssText='position:absolute;left:-60px;top:80px;width:180px;height:90px;background:red;z-index:1000';
                    panel.append(menu);const bounds=menu.getBoundingClientRect();
                    const visible=document.elementFromPoint(bounds.left+30,bounds.top+20)===menu;
                    menu.remove();return visible;
                });
            })()`)
            assert.equal(menusEscape, true, `${backdrop}, glass=${glass}, opacity=${opacity}: menus remain clickable beyond sidebar and joined-panel edges`)
        }
        await js(`testOptions.sidebarBackdrop='canvas';testOptions.sidebarLiquidGlass.enabled=true;testOptions.opacity=20;sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        await js(`document.querySelector('[class*="left_panel_container--sizeContainer--"]').style.width='300px';__resketchSidebars.schedule()`)
        await settle()
        assert.equal((await state()).width, 332, 'The shared surface follows sidebar resizing')
        await js(`testOptions.floatingSidebars=false;testOptions.sidebarLiquidGlass.cornerRadius=37;sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        assert.equal(await js(`getComputedStyle(document.querySelector('[data-resketch-shared-sidebar]')).borderTopLeftRadius`), '0px', 'Docked combined sidebar stays square with glass')
        assert.equal(await js(`getComputedStyle(document.querySelector('[class*="toolbelt--root--"]')).borderTopLeftRadius`), '9px', 'Toolbox keeps its native radius')
        await js(`testOptions.sidebarLiquidGlass.cornerRadius=70;sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        assert.equal(await js(`getComputedStyle(document.querySelector('[data-resketch-shared-sidebar]')).borderTopLeftRadius`), '0px')
        await js(`testOptions.floatingSidebars=true;sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        assert.equal(await js(`getComputedStyle(document.querySelector('[data-resketch-shared-sidebar]')).borderTopLeftRadius`), '70px', 'Floating radius still follows the setting')
        assert.equal(await js(`getComputedStyle(document.querySelector('[class*="toolbelt--root--"]')).borderTopLeftRadius`), '9px')
        await js(`testOptions.sidebarLiquidGlass.enabled=false;sidebarAppearance(testOptions,stylesheet)`)
        await settle()
        assert.equal((await state()).group, 'blur(15px)', 'Plain blur also uses the combined backdrop')
        assert.equal((await state()).filters, 0)
        assert.doesNotMatch(await js(`getComputedStyle(document.querySelector('[data-resketch-shared-sidebar]')).boxShadow`), /inset/,
            'Disabling glass removes the inner shadow')
        await js(`document.querySelector('[class*="left_panel_container--sizeContainer--"]').style.display='none';__resketchSidebars.schedule()`)
        await settle()
        assert.equal((await state()).visible, 'none', 'Collapsing the layers panel removes the shared surface')
        await js(`testOptions.floatingSidebars=false;testOptions.translucentSidebars=false;sidebarAppearance(testOptions,stylesheet)`)
        assert.equal(await js(`!!document.querySelector('[data-resketch-shared-sidebar]')`), false)
        console.log('Shared sidebar backdrop: current wrappers, one filter, resizing, plain blur, collapse and cleanup passed')
    } finally { socket.close() }
}
check().catch(error => { console.error(error); process.exitCode = 1 })
