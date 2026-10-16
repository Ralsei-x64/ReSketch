// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

function validColor(color) { return /^#[0-9a-f]{6}$/i.test(color || "") }
function channels(color) { return [1, 3, 5].map(offset => parseInt(color.slice(offset, offset + 2), 16)) }
function mix(background, foreground, amount) {
    const bg = channels(background), fg = channels(foreground)
    return "#" + bg.map((value, index) => Math.round(value + (fg[index] - value) * amount)
                       .toString(16).padStart(2, "0")).join("")
}
function luminance(color) {
    const rgb = channels(color).map(value => {
        value /= 255
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    })
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
}
function contrast(foreground, background) {
    const fg = luminance(foreground), bg = luminance(background)
    return (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05)
}
function readable(foreground, background, minimum) {
    const target = luminance(background) < 0.179 ? "#ffffff" : "#000000"
    for (let step = 0; step <= 10; ++step) {
        const color = mix(foreground, target, step / 10)
        if (contrast(color, background) >= minimum) return color
    }
    return target
}

// Only full-page loaders; leave loading bars, logos and skeleton details intact.
function loadingCss(opacity) {
    if (opacity >= 100) return ""
    const loader = '#loading-page-container, #filebrowser-loading-page:not(.hidden):not(.fadeOut), '
                 + '[class*="progress_bar--progressBarPageCover--"], '
                 + '[class*="progress_bar--progressBarPageFade--"], '
                 + '[class*="progress_bar--progressBarCover"]'
    return loader + ', :has(:is(' + loader + ')) { background:transparent !important; }'
        + 'body:has(:is(' + loader + ')) #resketch-sidebar-underlay { background:transparent !important; }'
        + 'body:has(:is(' + loader + ')) .gpu-view-content { visibility:hidden !important; }'
        + '#filebrowser-loading-page:not(.hidden):not(.fadeOut) .filebrowser-loading-page-layout, '
        + '#filebrowser-loading-page:not(.hidden):not(.fadeOut) .fb-sidebar, '
        + '#filebrowser-loading-page:not(.hidden):not(.fadeOut) .navbar '
        + '{ background:transparent !important; }'
}

// Figma distinguishes subtle selections from solid active tools/buttons.
// Keep these semantic roles paired, leaving document/canvas and status colors alone.
function paletteCss(palette) {
    const color = (role, fallback) => validColor(palette[role]) ? palette[role] : fallback
    const bg = color("window", "#ffffff")
    const text = readable(color("text", "#000000"), bg, 4.5)
    // Keep KDE's input color related to the window surface instead of stark white.
    const base = mix(bg, color("base", bg), 0.25)
    const accent = color("accent", color("link", text))
    const onAccent = readable(color("accentText", text), accent, 4.5)
    const accentHover = mix(accent, luminance(onAccent) < 0.179 ? "#ffffff" : "#000000", 0.12)
    const accentPressed = mix(accent, luminance(onAccent) < 0.179 ? "#ffffff" : "#000000", 0.24)
    const selected = mix(bg, accent, 0.18)
    const selectedHover = mix(bg, accent, 0.27)
    const selectedText = readable(text, selectedHover, 4.5)
    const link = readable(color("link", accent), selectedHover, 4.5)
    const tokens = {}
    const set = (value, names) => names.forEach(name => { tokens[name] = value })

    for (const context of ["", "-menu", "-toolbar", "-tooltip"]) {
        const surface = context === "-tooltip" ? color("tooltip", bg) : bg
        const foreground = context === "-tooltip" ? readable(color("tooltipText", text), surface, 4.5) : text
        const secondary = readable(color("secondaryText", mix(surface, foreground, 0.65)), surface, 4.5)
        const tertiary = readable(color("secondaryText", mix(surface, foreground, 0.5)), surface, 3)
        const disabled = color("disabledText", mix(surface, foreground, 0.4))
        set(surface, ["bg" + context])
        set(context === "" ? base : mix(surface, foreground, 0.04), ["bg" + context + "-secondary"])
        set(mix(surface, foreground, 0.12), ["bg" + context + "-tertiary"])
        set(mix(surface, foreground, 0.08), ["bg" + context + "-hover"])
        set(mix(surface, foreground, 0.16), ["bg" + context + "-pressed"])
        set(mix(surface, foreground, 0.12), ["bg" + context + "-disabled"])
        const border = readable(color("border", mix(surface, foreground, 0.3)), surface, 1.6)
        set(border, ["border" + context, "border" + context + "-disabled"])
        if (!context) set(border, ["bordertranslucent"])
        set(mix(surface, foreground, 0.65), ["border" + context + "-strong", "border" + context + "-disabled-strong"])
        set(accent, ["border" + context + "-selected", "border" + context + "-selected-strong"])
        if (context) {
            set(accent, ["bg" + context + "-selected"])
            set(accentHover, ["bg" + context + "-selected-hover"])
            set(accentPressed, ["bg" + context + "-selected-pressed"])
            set(selected, ["bg" + context + "-selected-secondary", "bg" + context + "-selected-tertiary"])
            set(mix(accent, onAccent, 0.35), ["border" + context + "-onselected"])
            set(onAccent, ["border" + context + "-onselected-strong"])
        }
        for (const type of ["text", "icon"]) {
            const prefix = type + context
            set(foreground, [prefix, prefix + "-hover", prefix + "-secondary-hover", prefix + "-tertiary-hover"])
            set(secondary, [prefix + "-secondary"])
            set(tertiary, [prefix + "-tertiary"])
            set(disabled, [prefix + "-disabled"])
            set(readable(foreground, mix(surface, foreground, 0.12), 3), [prefix + "-ondisabled"])
            set(link, [prefix + "-selected", prefix + "-selected-secondary", prefix + "-selected-tertiary"])
            set(context ? onAccent : selectedText, [prefix + "-onselected"])
            if (type === "icon") set(link, [prefix + "-pressed"])
        }
    }
    set(selected, ["bg-selected", "bg-brand-tertiary"])
    set(selectedHover, ["bg-selected-hover", "bg-selected-pressed", "bg-onselected", "bg-onselected-hover", "bg-onselected-pressed", "bg-brand-tertiary-hover", "bg-brand-tertiary-pressed"])
    set(mix(bg, accent, 0.1), ["bg-selected-secondary", "bg-selected-tertiary"])
    set(accent, ["bg-selected-strong", "bg-brand"])
    set(accent, ["loading-progress-bar"])
    set(mix(bg, text, 0.16), ["loading-progress-wrapper"])
    set(accentHover, ["loading-progress-accent"])
    set(accentHover, ["bg-brand-hover"])
    set(accentPressed, ["bg-brand-pressed", "bg-brand-secondary"])
    set(mix(base, text, 0.08), ["bg-secondary-hover"])
    set(mix(base, text, 0.16), ["bg-secondary-pressed", "bg-disabled-secondary"])
    set(mix(bg, text, 0.04), ["bg-elevated"])
    set(mix(bg, text, 0.1), ["bg-elevated-hover"])
    set(mix(bg, text, 0.08), ["bgtoolbarmodeswitcher"])
    set(accent, ["bg-strong-hover", "bg-strong-pressed"])
    set(mix(bg, accent, 0.4), ["border-brand", "border-onselected"])
    set(accent, ["border-brand-strong"])
    set(mix(accent, onAccent, 0.35), ["border-onbrand"])
    set(onAccent, ["border-onbrand-strong"])
    set(selectedText, ["border-onselected-strong"])
    for (const type of ["text", "icon"]) {
        set(link, [type + "-brand", type + "-brand-secondary", type + "-brand-tertiary", type + "-brand-pressed"])
        set(onAccent, [type + "-onbrand", type + "-onselected-strong"])
        set(readable(mix(accent, onAccent, 0.8), accent, 4.5), [type + "-onbrand-secondary", type + "-onbrand-tertiary"])
        set(readable(mix(selectedHover, selectedText, 0.7), selectedHover, 4.5), [type + "-onselected-secondary"])
        set(readable(mix(selectedHover, selectedText, 0.5), selectedHover, 3), [type + "-onselected-tertiary"])
    }
    const declarations = Object.keys(tokens).map(name => "--color-" + name + ":" + tokens[name] + " !important;")
    return ":root, body, [data-preferred-theme] {" + declarations.join("") + "}"
        // Use Figma's existing reset layer to beat Chromium's ButtonText
        // without overriding its higher-layer semantic control colors.
        + '@layer reset {'
        + ':where(button,input,select,textarea) { color:var(--color-text); }'
        + ':where(button,input,select,textarea):where(:disabled,[aria-disabled="true"]) { color:var(--color-text-disabled); } }'
        + '[class*="page_tracker_upsell--progressPartial--"]:not([class*="progressCompleteWarning--"],[class*="progressCompleteDanger--"]), '
        + '[class*="block_kit_row--unreadDotStructuredView--"] { background-color:var(--color-bg-brand) !important; }'
        + '[class*="user_notifications_dropdown--markAllReadButton--"] { color:' + readable(accent, bg, 4.5) + ' !important; }'
        // Recents cards use Figma's card primitive, including its main-action marker.
        + '[class*="tiles_view--container--"] [data-fpl-component="primitive"]:has(> [data-card-main-action]) {'
        + '--color-text:' + readable(text, bg, 8) + ' !important;'
        + '--color-text-secondary:' + readable(tokens["text-secondary"], bg, 5) + ' !important; }'
        // These primitives inherit browser button colors instead of semantic text roles.
        + '[class*="sidebar_row--sidebarRowSelected--"], [class*="legacy_pages_panel--pageRowActive--"] { background:var(--color-bg-selected) !important; color:var(--color-text-onselected) !important; outline:1px solid var(--color-border-selected) !important; }'
        + '[class*="sidebar_row--sidebarRowSelected--"] { --color-icon:var(--color-icon-onselected) !important; }'
        + '[data-testid="navigation-bar"] button[aria-expanded="true"] > div { background:var(--color-bg-selected-strong) !important; color:var(--color-text-onselected-strong) !important; --color-icon:var(--color-icon-onselected-strong) !important; }'
        + '[data-testid="file-icon"] { --color-icon:var(--color-icon-onbrand) !important; }'
}

// Canvas scrollbars are rendered by Figma, rather than browser scroll containers.
// Its native renderer reads this capability during initialization.
function canvasScrollbarsScript(hidden) {
    if (!hidden) return "";
    return `(function() {
        if (!/(^|\\.)figma\\.com$/.test(location.hostname)
                || !/^\\/(file|design|board|proto|slides|deck|site|buzz|make)\\/[^/]+/i.test(location.pathname)) return;
        let chunks, patched = false;
        function intercept(array) {
            let push = array.push;
            Object.defineProperty(array, 'push', {
                configurable:true,
                get() {
                    // Capture this handler so webpack can retain its parent push.
                    const original = push;
                    return function(...entries) {
                        if (!patched) for (const entry of entries) {
                            const modules = entry?.[1];
                            if (!modules) continue;
                            for (const id of Object.keys(modules)) {
                                const factory = modules[id];
                                if (typeof factory !== 'function' || factory.resketchScrollbarHook
                                        || !factory.toString().includes('appCanRenderScrollbars')) continue;
                                const wrapped = function(module, exports, runtime) {
                                    factory.call(this, module, exports, runtime);
                                    const app = Object.values(module.exports).find(value => typeof value === 'function'
                                        && typeof value.prototype?.appCanRenderScrollbars === 'function');
                                    if (app) {
                                        app.prototype.appCanRenderScrollbars = () => false;
                                        patched = window.__resketchCanvasScrollbarsHidden = true;
                                    }
                                };
                                wrapped.resketchScrollbarHook = true;
                                modules[id] = wrapped;
                            }
                        }
                        return original.apply(this, entries);
                    };
                },
                set(value) { push = value; }
            });
        }
        Object.defineProperty(window, 'rspackChunk_figma_web_bundler', {
            configurable:true,
            get() { return chunks; },
            set(value) { chunks = value; if (Array.isArray(value)) intercept(value); }
        });
    })()`;
}

// Cut holes in opaque page/canvas backgrounds without changing Figma's layout.
var sidebarMaskSource = `function sidebarMask(bounds, panels, viewport = bounds) {
    const rounded = panels.some(panel => panel.radius > 0);
    const x = viewport.left - bounds.left, y = viewport.top - bounds.top;
    const right = x + viewport.width, bottom = y + viewport.height;
    const origin = x + 'px ' + y + 'px';
    const paths = ['M' + x + ' ' + y + ' H' + right + ' V' + bottom + ' H' + x + ' Z'];
    const points = [origin, right + 'px ' + y + 'px', right + 'px ' + bottom + 'px', x + 'px ' + bottom + 'px', origin];
    let holes = 0;
    for (const panel of panels) {
        const left = Math.max(viewport.left, panel.left) - bounds.left;
        const top = Math.max(viewport.top, panel.top) - bounds.top;
        const right = Math.min(viewport.left + viewport.width, panel.right) - bounds.left;
        const bottom = Math.min(viewport.top + viewport.height, panel.bottom) - bounds.top;
        if (right <= left || bottom <= top) continue;
        if (rounded) {
            const x = panel.left - bounds.left, y = panel.top - bounds.top;
            const w = panel.right - panel.left, h = panel.bottom - panel.top;
            const r = Math.max(0, Math.min(panel.radius || 0, w / 2, h / 2));
            paths.push('M' + (x + r) + ' ' + y + ' H' + (x + w - r)
                + ' A' + r + ' ' + r + ' 0 0 1 ' + (x + w) + ' ' + (y + r)
                + ' V' + (y + h - r) + ' A' + r + ' ' + r + ' 0 0 1 ' + (x + w - r) + ' ' + (y + h)
                + ' H' + (x + r) + ' A' + r + ' ' + r + ' 0 0 1 ' + x + ' ' + (y + h - r)
                + ' V' + (y + r) + ' A' + r + ' ' + r + ' 0 0 1 ' + (x + r) + ' ' + y + ' Z');
        }
        points.push(left + 'px ' + top + 'px', right + 'px ' + top + 'px', right + 'px ' + bottom + 'px', left + 'px ' + bottom + 'px', left + 'px ' + top + 'px', origin);
        ++holes;
    }
    return !holes ? 'none' : rounded ? 'path(evenodd, "' + paths.join(' ') + '")'
        : 'polygon(evenodd, ' + points.join(', ') + ')';
}`

// Figma's canvas has its own native layout: CSS cannot resize its render buffer
// or pointer coordinates. Scope the collapsed-panel flags to that layout call,
// restoring them synchronously before React observes any UI changes.
var sidebarLayoutSource = `function floatingCanvasLayout() {
    const runtime = window.__resketchAppearance?.runtime;
    const factory = window._fullscreen_?._getTsApisForWasm?.().FigmaAppUi;
    if (!runtime || !factory) return null;
    try {
        let engine, caller = '';
        for (const id of Object.keys(runtime.m)) {
            const source = runtime.m[id].toString();
            if (source.includes('__getProperty_leftPanelCollapsed'))
                engine = Object.values(runtime(id)).find(value => value && typeof value === 'object'
                    && typeof value.uiState === 'function' && typeof value.editorPreferences === 'function');
            if (source.includes('updateLayoutForMinimizeUI') && (!caller || source.length < caller.length)) caller = source;
        }
        let api;
        for (const match of caller.matchAll(/\\((\\d+)\\)/g)) {
            if (!runtime.m[match[1]]) continue;
            api = Object.values(runtime(match[1])).find(value => value
                && typeof value.updateLayoutForMinimizeUI === 'function');
            if (api) break;
        }
        const proto = Object.getPrototypeOf(factory());
        const state = engine?.uiState();
        if (!api || typeof proto.getLeftRailWidth !== 'function'
                || !state?.leftPanelCollapsed?.set || !state?.showPropertiesPanel?.set) return null;
        const original = api.updateLayoutForMinimizeUI, originalRail = proto.getLeftRailWidth;
        const noRail = () => 0;
        let updating = false;
        function update(...args) {
            if (updating) return original.apply(this, args);
            updating = true;
            const ui = engine.uiState();
            const left = ui.leftPanelCollapsed.getCopy(), right = ui.showPropertiesPanel.getCopy();
            try {
                ui.leftPanelCollapsed.set(true);
                ui.showPropertiesPanel.set(false);
                return original.apply(this, args);
            } finally {
                ui.leftPanelCollapsed.set(left);
                ui.showPropertiesPanel.set(right);
                updating = false;
            }
        }
        proto.getLeftRailWidth = noRail;
        api.updateLayoutForMinimizeUI = update;
        return {update: () => update.call(api), dispose() {
            if (api.updateLayoutForMinimizeUI === update) api.updateLayoutForMinimizeUI = original;
            if (proto.getLeftRailWidth === noRail) proto.getLeftRailWidth = originalRail;
            original.call(api);
        }};
    } catch (_) { return null; }
}`

var sidebarSource = sidebarLayoutSource + `;function floatingFilePage() {
    return /^\\/(file|design|board|proto|slides|deck|site|buzz|make)\\/[^/]+/i.test(location.pathname);
}
function sidebarAppearance(options, stylesheet) {
    options = {...options, opacity: options.sidebarBackdrop === 'canvas' && Number.isFinite(options.sidebarCanvasOpacity)
        ? options.sidebarCanvasOpacity : options.opacity};
    let controller = window.__resketchSidebars;
    if (!options.floatingSidebars && (!options.translucentSidebars || options.opacity >= 100)) {
        controller?.dispose();
        delete window.__resketchSidebars;
        stylesheet('resketch-sidebars', '');
        return;
    }
    if (controller) {
        controller.options = options;
        controller.schedule();
        return;
    }
    const selector = '[data-testid="navigation-bar"], [data-onboarding-key="unified-design-onboarding-left-panel"], [data-testid="properties-panel"], [class*="left_panel_container--sizeContainer--"]:not(:has([data-onboarding-key="unified-design-onboarding-left-panel"])), [class*="sidebar--navDefault--"], .fb-sidebar';
    // Comments and collaborator cursors are separate from the WebGL canvas.
    const commentSelector = '[class*="comments_view--outerAnchorContainer--"], [class*="multiplayer_cursors--root--"], [class*="viewport_overlay--overflowContainer--"]';
    let panels = [], ancestors = new Set(), canvases = [], comments = [], frame = 0;
    let layout = null;
    const authoredSizes = new WeakMap();
    const authoredSize = panel => panel.style.width + ':' + panel.style.height;
    const canvasSizes = new WeakMap();
    const canvasSize = node => ['inset','width','height','left','right','top','bottom','transform']
        .map(name => node.style[name]).join(':');
    const underlay = document.createElement('div');
    underlay.id = 'resketch-sidebar-underlay';
    document.body.prepend(underlay);
    stylesheet('resketch-sidebars',
        '[data-resketch-sidebar], [data-resketch-sidebar] [data-preferred-theme] { --color-bg:var(--resketch-sidebar-content) !important; }'
        + '[data-resketch-sidebar] { background-color:var(--resketch-sidebar-tint) !important; backdrop-filter:var(--resketch-sidebar-blur) !important; }'
        + '[data-resketch-floating-sidebar] { box-sizing:border-box !important;'
        + 'width:var(--resketch-sidebar-width) !important; min-width:0 !important; max-width:none !important;'
        + 'height:var(--resketch-sidebar-height) !important; min-height:0 !important;'
        + 'border:1px solid var(--color-border) !important;'
        + 'margin:var(--resketch-sidebar-gap-vertical) var(--resketch-sidebar-gap-right) var(--resketch-sidebar-gap-vertical) var(--resketch-sidebar-gap-left) !important; border-radius:var(--resketch-sidebar-radius) !important; overflow:hidden !important; }'
        + '[data-resketch-sidebar-join="start"] { border-right:1px solid var(--color-border) !important; border-radius:var(--resketch-sidebar-radius) 0 0 var(--resketch-sidebar-radius) !important; }'
        + '[data-resketch-sidebar-join="end"] { border-left:0 !important; border-radius:0 var(--resketch-sidebar-radius) var(--resketch-sidebar-radius) 0 !important; }'
        + '[data-resketch-floating-sidebar] :is([class*="left_panel_container--panel--"],[class*="properties_panel--panelPosition--"]) '
        + '{ box-sizing:border-box !important; width:100% !important; height:100% !important; border:0 !important; }'
        + '[data-resketch-floating-sidebar] [class*="properties_panel--panelContainer--"] { border-left:0 !important; }'
        + '[data-resketch-floating-sidebar] [class*="comments_sidebar--container--"] { width:100% !important; min-width:0 !important; }'
        + '[data-resketch-floating-sidebar][class*="sidebar--navDefault--"] > *, '
        + '[data-resketch-floating-sidebar][class*="sidebar--navDefault--"] .fb-sidebar { box-sizing:border-box !important; width:100% !important; }'
        + '[data-resketch-floating-sidebar]:is([data-onboarding-key="unified-design-onboarding-left-panel"],[class*="left_panel_container--sizeContainer--"]) { position:relative !important; }'
        + '[data-resketch-floating-sidebar] > .data-fullscreen-prevent-event-capture { top:0 !important; height:100% !important; left:auto !important; right:0 !important; }'
        + '[data-resketch-floating-sidebar][data-testid="properties-panel"] > .data-fullscreen-prevent-event-capture { left:0 !important; right:auto !important; }'
        // Figma forces its TreeGrid action fade to alpha 1, turning transparent
        // sidebar colors black. Keep the original color's alpha at the fade end.
        + '[data-resketch-sidebar] :is(.ublpttv, .ublptty), '
        + '[data-resketch-sidebar] .ublptt9[data-fpl-has-trail]:hover .ublpttw:before '
        + '{ background:linear-gradient(90deg, rgb(from var(--ublptt0) r g b / 0) 0, var(--ublptt0) 10px) !important; }'
        // Floating Home popups need their own opaque surface, even inside a
        // translucent sidebar. Their headers and rows inherit this background.
        + '[data-resketch-sidebar] :is([data-testid="facetedSearchModal"], [class*="user_notifications_dropdown--dropdownContainer--"]), '
        + '[data-resketch-sidebar] :is([data-testid="facetedSearchModal"], [class*="user_notifications_dropdown--dropdownContainer--"]) [data-preferred-theme] '
        + '{ --color-bg:var(--resketch-sidebar-surface) !important; }'
        + '[data-resketch-sidebar] [class*="user_notifications_dropdown--dropdownContainer--"] '
        + '{ background:var(--resketch-sidebar-surface) !important; border:1px solid var(--color-border); }'
        + '[data-resketch-sidebar-ancestor] { background-color:transparent !important; }'
        + '[data-resketch-sidebar-canvas] { clip-path:var(--resketch-sidebar-clip) !important; }'
        + '#resketch-sidebar-underlay { position:fixed; inset:0; z-index:-1; pointer-events:none; }');
    function clear() {
        for (const panel of panels) {
            panel.removeAttribute('data-resketch-sidebar');
            panel.removeAttribute('data-resketch-floating-sidebar');
            panel.removeAttribute('data-resketch-sidebar-join');
            for (const name of ['tint','surface','content','blur','width','height','gap-left','gap-right','gap-vertical','radius'])
                panel.style.removeProperty('--resketch-sidebar-' + name);
        }
        for (const ancestor of ancestors) ancestor.removeAttribute('data-resketch-sidebar-ancestor');
        for (const canvas of canvases.concat(comments)) {
            canvas.removeAttribute('data-resketch-sidebar-canvas');
            canvas.style.removeProperty('--resketch-sidebar-clip');
        }
        ancestors.clear();
    }
    function update() {
        frame = 0;
        clear();
        const options = {...controller.options, floatingSidebars:controller.options.floatingSidebars && floatingFilePage()};
        const canvasBehind = floatingFilePage() && (options.floatingSidebars
            || options.translucentSidebars && options.sidebarBackdrop === 'canvas' && options.opacity < 100);
        if (!canvasBehind && layout) { layout.dispose(); layout = null; }
        const canvasView = document.querySelector('.gpu-view-content');
        if (canvasBehind && canvasView) {
            layout ||= floatingCanvasLayout();
            const bounds = canvasView.getBoundingClientRect();
            if (bounds.left > 1 || Math.abs(bounds.width - innerWidth) > 1) layout?.update();
        }
        const found = Array.from(document.querySelectorAll(selector));
        const next = found.filter(panel => !found.some(other => other !== panel && other.contains(panel)));
        for (const panel of panels) if (!next.includes(panel)) resize.unobserve(panel);
        for (const panel of next) if (!panels.includes(panel)) resize.observe(panel);
        panels = next;
        observer.disconnect();
        observer.observe(document.body, {childList:true, subtree:true});
        for (const panel of panels) observer.observe(panel, {attributes:true, attributeFilter:['style']});
        canvases = Array.from(document.querySelectorAll('.gpu-view-content'));
        comments = canvasBehind ? Array.from(document.querySelectorAll(commentSelector)) : [];
        // Native layout can move the canvas after updating the panel flags.
        // Watch its actual layout, ignoring our mask variables to avoid a loop.
        for (const canvas of canvases.concat(comments)) for (let node = canvas; node && node !== document.body; node = node.parentElement) {
            canvasSizes.set(node, canvasSize(node));
            observer.observe(node, {attributes:true, attributeFilter:['style']});
        }
        const active = options.floatingSidebars || options.translucentSidebars && options.opacity < 100;
        underlay.style.display = active ? "" : "none";
        if (!active) return;
        const bg = getComputedStyle(document.body).getPropertyValue('--color-bg').trim() || (options.theme === 'dark' ? '#2c2c2c' : '#ffffff');
        // Desktop tint is already drawn by the native window background.
        // Applying it again here makes 85% opacity effectively 98%.
        const translucent = (options.translucentSidebars || options.floatingSidebars) && options.opacity < 100
            && (options.sidebarBackdrop !== 'canvas' || floatingFilePage());
        const tint = !translucent ? bg : options.sidebarBackdrop === 'desktop' ? 'transparent'
            : 'color-mix(in srgb, ' + bg + ' ' + options.opacity + '%, transparent)';
        const rail = panels.find(panel => panel.matches('[data-testid="navigation-bar"]'));
        const leftPanel = panels.find(panel => panel.matches('[data-onboarding-key="unified-design-onboarding-left-panel"]'));
        const railBounds = rail?.getBoundingClientRect(), leftBounds = leftPanel?.getBoundingClientRect();
        const joined = options.floatingSidebars && railBounds?.width && leftBounds?.width
            && Math.abs(railBounds.right - leftBounds.left) < 3;
        underlay.style.backgroundColor = (options.floatingSidebars || options.sidebarBackdrop === 'canvas') && canvases.length
            ? getComputedStyle(canvases[0]).backgroundColor : bg;
        for (const panel of panels) {
            authoredSizes.set(panel, authoredSize(panel));
            panel.style.setProperty('--resketch-sidebar-tint', tint);
            panel.style.setProperty('--resketch-sidebar-surface', bg);
            panel.style.setProperty('--resketch-sidebar-content', translucent ? 'transparent' : bg);
            panel.style.setProperty('--resketch-sidebar-blur', translucent && options.sidebarBackdrop === 'canvas'
                && options.sidebarCanvasBlur > 0 ? 'blur(' + options.sidebarCanvasBlur + 'px)' : 'none');
            const bounds = panel.getBoundingClientRect();
            if (options.floatingSidebars && bounds.width && bounds.height) {
                const margin = options.sidebarMargin;
                const gap = bounds.width < 100 ? margin / 2 : margin;
                const gapLeft = joined && panel === leftPanel ? 0 : joined && panel === rail ? margin : gap;
                const gapRight = joined && panel === rail ? 0 : gap;
                panel.style.setProperty('--resketch-sidebar-width', Math.max(1, bounds.width - gapLeft - gapRight) + 'px');
                panel.style.setProperty('--resketch-sidebar-height', Math.max(1, bounds.height - 2 * margin) + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-vertical', margin + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-left', gapLeft + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-right', gapRight + 'px');
                panel.style.setProperty('--resketch-sidebar-radius', options.sidebarCornerRadius + 'px');
                panel.setAttribute('data-resketch-floating-sidebar', '');
                if (joined && (panel === rail || panel === leftPanel))
                    panel.setAttribute('data-resketch-sidebar-join', panel === rail ? 'start' : 'end');
            }
            panel.setAttribute('data-resketch-sidebar', '');
            for (let node = panel.parentElement; node; node = node.parentElement) ancestors.add(node);
        }
        for (const ancestor of ancestors) ancestor.setAttribute('data-resketch-sidebar-ancestor', '');
        const rects = panels.filter(panel => !joined || panel !== leftPanel).map(panel => {
            const bounds = panel.getBoundingClientRect();
            const right = joined && panel === rail ? leftPanel.getBoundingClientRect().right : bounds.right;
            return {left:bounds.left, top:bounds.top, right, bottom:bounds.bottom,
                    radius:options.floatingSidebars ? options.sidebarCornerRadius : 0};
        }).filter(rect => rect.right > rect.left && rect.bottom > rect.top);
        underlay.style.clipPath = options.sidebarBackdrop === 'desktop'
            ? sidebarMask({left:0, top:0, width:innerWidth, height:innerHeight}, rects) : 'none';
        for (const canvas of (options.sidebarBackdrop === 'desktop' ? canvases : []).concat(comments)) {
            // Figma keeps some overlay bounds inset even after the canvas fills
            // the window. Pins can overflow those bounds, so clip the viewport.
            const viewport = comments.includes(canvas)
                ? {left:0, top:0, width:innerWidth, height:innerHeight} : undefined;
            canvas.style.setProperty('--resketch-sidebar-clip', sidebarMask(canvas.getBoundingClientRect(), rects, viewport));
            canvas.setAttribute('data-resketch-sidebar-canvas', '');
        }
    }
    function schedule() { if (!frame) frame = requestAnimationFrame(update); }
    const resize = new ResizeObserver(schedule);
    const observer = new MutationObserver(records => {
        if (records.some(record => record.type === 'attributes'
            ? (panels.includes(record.target) && authoredSizes.get(record.target) !== authoredSize(record.target))
                || (canvasSizes.has(record.target) && canvasSizes.get(record.target) !== canvasSize(record.target))
            : [...record.addedNodes, ...record.removedNodes].some(node =>
            node.nodeType === 1 && (node.matches(selector + ', .gpu-view-content, ' + commentSelector) || node.querySelector(selector + ', .gpu-view-content, ' + commentSelector))))) schedule();
    });
    observer.observe(document.body, {childList:true, subtree:true});
    window.addEventListener('resize', schedule);
    controller = window.__resketchSidebars = {
        options, schedule,
        dispose() {
            cancelAnimationFrame(frame);
            resize.disconnect();
            observer.disconnect();
            window.removeEventListener('resize', schedule);
            clear();
            layout?.dispose();
            underlay.remove();
        }
    };
    schedule();
}`

var pageThemeSource = `function applyAppearance(options) {
    if (!/(^|\\.)figma\\.com$/.test(location.hostname) || !document.body) return;
    // Reuse the module/store lookup on theme changes and lifecycle resumes.
    const bridge = window.__resketchAppearance || (window.__resketchAppearance = {});
    clearTimeout(bridge.timer);
    bridge.observer?.disconnect();
    window.__resketchThemeObserver?.disconnect(); // Remove the old attribute-only synchronizer.
    let attempts = 0;
    // Figma's canvas input test recognizes input/textarea, but not Lexical's
    // contenteditable comments. Use its own keyboard opt-out for these editors.
    if (!bridge.textEditorsProtected) {
        const protect = node => {
            if (node?.matches?.('[data-lexical-editor="true"][contenteditable="true"]'))
                node.setAttribute('data-fullscreen-prevent-event-capture-keys', 'true');
        };
        document.addEventListener('focusin', event => protect(event.target), true);
        protect(document.activeElement);
        bridge.textEditorsProtected = true;
    }

    function nativeTheme() {
        try {
            if (!bridge.runtime && window.rspackChunk_figma_web_bundler) {
                window.rspackChunk_figma_web_bundler.push([
                    ["resketch-appearance"], {}, runtime => { bridge.runtime = runtime; }
                ]);
            }
            const runtime = bridge.runtime;
            if (!runtime) return false;
            const ids = Object.keys(runtime.m);
            if (!bridge.themeAction && bridge.moduleCount !== ids.length) {
                bridge.moduleCount = ids.length;
                const id = ids.find(id => {
                    const source = runtime.m[id].toString();
                    return source.includes("global-debug-theme-preference")
                        && source.includes("on-theme-update-ipc-key");
                });
                const module = id && runtime(id);
                // This is Figma's local theme update, which does not persist or
                // broadcast a preference to the user's other browser sessions.
                if (module?.D6 === "on-theme-update-ipc-key" && typeof module.id === "function")
                    bridge.themeAction = module.id;
            }
            if (!bridge.themeAction) return false;
            if (!bridge.store) bridge.store = menuStore();
            if (!bridge.store) return false;
            if (bridge.lastTheme !== options.theme
                    || document.body.getAttribute("data-preferred-theme") !== options.theme) {
                bridge.store.dispatch(bridge.themeAction({theme: options.theme}));
                bridge.lastTheme = options.theme;
            }
            return true;
        } catch (_) {
            return false;
        }
    }

    function stylesheet(id, css) {
        let style = document.getElementById(id);
        if (!css) {
            style?.remove();
            return;
        }
        if (!style) {
            style = document.createElement("style");
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
        }
        if (style.textContent !== css) style.textContent = css;
    }

    function apply() {
        const ready = nativeTheme();
        // Login and pages without the app runtime still support Figma's CSS theme.
        if (!ready) {
            if (document.body.getAttribute("data-preferred-theme") !== options.theme)
                document.body.setAttribute("data-preferred-theme", options.theme);
            document.body.style.colorScheme = options.theme;
        }
        document.documentElement.style.colorScheme = options.theme;
        sidebarAppearance(options, stylesheet);
        const custom = document.getElementById('resketch-custom-css');
        if (custom && custom.parentNode.lastChild !== custom) custom.parentNode.appendChild(custom);
        return ready;
    }

    stylesheet("resketch-system-colors", options.paletteCss);
    stylesheet("resketch-loading-background", options.loadingCss);
    stylesheet("resketch-custom-css", options.customCss);
    // Keep custom CSS after palette overrides when the palette is enabled later.
    const custom = document.getElementById("resketch-custom-css");
    if (custom) custom.parentNode.appendChild(custom);
    bridge.observer = new MutationObserver(apply);
    bridge.observer.observe(document.body, {attributes: true, attributeFilter: ["data-preferred-theme"]});
    function retry() {
        if (!apply() && ++attempts < 20) bridge.timer = setTimeout(retry, 500);
    }
    retry();
}`

function script(options, storeSource) {
    const settings = {
        theme: options.systemColors && validColor(options.palette?.window)
               ? luminance(options.palette.window) < 0.179 ? "dark" : "light"
               : options.dark ? "dark" : "light",
        paletteCss: options.systemColors ? paletteCss(options.palette || {}) : "",
        customCss: options.customCssEnabled ? options.customCss : "",
        loadingCss: loadingCss(Number.isFinite(options.opacity) ? options.opacity : 100),
        translucentSidebars: !!options.translucentSidebars,
        floatingSidebars: !!options.floatingSidebars,
        hideFloatingScrollbars: !!options.hideFloatingScrollbars,
        sidebarCornerRadius: Math.max(0, Math.min(40, Number.isFinite(options.sidebarCornerRadius) ? options.sidebarCornerRadius : 12)),
        sidebarMargin: Math.max(0, Math.min(40, Number.isFinite(options.sidebarMargin) ? options.sidebarMargin : 8)),
        sidebarBackdrop: options.sidebarBackdrop === "canvas" ? "canvas" : "desktop",
        sidebarCanvasBlur: Math.max(0, Math.min(40, Number.isFinite(options.sidebarCanvasBlur) ? options.sidebarCanvasBlur : 0)),
        sidebarCanvasOpacity: Math.max(0, Math.min(100, Number.isFinite(options.sidebarCanvasOpacity) ? options.sidebarCanvasOpacity
            : Number.isFinite(options.opacity) ? options.opacity : 100)),
        opacity: Math.max(0, Math.min(100, Number.isFinite(options.opacity) ? options.opacity : 100))
    }
    return "(function() {" + storeSource + ";" + sidebarMaskSource + ";" + sidebarSource
        + ";(" + pageThemeSource + ")(" + JSON.stringify(settings) + ");})()"
}
