// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.Frame {
    id: settingsGroup
    property string title
    default property alias rows: groupLayout.data
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    padding: Kirigami.Units.largeSpacing
    contentItem: ColumnLayout {
        id: groupLayout
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: settingsGroup.title
            wrapMode: Text.WordWrap
        }
    }
}
