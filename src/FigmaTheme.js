// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

function validColor(color) { return /^#[0-9a-f]{6}$/i.test(color || "") }
var toolboxSelector = '[class^="toolbelt--root--"],[class*=" toolbelt--root--"]'
function sidebarGestureHitTest(x, y) {
    if (!Number.isFinite(x) || !Number.isFinite(y)) return "'none'"
    return `(()=>{
        const node = document.elementFromPoint(${x}, ${y});
        if (node?.closest('input,textarea,select,[contenteditable="true"],[role="textbox"],[role="slider"],[role="spinbutton"],[role="menu"],[role="dialog"],[role="listbox"]')) return 'none';
        if (node?.closest(${JSON.stringify(toolboxSelector)})) return 'dock';
        if (node?.closest('.gpu-view-content')) return 'canvas';
        let verticalScroll = false;
        for (let parent = node; parent; parent = parent.parentElement) {
            const style = getComputedStyle(parent);
            if (['auto','scroll','overlay'].includes(style.overflowX) && parent.scrollWidth > parent.clientWidth + 1) return 'none';
            verticalScroll ||= ['auto','scroll','overlay'].includes(style.overflowY) && parent.scrollHeight > parent.clientHeight + 1;
        }
        if (verticalScroll) return 'scroll';
        const panel = node?.closest('[data-resketch-sidebar],[data-testid="navigation-bar"],[data-onboarding-key="unified-design-onboarding-left-panel"],[data-testid="properties-panel"],[class*="left_panel_container--sizeContainer--"],[class*="sidebar--navDefault--"],.fb-sidebar');
        if (!panel) return 'none';
        if (node.closest('button,a,input,textarea,select,label,svg,img,canvas,.ublptt9,[data-testid*="layer-row"],[data-testid*="layer_row"],[contenteditable="true"],[draggable="true"],[role="button"],[role="treeitem"],[role="row"],[role="gridcell"],[role="tab"],[role="checkbox"],[role="menuitem"],[role="menu"],[role="dialog"],[role="listbox"]')) return 'none';
        if (!['auto','default'].includes(getComputedStyle(node).cursor)) return 'none';
        return Array.from(node.childNodes).some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim()) ? 'none' : 'sidebar';
    })()`
}
function sidebarScrollbarsCss(hidden) {
    if (!hidden) return ""
    const panel = ':is([data-resketch-sidebar],[data-testid="navigation-bar"],[data-onboarding-key="unified-design-onboarding-left-panel"],[data-testid="properties-panel"],[class*="left_panel_container--sizeContainer--"],[class*="sidebar--navDefault--"],.fb-sidebar)'
    return panel + ', ' + panel + ' * { scrollbar-width:none !important; }'
        + panel + '::-webkit-scrollbar, ' + panel + ' *::-webkit-scrollbar { display:none !important; }'
}
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
var loaderSelectors = ['#loading-page-container', '#filebrowser-loading-page',
    '[class*="progress_bar--progressBarPageCover--"]', '[class*="progress_bar--progressBarPageFade--"]',
    '[class*="progress_bar--progressBarCover"]']
var loadingSelector = loaderSelectors.map(selector => selector
        + ':not(.hidden):not(.fadeOut):not([hidden]):not([style*="display: none"]):not([style*="display:none"])').join(', ')
function loadingCss(opacity) {
    if (opacity >= 100) return ""
    return '[data-resketch-loading-background] { background:transparent !important; }'
        + 'body[data-resketch-loading] #resketch-sidebar-underlay { background:transparent !important; }'
        + 'body[data-resketch-loading] .gpu-view-content { visibility:hidden !important; }'
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
                // Figma can retain an old pixel height on its outer window.
                // Stretch that window, then resize the renderer/input space too.
                const windowState = window._fullscreen_?.HTMLWindowBindings?.globalWindowState;
                if (windowState?.viewElement?.style && typeof windowState.updateSizeAndPixelRatio === 'function') {
                    windowState.viewElement.style.height = 'auto';
                    windowState.updateSizeAndPixelRatio();
                }
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

// Observe loader state directly. Document-wide :has() rules with style/class
// conditions otherwise invalidate Figma's entire UI on every canvas update.
var loadingSource = `function loadingAppearance() {
    if (window.__resketchLoading) return;
    const selector = ${JSON.stringify(loaderSelectors.join(', '))};
    const visible = ${JSON.stringify(loadingSelector)};
    let marked = new Set();
    function update() {
        const loaders = Array.from(document.querySelectorAll(selector));
        const next = new Set();
        for (const loader of loaders) if (loader.matches(visible))
            for (let node = loader; node; node = node.parentElement) next.add(node);
        for (const node of marked) if (!next.has(node)) node.removeAttribute('data-resketch-loading-background');
        for (const node of next) if (!marked.has(node)) node.setAttribute('data-resketch-loading-background', '');
        const loading = next.size > 0;
        if (document.body.hasAttribute('data-resketch-loading') !== loading)
            document.body.toggleAttribute('data-resketch-loading', loading);
        marked = next;
        observer.disconnect();
        observer.observe(document.body, {childList:true, subtree:true});
        for (const loader of loaders)
            observer.observe(loader, {attributes:true, attributeFilter:['class','style','hidden','id']});
    }
    const observer = new MutationObserver(records => {
        if (records.some(record => record.type === 'attributes'
            || [...record.addedNodes, ...record.removedNodes].some(node => node.nodeType === 1
                && (node.matches(selector) || node.querySelector(selector))))) update();
    });
    window.__resketchLoading = observer;
    update();
}`

function normalizedLiquidGlass(values) {
    values = values || {}
    const number = (key, fallback, minimum, maximum) => Math.max(minimum, Math.min(maximum,
        Number.isFinite(values[key]) ? Math.round(values[key]) : fallback))
    return {
        enabled: !!values.enabled,
        noiseStrength: number('noiseStrength', 0, 0, 100),
        brightness: number('brightness', 100, 0, 200),
        saturation: number('saturation', 180, 0, 300),
        contrast: number('contrast', 100, 0, 200),
        cornerRadius: number('cornerRadius', 15, 0, 80),
        refractionStrength: number('refractionStrength', 100, 0, 100),
        refractionMode: values.refractionMode === 'basic' ? 'basic' : 'concave',
        refractionEdgeSize: number('refractionEdgeSize', 30, 1, 200),
        refractionFalloff: number('refractionFalloff', 400, 1, 400),
        refractionCornerRadius: number('refractionCornerRadius', 15, 0, 200),
        rgbFringingStrength: number('rgbFringingStrength', 0, 0, 20),
        innerShadowX: number('innerShadowX', 0, -100, 100),
        innerShadowY: number('innerShadowY', 2, -100, 100),
        innerShadowScale: number('innerShadowScale', 12, 0, 100),
        innerShadowBrightness: number('innerShadowBrightness', 100, 0, 200),
        innerShadowStrength: number('innerShadowStrength', 0, 0, 100),
        innerShadowColor: validColor(values.innerShadowColor) ? values.innerShadowColor : '#000000'
    }
}

var liquidGlassSource = `function glassInnerShadow(glass) {
    if (glass.innerShadowStrength === 0) return '0 0 transparent';
    const color = [1, 3, 5].map(offset => Math.min(255,
        Math.round(parseInt(glass.innerShadowColor.slice(offset, offset + 2), 16) * glass.innerShadowBrightness / 100)));
    return 'inset ' + glass.innerShadowX + 'px ' + glass.innerShadowY + 'px ' + glass.innerShadowScale
        + 'px 0 rgba(' + color.join(',') + ',' + glass.innerShadowStrength / 100 + ')';
}
function glassDisplacement(x, y, width, height, glass) {
    const radius = Math.min(glass.refractionCornerRadius, width / 2, height / 2);
    const px = x - width / 2, py = y - height / 2;
    const qx = Math.abs(px) - width / 2 + radius, qy = Math.abs(py) - height / 2 + radius;
    const cx = Math.max(qx, 0), cy = Math.max(qy, 0), length = Math.hypot(cx, cy);
    const distance = length + Math.min(Math.max(qx, qy), 0) - radius;
    const edge = Math.pow(Math.max(0, 1 - Math.max(0, -distance) / glass.refractionEdgeSize),
                          glass.refractionFalloff / 100);
    const direction = glass.refractionMode === 'concave' ? -1 : 1;
    const nx = length > 0 ? cx / length : qx > qy ? 1 : 0;
    const ny = length > 0 ? cy / length : qx > qy ? 0 : 1;
    return [Math.sign(px) * nx * edge * direction, Math.sign(py) * ny * edge * direction];
}
function glassFilter(width, height, glass, id) {
    let markup = '<filter id="' + id + '" x="0" y="0" width="' + width + '" height="' + height
        + '" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">';
    let source = 'SourceGraphic';
    if (glass.refractionStrength > 0 || glass.rgbFringingStrength > 0) {
        const map = document.createElement('canvas');
        // ponytail: cap displacement textures at 512px; raise for finer edges on large panels.
        const ratio = Math.min(1, 512 / Math.max(width, height));
        map.width = Math.max(2, Math.ceil(width * ratio));
        map.height = Math.max(2, Math.ceil(height * ratio));
        const context = map.getContext('2d');
        const pixels = context.createImageData(map.width, map.height);
        for (let y = 0; y < map.height; ++y) for (let x = 0; x < map.width; ++x) {
            const vector = glassDisplacement((x + 0.5) * width / map.width,
                (y + 0.5) * height / map.height, width, height, glass);
            const offset = (y * map.width + x) * 4;
            pixels.data[offset] = Math.round(128 + 127 * vector[0]);
            pixels.data[offset + 1] = Math.round(128 + 127 * vector[1]);
            pixels.data[offset + 2] = 128;
            pixels.data[offset + 3] = 255;
        }
        context.putImageData(pixels, 0, 0);
        markup += '<feImage href="' + map.toDataURL() + '" x="0" y="0" width="' + width
            + '" height="' + height + '" preserveAspectRatio="none" result="mapImage"/>'
            // Make the quantized neutral value (128) exactly zero displacement.
            + '<feComponentTransfer in="mapImage" result="map"><feFuncR type="linear" intercept="-0.00196078431372549"/>'
            + '<feFuncG type="linear" intercept="-0.00196078431372549"/></feComponentTransfer>';
        const displacement = (name, strength) => '<feDisplacementMap in="SourceGraphic" in2="map" scale="'
            + strength * 255 / 127 + '" xChannelSelector="R" yChannelSelector="G" result="' + name + '"/>';
        if (glass.rgbFringingStrength > 0) {
            const channels = ['red', 'green', 'blue'];
            for (let channel = 0; channel < 3; ++channel) {
                const name = channels[channel];
                markup += displacement(name + 'Shift', glass.refractionStrength + (1 - channel) * glass.rgbFringingStrength);
                const matrix = Array(20).fill(0);
                matrix[channel * 6] = 1;
                matrix[18] = 1;
                markup += '<feColorMatrix in="' + name + 'Shift" type="matrix" values="' + matrix.join(' ')
                    + '" result="' + name + '"/>';
            }
            markup += '<feBlend in="red" in2="green" mode="screen" result="rg"/>'
                + '<feBlend in="rg" in2="blue" mode="screen" result="refracted"/>';
        } else markup += displacement('refracted', glass.refractionStrength);
        source = 'refracted';
    }
    if (glass.noiseStrength > 0) {
        markup += '<feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="3" seed="7" stitchTiles="stitch" result="noise"/>'
            + '<feColorMatrix in="noise" type="saturate" values="0"/>'
            + '<feComponentTransfer result="grain"><feFuncA type="linear" slope="' + glass.noiseStrength / 100 + '"/></feComponentTransfer>'
            + '<feBlend in="grain" in2="' + source + '" mode="soft-light"/>';
    } else if (source === 'SourceGraphic') markup += '<feOffset/>';
    return markup + '</filter>';
}`

var sidebarSource = sidebarLayoutSource + ';' + loadingSource + ';' + liquidGlassSource + `;function floatingFilePage() {
    return /^\\/(file|design|board|proto|slides|deck|site|buzz|make)\\/[^/]+/i.test(location.pathname);
}
function sidebarAppearance(options, stylesheet) {
    loadingAppearance();
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
    const minimized = '[class*="left_panel_island_container--islandContainer--"][class*="left_panel_island_container--collapsed--"], [class*="properties_panel--panelContainerCollapsed"]';
    const toolbox = ${JSON.stringify(toolboxSelector)};
    const selector = '[data-testid="navigation-bar"], [data-onboarding-key="unified-design-onboarding-left-panel"], [data-testid="properties-panel"]:not(:has([class*="properties_panel--panelContainerCollapsed"])), [class*="left_panel_container--sizeContainer--"]:not(:has([data-onboarding-key="unified-design-onboarding-left-panel"])), [class*="sidebar--navDefault--"], .fb-sidebar, ' + minimized + ', ' + toolbox;
    // Comments and collaborator cursors are separate from the WebGL canvas.
    const commentSelector = '[class*="comments_view--outerAnchorContainer--"], [class*="multiplayer_cursors--root--"], [class*="viewport_overlay--overflowContainer--"]';
    let panels = [], ancestors = new Set(), canvases = [], comments = [], frame = 0;
    let layout = null;
    const authoredSizes = new WeakMap();
    const authoredSize = panel => panel.style.width + ':' + panel.style.height;
    const canvasSizes = new WeakMap();
    const glassFilters = new WeakMap();
    let glassSerial = 0, filterSignature = '';
    const filterSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    filterSvg.id = 'resketch-glass-filters';
    filterSvg.setAttribute('style', 'position:absolute;width:0;height:0;pointer-events:none');
    document.body.prepend(filterSvg);
    const canvasSize = node => ['inset','width','height','left','right','top','bottom','transform']
        .map(name => node.style[name]).join(':');
    const underlay = document.createElement('div');
    underlay.id = 'resketch-sidebar-underlay';
    document.body.prepend(underlay);
    const sharedBackdrop = document.createElement('div');
    sharedBackdrop.setAttribute('data-resketch-shared-sidebar', '');
    sharedBackdrop.setAttribute('aria-hidden', 'true');
    sharedBackdrop.style.cssText = 'position:fixed;pointer-events:none;display:none';
    stylesheet('resketch-sidebars',
        'body[data-resketch-loading] :is(' + selector + ', [data-resketch-shared-sidebar]) { visibility:hidden !important; }'
        + '[data-resketch-sidebar], [data-resketch-sidebar] [data-preferred-theme] { --color-bg:var(--resketch-sidebar-content) !important; }'
        + '[data-resketch-sidebar] { background-color:var(--resketch-sidebar-tint) !important; backdrop-filter:var(--resketch-sidebar-blur) !important; }'
        + '[data-resketch-floating-sidebar] { box-sizing:border-box !important;'
        + 'width:var(--resketch-sidebar-width) !important; min-width:0 !important; max-width:none !important;'
        + 'height:var(--resketch-sidebar-height) !important; min-height:0 !important;'
        + 'border:1px solid var(--color-border) !important;'
        + 'box-shadow:var(--resketch-sidebar-shadow) !important;'
        + 'margin:calc(var(--resketch-sidebar-gap-vertical) + var(--resketch-sidebar-offset-top, 0px)) var(--resketch-sidebar-gap-right) var(--resketch-sidebar-gap-vertical) var(--resketch-sidebar-gap-left) !important; border-radius:var(--resketch-sidebar-radius) !important; overflow:visible !important; }'
        + '[data-resketch-shared-sidebar] { box-shadow:var(--resketch-sidebar-shadow, 0 0 transparent) !important; }'
        + '[data-resketch-liquid-glass] { '
        + 'box-shadow:var(--resketch-sidebar-inner-shadow, 0 0 transparent), var(--resketch-sidebar-outer-shadow, 0 0 transparent) !important; }'
        + '[data-resketch-sidebar-join="start"] { border-right:1px solid var(--color-border) !important; border-radius:var(--resketch-sidebar-radius) 0 0 var(--resketch-sidebar-radius) !important; }'
        + '[data-resketch-sidebar-join="end"] { border-left:0 !important; border-radius:0 var(--resketch-sidebar-radius) var(--resketch-sidebar-radius) 0 !important; }'
        + '[data-resketch-floating-sidebar] :is([class*="left_panel_container--panel--"],[class*="properties_panel--panelPosition--"]) '
        + '{ box-sizing:border-box !important; width:100% !important; height:100% !important; border:0 !important; }'
        + '[data-resketch-floating-sidebar] [class*="properties_panel--panelPosition--"] { top:0 !important; bottom:0 !important; }'
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
        sharedBackdrop.style.display = 'none';
        for (const panel of panels.concat(sharedBackdrop)) {
            panel.removeAttribute('data-resketch-sidebar');
            panel.removeAttribute('data-resketch-floating-sidebar');
            panel.removeAttribute('data-resketch-sidebar-join');
            panel.removeAttribute('data-resketch-liquid-glass');
            for (const name of ['tint','surface','content','blur','shadow','inner-shadow','outer-shadow','width','height','offset-top','gap-left','gap-right','gap-vertical','radius'])
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
            if (Math.abs(bounds.left) > 1
                    || Math.abs(bounds.right - innerWidth) > 1
                    || Math.abs(bounds.bottom - innerHeight) > 1) layout?.update();
        }
        const found = Array.from(document.querySelectorAll(selector));
        const next = found.filter(panel => !found.some(other => other !== panel && other.contains(panel)));
        for (const panel of panels) if (!next.includes(panel)) resize.unobserve(panel);
        for (const panel of next) if (!panels.includes(panel)) resize.observe(panel);
        panels = next;
        observer.disconnect();
        observer.observe(document.body, {childList:true, subtree:true});
        for (const panel of panels) observer.observe(panel, {attributes:true, attributeFilter:['style']});
        const nextCanvases = Array.from(document.querySelectorAll('.gpu-view-content'));
        for (const canvas of canvases) if (!nextCanvases.includes(canvas)) resize.unobserve(canvas);
        for (const canvas of nextCanvases) if (!canvases.includes(canvas)) resize.observe(canvas);
        canvases = nextCanvases;
        comments = canvasBehind ? Array.from(document.querySelectorAll(commentSelector)) : [];
        // Native layout can move the canvas after updating the panel flags.
        // Watch its actual layout, ignoring our mask variables to avoid a loop.
        for (const canvas of canvases.concat(comments)) for (let node = canvas; node && node !== document.body; node = node.parentElement) {
            canvasSizes.set(node, canvasSize(node));
            observer.observe(node, {attributes:true, attributeFilter:['style']});
        }
        const active = options.floatingSidebars || options.translucentSidebars && options.opacity < 100;
        underlay.style.display = active ? "" : "none";
        if (!active) {
            filterSvg.innerHTML = '';
            filterSignature = '';
            return;
        }
        const bg = getComputedStyle(document.body).getPropertyValue('--color-bg').trim() || (options.theme === 'dark' ? '#2c2c2c' : '#ffffff');
        // Desktop tint is already drawn by the native window background.
        // Applying it again here makes 85% opacity effectively 98%.
        const translucent = (options.translucentSidebars || options.floatingSidebars) && options.opacity < 100
            && (options.sidebarBackdrop !== 'canvas' || floatingFilePage());
        const tint = !translucent ? bg : options.sidebarBackdrop === 'desktop' ? 'transparent'
            : 'color-mix(in srgb, ' + bg + ' ' + options.opacity + '%, transparent)';
        const rail = panels.find(panel => panel.matches('[data-testid="navigation-bar"]'));
        const leftPanel = panels.find(panel => panel.matches('[data-onboarding-key="unified-design-onboarding-left-panel"], [class*="left_panel_container--sizeContainer--"]'));
        const railBounds = rail?.getBoundingClientRect(), leftBounds = leftPanel?.getBoundingClientRect();
        const joined = options.floatingSidebars && railBounds?.width && leftBounds?.width
            && Math.abs(railBounds.right - leftBounds.left) < 3;
        const strength = options.sidebarShadowStrength || 0;
        const shadow = strength > 0 && options.sidebarShadowTransparency < 100
            ? '0 ' + strength / 10 + 'px ' + strength * 0.4 + 'px rgba(0,0,0,'
                + (1 - options.sidebarShadowTransparency / 100) + ')' : '0 0 transparent';
        underlay.style.backgroundColor = (options.floatingSidebars || options.sidebarBackdrop === 'canvas') && canvases.length
            ? getComputedStyle(canvases[0]).backgroundColor : bg;
        const glass = options.sidebarLiquidGlass;
        const glassActive = translucent && options.sidebarBackdrop === 'canvas' && glass.enabled;
        const filters = [];
        for (const panel of panels) {
            authoredSizes.set(panel, authoredSize(panel));
            panel.style.setProperty('--resketch-sidebar-tint', tint);
            panel.style.setProperty('--resketch-sidebar-surface', bg);
            panel.style.setProperty('--resketch-sidebar-content', translucent ? 'transparent' : bg);
            panel.style.setProperty('--resketch-sidebar-blur', translucent && options.sidebarBackdrop === 'canvas'
                && options.sidebarCanvasBlur > 0 ? 'blur(' + options.sidebarCanvasBlur + 'px)' : 'none');
            const bounds = panel.getBoundingClientRect();
            // Minimized controls and the toolbox retain their native geometry.
            if (options.floatingSidebars && !panel.matches(minimized + ', ' + toolbox) && bounds.width && bounds.height) {
                const margin = options.sidebarMargin;
                const rightPanel = panel.matches('[data-testid="properties-panel"]');
                const position = rightPanel ? panel.querySelector('[class*="properties_panel--panelPosition--"]') : null;
                // Figma offsets the inner right panel for banners, while its
                // outer wrapper still spans the viewport. Apply that inset once.
                // The canvas offset is available even before panel CSS loads.
                const insetTop = rightPanel ? Math.max(0,
                    (position?.getBoundingClientRect().top ?? bounds.top) - bounds.top,
                    (canvasView?.getBoundingClientRect().top ?? bounds.top) - bounds.top) : 0;
                const gap = bounds.width < 100 ? margin / 2 : margin;
                const gapLeft = joined && panel === leftPanel ? 0 : joined && panel === rail ? margin : gap;
                const gapRight = joined && panel === rail ? 0 : gap;
                panel.style.setProperty('--resketch-sidebar-width', Math.max(1, bounds.width - gapLeft - gapRight) + 'px');
                panel.style.setProperty('--resketch-sidebar-height', Math.max(1, bounds.height - insetTop - 2 * margin) + 'px');
                panel.style.setProperty('--resketch-sidebar-offset-top', insetTop + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-vertical', margin + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-left', gapLeft + 'px');
                panel.style.setProperty('--resketch-sidebar-gap-right', gapRight + 'px');
                panel.style.setProperty('--resketch-sidebar-radius', (glassActive ? glass.cornerRadius : options.sidebarCornerRadius) + 'px');
                panel.style.setProperty('--resketch-sidebar-shadow', shadow);
                panel.setAttribute('data-resketch-floating-sidebar', '');
                if (joined && (panel === rail || panel === leftPanel))
                    panel.setAttribute('data-resketch-sidebar-join', panel === rail ? 'start' : 'end');
            }
            panel.setAttribute('data-resketch-sidebar', '');
            for (let node = panel.parentElement; node; node = node.parentElement) ancestors.add(node);
        }
        for (const ancestor of ancestors) ancestor.setAttribute('data-resketch-sidebar-ancestor', '');
        let shared = false;
        if ((options.floatingSidebars || translucent && options.sidebarBackdrop === 'canvas') && rail && leftPanel) {
            const start = rail.getBoundingClientRect(), end = leftPanel.getBoundingClientRect();
            shared = start.width > 0 && end.width > 0 && Math.abs(start.right - end.left) < 3
                && Math.abs(start.top - end.top) < 3 && Math.abs(start.bottom - end.bottom) < 3;
            if (shared) {
                // Keep the native panels in place; one surface behind both avoids
                // clipping and filtering the canvas again at their internal seam.
                let parent = rail.parentElement;
                while (parent && !parent.contains(leftPanel)) parent = parent.parentElement;
                let branch = rail;
                while (branch.parentElement !== parent) branch = branch.parentElement;
                let leftBranch = leftPanel;
                while (leftBranch.parentElement !== parent) leftBranch = leftBranch.parentElement;
                if (branch.compareDocumentPosition(leftBranch) & 2) branch = leftBranch;
                parent.insertBefore(sharedBackdrop, branch);
                const stackLevel = panel => {
                    for (let node = panel; node && node !== parent; node = node.parentElement) {
                        const level = getComputedStyle(node).zIndex;
                        if (level !== 'auto') return Number(level) || 0;
                    }
                    return 0;
                };
                Object.assign(sharedBackdrop.style, {display:'block', left:start.left + 'px', top:start.top + 'px',
                    width:(end.right - start.left) + 'px', height:start.height + 'px',
                    zIndex:String(Math.min(stackLevel(rail), stackLevel(leftPanel))),
                    borderRadius:(options.floatingSidebars ? (glassActive ? glass.cornerRadius : options.sidebarCornerRadius) : 0) + 'px'});
                sharedBackdrop.setAttribute('data-resketch-sidebar', '');
                sharedBackdrop.style.setProperty('--resketch-sidebar-tint', tint);
                sharedBackdrop.style.setProperty('--resketch-sidebar-blur', translucent && options.sidebarBackdrop === 'canvas'
                    ? 'blur(' + options.sidebarCanvasBlur + 'px)' : 'none');
                sharedBackdrop.style.setProperty('--resketch-sidebar-shadow', shadow);
                for (const panel of [rail, leftPanel]) {
                    panel.style.setProperty('--resketch-sidebar-tint', 'transparent');
                    panel.style.setProperty('--resketch-sidebar-blur', 'none');
                    panel.style.setProperty('--resketch-sidebar-shadow', '0 0 transparent');
                }
            }
        }
        // Measure after floating layout is applied, so refraction follows the visible surface.
        const glassPanels = shared ? panels.filter(panel => panel !== rail && panel !== leftPanel).concat(sharedBackdrop) : panels;
        for (const panel of glassPanels) if (glassActive) {
            const bounds = panel.getBoundingClientRect();
            const width = Math.round(bounds.width), height = Math.round(bounds.height);
            if (!width || !height) continue;
            const key = JSON.stringify([width, height, glass.noiseStrength, glass.refractionStrength,
                glass.refractionMode, glass.refractionEdgeSize, glass.refractionFalloff,
                glass.refractionCornerRadius, glass.rgbFringingStrength]);
            let filter = glassFilters.get(panel);
            if (!filter || filter.key !== key) {
                const id = 'resketch-glass-' + ++glassSerial;
                filter = {key, id, markup:glassFilter(width, height, glass, id)};
                glassFilters.set(panel, filter);
            }
            filters.push(filter);
            const outerShadow = getComputedStyle(panel).boxShadow;
            panel.style.setProperty('--resketch-sidebar-outer-shadow', outerShadow === 'none' ? '0 0 transparent' : outerShadow);
            panel.setAttribute('data-resketch-liquid-glass', '');
            panel.style.setProperty('--resketch-sidebar-inner-shadow', glassInnerShadow(glass));
            panel.style.setProperty('--resketch-sidebar-blur', 'blur(' + options.sidebarCanvasBlur + 'px) url(#'
                + filter.id + ') brightness(' + glass.brightness / 100 + ') saturate(' + glass.saturation / 100
                + ') contrast(' + glass.contrast / 100 + ')');
        }
        const signature = filters.map(filter => filter.id).join(',');
        if (signature !== filterSignature) {
            filterSvg.innerHTML = filters.map(filter => filter.markup).join('');
            filterSignature = signature;
        }
        const rects = panels.filter(panel => !joined || panel !== leftPanel).map(panel => {
            const bounds = panel.getBoundingClientRect();
            const right = joined && panel === rail ? leftPanel.getBoundingClientRect().right : bounds.right;
            return {left:bounds.left, top:bounds.top, right, bottom:bounds.bottom,
                    radius:parseFloat(getComputedStyle(panel).borderTopLeftRadius) || 0};
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
            sharedBackdrop.remove();
            filterSvg.remove();
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
    stylesheet("resketch-sidebar-scrollbars", options.sidebarScrollbarsCss);
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
        sidebarScrollbarsCss: sidebarScrollbarsCss(options.hideSidebarScrollbars !== false),
        translucentSidebars: !!options.translucentSidebars,
        floatingSidebars: !!options.floatingSidebars,
        hideFloatingScrollbars: !!options.hideFloatingScrollbars,
        sidebarCornerRadius: Math.max(0, Math.min(40, Number.isFinite(options.sidebarCornerRadius) ? options.sidebarCornerRadius : 12)),
        sidebarMargin: Math.max(0, Math.min(40, Number.isFinite(options.sidebarMargin) ? options.sidebarMargin : 8)),
        sidebarShadowTransparency: Math.max(0, Math.min(100, Number.isFinite(options.sidebarShadowTransparency) ? options.sidebarShadowTransparency : 65)),
        sidebarShadowStrength: Math.max(0, Math.min(100, Number.isFinite(options.sidebarShadowStrength) ? options.sidebarShadowStrength : 40)),
        sidebarBackdrop: options.sidebarBackdrop === "canvas" ? "canvas" : "desktop",
        sidebarCanvasBlur: Math.max(0, Math.min(40, Number.isFinite(options.sidebarCanvasBlur) ? options.sidebarCanvasBlur : 15)),
        sidebarLiquidGlass: normalizedLiquidGlass(options.sidebarLiquidGlass),
        sidebarCanvasOpacity: Math.max(0, Math.min(100, Number.isFinite(options.sidebarCanvasOpacity) ? options.sidebarCanvasOpacity
            : Number.isFinite(options.opacity) ? options.opacity : 100)),
        opacity: Math.max(0, Math.min(100, Number.isFinite(options.opacity) ? options.opacity : 100))
    }
    return "(function() {" + storeSource + ";" + sidebarMaskSource + ";" + sidebarSource
        + ";(" + pageThemeSource + ")(" + JSON.stringify(settings) + ");})()"
}
