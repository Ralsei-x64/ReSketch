// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

// Figma has no public native-menu API. Discover its loaded menu helpers by
// their behavior, rather than pinning bundle module numbers or translated labels.
function script(command) {
    return "(" + pageMenuSource + ")(" + JSON.stringify(command || "") + ")"
}

function homeMenus(theme, authenticated) {
    function action(id, text, enabled = true, checked) {
        return {id, text, enabled, shortcut: "", checkable: checked !== undefined, checked: !!checked}
    }
    function menu(id, text, children) {
        return {id, text, enabled: true, children}
    }
    return [
        menu("figma/view-menu", qsTr("View"), [
            action("app/reload", qsTr("Reload page")),
            action("app/overview", qsTr("Tab overview"))
        ]),
        menu("figma/preferences-menu", qsTr("Preferences"), [
            menu("app/theme", qsTr("Theme"), [
                action("app/theme-auto", qsTr("Use system theme"), true, theme === "auto"),
                action("app/theme-light", qsTr("Light"), true, theme === "light"),
                action("app/theme-dark", qsTr("Dark"), true, theme === "dark")
            ])
        ]),
        menu("figma/figma-account-menu", qsTr("Help"), [
            action("app/help", qsTr("Help page")),
            action("app/forum", qsTr("Support forum")),
            action("app/tutorials", qsTr("Video tutorials")),
            action("app/releases", qsTr("Release notes")),
            action("app/legal", qsTr("Legal summary")),
            {id: "home/help-account-separator", separator: true},
            action("home/account-settings", qsTr("Account settings"), authenticated),
            action("home/sign-out", qsTr("Log out"), authenticated),
            {id: "home/help-about-separator", separator: true},
            action("app/about", qsTr("About ReSketch…"))
        ])
    ]
}

function homeScript(command) {
    return "(" + homePageSource + ")(" + JSON.stringify(command || "") + ")"
}

// Read the Redux Provider used by the UI. Figma's window.store and
// _fullscreen_ debug facades throttle calls and can block the renderer.
var storeSource = `
    function menuStore() {
        const button = document.querySelector('[data-onboarding-key="figma-menu"]')
                       || document.querySelector('[data-onboarding-key]')
        function provider(node) {
            const key = Object.keys(node).find(key => key.startsWith("__reactFiber")
                                                   || key.startsWith("__reactContainer"))
            let fiber = key && node[key]
            // A root container points to HostRoot; its child holds the providers.
            if (key?.startsWith("__reactContainer")) {
                for (let count = 0; fiber && count < 30; ++count, fiber = fiber.child) {
                    const props = fiber.memoizedProps
                    const store = props?.store || props?.value?.store
                    if (typeof store?.getState === "function" && typeof store.dispatch === "function")
                        return store
                }
                return null
            }
            for (; fiber; fiber = fiber.return) {
                const props = fiber.memoizedProps
                const store = props?.store || props?.value?.store
                if (typeof store?.getState === "function" && typeof store.dispatch === "function")
                    return store
            }
            return null
        }
        if (button) {
            const store = provider(button)
            if (store) return store
        }
        const walker = document.createTreeWalker(document.body, 1)
        for (let count = 0, node = walker.nextNode(); node && count < 100;
             ++count, node = walker.nextNode()) {
            const store = provider(node)
            if (store) return store
        }
        return null
    }
`

// Home does not register Figma's canvas command dispatcher. Use the same
// modal and account actions its profile menu dispatches instead.
var homePageSource = `function homePageMenu(command) {
    ${storeSource}
    try {
        if (location.hostname !== "www.figma.com"
                || !(location.pathname.startsWith("/files/") || location.pathname === "/files"
                     || location.pathname === "/" || location.pathname === "/desktop_new_tab"))
            return JSON.stringify({authenticated: false, executed: false})
        const store = menuStore()
        const user = store?.getState()?.user
        if (!command) return JSON.stringify({authenticated: !!user})
        if (!user) return JSON.stringify({executed: false})
        let require = window.__resketchHomeMenuRuntime
        if (!require) {
            window.rspackChunk_figma_web_bundler.push([
                ["resketch-home-menus"], {}, runtime => { require = runtime }
            ])
            window.__resketchHomeMenuRuntime = require
        }
        function moduleWith(...markers) {
            const id = Object.keys(require.m).find(id => {
                const source = require.m[id].toString()
                return markers.every(marker => source.includes(marker))
            })
            if (!id) throw new Error("Figma account action unavailable")
            return require(id)
        }
        if (command === "home/account-settings") {
            const settings = moduleWith("accountModalSubViewData", "ChangeAddressModal")
            const modals = moduleWith("optOutOfPrevModal", "showModalsBeneath")
            const openModal = Object.values(modals).find(value => typeof value === "function"
                && value.toString().includes("optOutOfPrevModal")
                && value.toString().includes("showModalsBeneath"))
            if (!openModal || !settings.sE || !settings.c3?.ACCOUNT)
                throw new Error("Figma account settings changed")
            store.dispatch(openModal({type: settings.sE, data: {tab: settings.c3.ACCOUNT}}))
        } else if (command === "home/sign-out") {
            const accounts = moduleWith("logoutOneUser", "autosave_modal_shown")
            if (typeof accounts.q !== "function") throw new Error("Figma sign-out action changed")
            store.dispatch(accounts.q({user}))
        } else {
            return JSON.stringify({executed: false})
        }
        return JSON.stringify({executed: true})
    } catch (error) {
        return JSON.stringify({executed: false, error: String(error.message || error)})
    }
}`

// Keep the browser script as source: QML functions stringify as [native code].
var pageMenuSource = `function pageMenu(command) {
    ${storeSource}
    try {
        if (location.hostname !== "www.figma.com") return JSON.stringify({menus: []})
        const store = menuStore()
        const state = store?.getState()
        if (state?.selectedView?.view !== "fullscreen" || !state.mirror?.appModel)
            return JSON.stringify({menus: []})
        let bridge = window.__resketchMenus
        if (!bridge) {
            const chunks = window.rspackChunk_figma_web_bundler
            if (!chunks)
                return JSON.stringify({menus: []})
            let require
            chunks.push([["resketch-native-menus"], {}, runtime => { require = runtime }])
            function moduleWith(...markers) {
                const id = Object.keys(require.m).find(id => {
                    const source = require.m[id].toString()
                    return markers.every(marker => source.includes(marker))
                })
                if (!id) throw new Error("Figma menu helper unavailable")
                return require(id)
            }
            function functionWith(module, marker) {
                return Object.values(module).find(value => typeof value === "function"
                                                  && value.toString().includes(marker))
            }
            const definitions = moduleWith("fileMenuArgs", "GetFullscreenMenuItems")
            const filtering = moduleWith("removeDisabledItems", "isDesktopMenu", "disabledAndForceVisible")
            const callbacks = moduleWith("_permanentCache", "toggle-menu")
            bridge = {
                build: functionWith(definitions, "fileMenuArgs"),
                filter: functionWith(filtering, "removeDisabledItems"),
                visible: functionWith(filtering, "!desktop_os_menu"),
                actions: Object.values(callbacks).find(value => typeof value?.get === "function"),
                commands: new Map()
            }
            if (!bridge.build || !bridge.filter || !bridge.visible || !bridge.actions)
                throw new Error("Figma menu helpers changed")
            window.__resketchMenus = bridge
        }

        const appModel = state.mirror.appModel
        const options = {appModel, selectedView: state.selectedView,
                         isReadOnly: appModel.isReadOnly, isDesktopMenu: true,
                         isSearching: false, removeDisabledItems: false}

        // Use the full rendered definitions when Figma has built its main menu,
        // including file-specific callbacks and installed plugin entries.
        let raw
        const button = document.querySelector('[data-onboarding-key="figma-menu"]')
                       || document.querySelector('button[aria-haspopup="menu"][data-onboarding-key]')
                       || document.querySelector('button[aria-label="Main menu"]')
        if (button) {
            let fiber = button[Object.keys(button).find(key => key.startsWith("__reactFiber"))]
            while (fiber && !fiber.memoizedProps?.onMenuOpenChange) fiber = fiber.return
            function findItems(node) {
                if (!node) return null
                if (Array.isArray(node.memoizedProps?.items)
                        && node.memoizedProps.items.some(item => item.name === "view-menu"))
                    return node.memoizedProps.items
                return findItems(node.child) || findItems(node.sibling)
            }
            raw = findItems(fiber?.child)
        }
        if (!raw) {
            // These are the same file-menu inputs Figma uses in its Actions
            // search. Branch actions remain hidden until Figma supplies them.
            const hiddenBranches = Object.fromEntries([
                "createBranch", "openBranchSource", "viewBranches", "viewBranchDiff",
                "mergeBranch", "viewSourceDiff", "updateBranch"
            ].map(key => [key, {status: "hidden"}]))
            raw = bridge.build({
                theme: document.body.dataset.preferredTheme || "light",
                backToFileArgs: {shouldShowBackToFiles: false},
                publishingModalArgs: {isPublishingModalDisabled: false},
                fileMenuArgs: {
                    context: "unknown", fileCreationMenuItems: [],
                    branchingActionsStatus: hiddenBranches, saveAsState: state.saveAsState,
                    topLevelMode: appModel.topLevelMode, openFile: state.openFile,
                    hasCollections: false, duplicateFileData: null,
                    shouldShowSlideConversionEntrypoint: false
                }
            })
        }
        function desktopItems(items) {
            return items.filter(item => bridge.visible(item, options)).map(item => {
                const copy = Object.assign({}, item)
                copy.flags = item.flags?.filter(flag => flag !== "desktop_os_menu")
                if (item.children) copy.children = desktopItems(item.children)
                return copy
            })
        }
        const filtered = bridge.filter(desktopItems(raw), options)
        const commands = new Map()
        function convert(items, parent) {
            const converted = items.flatMap((item, index) => {
                if (item.render || item.header || item.input) return []
                const id = parent + "/" + (item.action || item.name || index)
                if (item.separator) return [{id, separator: true}]
                const children = item.children ? convert(item.children, id) : null
                if (children && !children.some(child => !child.separator)) return []
                if (!children && !item.action && !item.callback
                        && !["cut", "copy", "paste"].includes(item.name)) return []
                commands.set(id, item)
                const entry = {id, text: item.displayText, enabled: !item.disabled,
                               checkable: typeof item.isChecked === "boolean",
                               checked: !!item.isChecked, shortcut: item.shortcut || ""}
                if (children) entry.children = children
                return [entry]
            })
            while (converted[0]?.separator) converted.shift()
            while (converted[converted.length - 1]?.separator) converted.pop()
            return converted.filter((item, index) => !item.separator || !converted[index - 1].separator)
        }
        const menus = convert(filtered.filter(item => item.children), "figma")
        bridge.commands = commands
        if (command) {
            const item = commands.get(command)
            if (!item || item.disabled || item.children)
                return JSON.stringify({executed: false})
            const event = new MouseEvent("click")
            if (item.callback)
                item.callback(item.action || item.name, item.args, store.dispatch, event)
            if (item.action)
                bridge.actions.get(item.action, "os-menu", item.args)(event)
            else if (["cut", "copy", "paste"].includes(item.name))
                document.execCommand(item.name)
            return JSON.stringify({executed: true})
        }
        return JSON.stringify({menus})
    } catch (error) {
        // A changed upstream bundle must never leave another file's actions live.
        return JSON.stringify({menus: [], error: String(error.message || error)})
    }
}`
