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
        // Recents cards use Figma's card primitive, including its main-action marker.
        + '[class*="tiles_view--container--"] [data-fpl-component="primitive"]:has(> [data-card-main-action]) {'
        + '--color-text:' + readable(text, bg, 8) + ' !important;'
        + '--color-text-secondary:' + readable(tokens["text-secondary"], bg, 5) + ' !important; }'
        // These primitives inherit browser button colors instead of semantic text roles.
        + '[class*="sidebar_row--sidebarRowSelected--"] { color:var(--color-text-onselected) !important; --color-icon:var(--color-icon-onselected) !important; }'
        + '[class*="legacy_pages_panel--pageRowActive--"] { background:var(--color-bg-selected) !important; color:var(--color-text-onselected) !important; outline:1px solid var(--color-border-selected) !important; }'
        + '[data-testid="navigation-bar"] button[aria-expanded="true"] > div { background:var(--color-bg-selected-strong) !important; color:var(--color-text-onselected-strong) !important; --color-icon:var(--color-icon-onselected-strong) !important; }'
        + '[data-testid="file-icon"] { --color-icon:var(--color-icon-onbrand) !important; }'
}

// Cut holes in opaque page/canvas backgrounds without changing Figma's layout.
var sidebarMaskSource = `function sidebarMask(bounds, panels) {
    const points = ['0px 0px', bounds.width + 'px 0px', bounds.width + 'px ' + bounds.height + 'px', '0px ' + bounds.height + 'px', '0px 0px'];
    let holes = 0;
    for (const panel of panels) {
        const left = Math.max(0, panel.left - bounds.left), top = Math.max(0, panel.top - bounds.top);
        const right = Math.min(bounds.width, panel.right - bounds.left), bottom = Math.min(bounds.height, panel.bottom - bounds.top);
        if (right <= left || bottom <= top) continue;
        points.push(left + 'px ' + top + 'px', right + 'px ' + top + 'px', right + 'px ' + bottom + 'px', left + 'px ' + bottom + 'px', left + 'px ' + top + 'px', '0px 0px');
        ++holes;
    }
    return holes ? 'polygon(evenodd, ' + points.join(', ') + ')' : 'none';
}`

var sidebarSource = `function sidebarAppearance(options, stylesheet) {
    let controller = window.__resketchSidebars;
    if (!options.translucentSidebars || options.opacity >= 100) {
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
    const selector = '[data-testid="navigation-bar"], [data-onboarding-key="unified-design-onboarding-left-panel"], [data-testid="properties-panel"], [class*="sidebar--navDefault--"], .fb-sidebar';
    let panels = [], ancestors = new Set(), canvases = [], frame = 0;
    const underlay = document.createElement('div');
    underlay.id = 'resketch-sidebar-underlay';
    document.body.prepend(underlay);
    stylesheet('resketch-sidebars',
        '[data-resketch-sidebar], [data-resketch-sidebar] [data-preferred-theme] { --color-bg:transparent !important; }'
        + '[data-resketch-sidebar] { background-color:var(--resketch-sidebar-tint) !important; }'
        // Search suggestions float beyond the sidebar and need an opaque surface.
        + '[data-resketch-sidebar] [data-testid="facetedSearchModal"], [data-resketch-sidebar] [data-testid="facetedSearchModal"] [data-preferred-theme] { --color-bg:var(--resketch-sidebar-surface) !important; }'
        + '[data-resketch-sidebar-ancestor] { background-color:transparent !important; }'
        + '[data-resketch-sidebar-canvas] { clip-path:var(--resketch-sidebar-clip) !important; }'
        + '#resketch-sidebar-underlay { position:fixed; inset:0; z-index:-1; pointer-events:none; }');
    function clear() {
        for (const panel of panels) {
            panel.removeAttribute('data-resketch-sidebar');
            panel.style.removeProperty('--resketch-sidebar-tint');
            panel.style.removeProperty('--resketch-sidebar-surface');
        }
        for (const ancestor of ancestors) ancestor.removeAttribute('data-resketch-sidebar-ancestor');
        for (const canvas of canvases) {
            canvas.removeAttribute('data-resketch-sidebar-canvas');
            canvas.style.removeProperty('--resketch-sidebar-clip');
        }
        ancestors.clear();
    }
    function update() {
        frame = 0;
        clear();
        const found = Array.from(document.querySelectorAll(selector));
        const next = found.filter(panel => !found.some(other => other !== panel && other.contains(panel)));
        for (const panel of panels) if (!next.includes(panel)) resize.unobserve(panel);
        for (const panel of next) if (!panels.includes(panel)) resize.observe(panel);
        panels = next;
        canvases = Array.from(document.querySelectorAll('.gpu-view-content'));
        const options = controller.options;
        const bg = getComputedStyle(document.body).getPropertyValue('--color-bg').trim() || (options.theme === 'dark' ? '#2c2c2c' : '#ffffff');
        // Desktop tint is already drawn by the native window background.
        // Applying it again here makes 85% opacity effectively 98%.
        const tint = options.sidebarBackdrop === 'desktop' ? 'transparent'
            : 'color-mix(in srgb, ' + bg + ' ' + options.opacity + '%, transparent)';
        const rects = panels.map(panel => panel.getBoundingClientRect()).filter(rect => rect.width && rect.height);
        underlay.style.backgroundColor = options.sidebarBackdrop === 'canvas' && canvases.length
            ? getComputedStyle(canvases[0]).backgroundColor : bg;
        underlay.style.clipPath = options.sidebarBackdrop === 'desktop'
            ? sidebarMask({left:0, top:0, width:innerWidth, height:innerHeight}, rects) : 'none';
        for (const panel of panels) {
            panel.style.setProperty('--resketch-sidebar-tint', tint);
            panel.style.setProperty('--resketch-sidebar-surface', bg);
            panel.setAttribute('data-resketch-sidebar', '');
            for (let node = panel.parentElement; node; node = node.parentElement) ancestors.add(node);
        }
        for (const ancestor of ancestors) ancestor.setAttribute('data-resketch-sidebar-ancestor', '');
        if (options.sidebarBackdrop === 'desktop') for (const canvas of canvases) {
            canvas.style.setProperty('--resketch-sidebar-clip', sidebarMask(canvas.getBoundingClientRect(), rects));
            canvas.setAttribute('data-resketch-sidebar-canvas', '');
        }
    }
    function schedule() { if (!frame) frame = requestAnimationFrame(update); }
    const resize = new ResizeObserver(schedule);
    const observer = new MutationObserver(records => {
        if (records.some(record => [...record.addedNodes, ...record.removedNodes].some(node =>
            node.nodeType === 1 && (node.matches(selector + ', .gpu-view-content') || node.querySelector(selector + ', .gpu-view-content'))))) schedule();
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
        sidebarBackdrop: options.sidebarBackdrop === "canvas" ? "canvas" : "desktop",
        opacity: Math.max(0, Math.min(100, Number.isFinite(options.opacity) ? options.opacity : 100))
    }
    return "(function() {" + storeSource + ";" + sidebarMaskSource + ";" + sidebarSource
        + ";(" + pageThemeSource + ")(" + JSON.stringify(settings) + ");})()"
}
