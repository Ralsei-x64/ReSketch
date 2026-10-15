// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

function isFigmaUrl(address) {
    return /^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?(?:[/?#]|$)/i.test(String(address))
}

function homeNavigationScript(enabled) {
    if (!enabled) return ""
    return String.raw`(()=>{
        if (!window.navigation || window.__resketchHomeNavigation) return;
        window.__resketchHomeNavigation = true;
        navigation.addEventListener('navigate', event => {
            if (!event.cancelable || !/^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?\/(?:file|design|board|proto|slides|deck|site|buzz|make)\/[^/?#]+/i.test(event.destination.url)) return;
            const state = history.state;
            event.preventDefault();
            // Figma updates its store before pushState. Cancelling the URL alone
            // leaves Home in the editor; restore its route after that update ends.
            if (event.destination.sameDocument)
                queueMicrotask(() => window.dispatchEvent(new PopStateEvent('popstate', {state})));
            __resketchNative('home-file', event.destination.url);
        });
    })()`
}

function isFileUrl(address) {
    return /^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?\/(?:file|design|board|proto|slides|deck|site|buzz|make)\/[^/?#]+/i.test(String(address))
}

function fileKey(address) {
    const match = /^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?\/(?:file|design|board|proto|slides|deck|site|buzz|make)\/([a-z0-9_-]+)(?:[/?#]|$)/i.exec(String(address))
    return match ? match[1] : ""
}

function isFileBrowserUrl(address) {
    return /^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?(?:\/(?:files(?:[/?#]|$)|[?#]|$)|[?#]|$)/i.test(String(address))
}

function isNewFileTabUrl(address) {
    return /^https:\/\/(?:[a-z0-9-]+\.)*figma\.com(?::443)?\/desktop_new_tab(?:[?#]|$)/i.test(String(address))
}

function fileName(address, title) {
    const name = String(title || "").replace(/\s*[-–—|]\s*(?:Figma(?:\s+(?:Design|Slides))?|FigJam)\s*$/i, "").trim()
    if (name && !/^(?:Figma(?:\s+(?:Design|Slides))?|FigJam)$/i.test(name) && !/^Loading/i.test(name))
        return name
    const match = /\/(?:file|design|board|proto|slides|deck|site|buzz|make)\/[^/?#]+\/([^?#]+)/i.exec(String(address))
    if (match) {
        try {
            return decodeURIComponent(match[1]).replace(/-/g, " ")
        } catch (_) {}
    }
    return "Untitled file"
}

function pageLabel(address, title) {
    if (isFileUrl(address))
        return fileName(address, title)
    return isNewFileTabUrl(address) ? "New file" : "Home"
}

function windowTitle(address, title) {
    return "ReSketch — " + (isGoogleSignInUrl(address) ? "Google sign in" : pageLabel(address, title))
}

function isAuthGrantUrl(address) {
    return /^https:\/\/www\.figma\.com\/app_auth\/[a-z0-9-]+\/grant(?:[?#]|$)/i.test(String(address))
}

function isGoogleSignInUrl(address) {
    return /^https:\/\/accounts\.google\.com(?::443)?(?:[/?#]|$)/i.test(String(address))
}

function isExternalWebUrl(address) {
    return /^https?:\/\//i.test(String(address))
           && !isFigmaUrl(address) && !isGoogleSignInUrl(address)
}

function tabTitle(title) {
    return title.length > 20 ? title.slice(0, 19) + "…" : title
}

function deepLink(address) {
    if (isFigmaUrl(address))
        return address
    const file = /^figma:\/\/(file|design|board|proto|slides)\/([^\s?#]+)(\?[^#]*)?(#.*)?$/i.exec(address)
    return file ? "https://www.figma.com/" + file[1] + "/" + file[2] + (file[3] || "") + (file[4] || "") : ""
}

function redeemSecret(address) {
    if (!/^figma:\/\/app_auth\/redeem\?/i.test(address))
        return ""
    const match = /(?:[?&])g_secret=([a-z0-9_-]+)(?:[&#]|$)/i.exec(address)
    return match ? match[1] : ""
}
