// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
.pragma library

var items = [
    {id: "new-tab", title: "New tab", category: "Tabs", defaultSequence: "Ctrl+T"},
    {id: "close-tab", title: "Close focused tab", category: "Tabs", defaultSequence: "Ctrl+W"},
    {id: "previous-tab", title: "Previous tab", category: "Tabs", defaultSequence: "Ctrl+Alt+Shift+Left"},
    {id: "next-tab", title: "Next tab", category: "Tabs", defaultSequence: "Ctrl+Alt+Shift+Right"},
    {id: "cycle-tabs", title: "Cycle tabs", category: "Tabs", defaultSequence: "Ctrl+Tab"},
    {id: "toggle-overview", title: "Toggle tab overview", category: "Tabs", defaultSequence: "Ctrl+Alt+Shift+Up"},
    {id: "detach-tab", title: "Move focused tab to a new window", category: "Tabs", defaultSequence: "Ctrl+Alt+Shift+Down"},
    {id: "freeze-tabs", title: "Freeze or wake tabs", category: "Tabs", defaultSequence: "Ctrl+Alt+Shift+F"},
    {id: "fullscreen", title: "Toggle fullscreen", category: "Window", defaultSequence: "F11"},
    {id: "autohide-toolbar", title: "Toggle titlebar autohide", category: "Window", defaultSequence: "Shift+F11"},
    {id: "cancel-selection", title: "Clear selection or leave fullscreen/autohide", category: "Window", defaultSequence: "Escape"},
    {id: "overview-left", title: "Select previous card", category: "Overview", defaultSequence: "Left", key: "Left"},
    {id: "overview-right", title: "Select next card", category: "Overview", defaultSequence: "Right", key: "Right"},
    {id: "overview-up", title: "Select card above", category: "Overview", defaultSequence: "Up", key: "Up"},
    {id: "overview-down", title: "Select card below", category: "Overview", defaultSequence: "Down", key: "Down"},
    {id: "overview-range-left", title: "Extend selection left", category: "Overview", defaultSequence: "Shift+Left", key: "Left", range: true},
    {id: "overview-range-right", title: "Extend selection right", category: "Overview", defaultSequence: "Shift+Right", key: "Right", range: true},
    {id: "overview-range-up", title: "Extend selection up", category: "Overview", defaultSequence: "Shift+Up", key: "Up", range: true},
    {id: "overview-range-down", title: "Extend selection down", category: "Overview", defaultSequence: "Shift+Down", key: "Down", range: true},
    {id: "overview-open", title: "Open selected card", category: "Overview", defaultSequence: "Return", key: "Return"},
    {id: "overview-open-keypad", title: "Open selected card (keypad)", category: "Overview", defaultSequence: "Enter", key: "Enter"},
    {id: "delete-selection", title: "Close selected tabs or ungroup selected groups", category: "Selection", defaultSequence: "Delete"},
    {id: "close-selection", title: "Close selected tabs and groups", category: "Selection", defaultSequence: "Alt+Delete"},
    {id: "group-selection", title: "Group, move into group, or ungroup selection", category: "Selection", defaultSequence: "Ctrl+G"}
]

function sequence(settings, id) {
    const overrides = settings.shortcutOverrides || {}
    return Object.prototype.hasOwnProperty.call(overrides, id)
        ? overrides[id] : items.find(item => item.id === id)?.defaultSequence || ""
}
