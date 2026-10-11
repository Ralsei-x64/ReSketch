// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only

import QtQuick

Item {
    id: handles
    required property var targetWindow
    property bool active: false

    visible: active && targetWindow.visibility !== Window.Maximized
    z: 1000

    MouseArea {
        x: 0
        y: 0
        width: 5
        height: handles.height
        hoverEnabled: true
        cursorShape: mouseY < 8 ? Qt.SizeFDiagCursor
                                 : mouseY > height - 8 ? Qt.SizeBDiagCursor : Qt.SizeHorCursor
        onPressed: (mouse) => handles.targetWindow.startSystemResize(mouse.y < 8 ? Qt.LeftEdge | Qt.TopEdge
                                                      : mouse.y > height - 8 ? Qt.LeftEdge | Qt.BottomEdge
                                                                             : Qt.LeftEdge)
    }
    MouseArea {
        x: handles.width - width
        y: 0
        width: 5
        height: handles.height
        hoverEnabled: true
        cursorShape: mouseY < 8 ? Qt.SizeBDiagCursor
                                 : mouseY > height - 8 ? Qt.SizeFDiagCursor : Qt.SizeHorCursor
        onPressed: (mouse) => handles.targetWindow.startSystemResize(mouse.y < 8 ? Qt.RightEdge | Qt.TopEdge
                                                      : mouse.y > height - 8 ? Qt.RightEdge | Qt.BottomEdge
                                                                             : Qt.RightEdge)
    }
    MouseArea {
        x: 5
        y: 0
        width: handles.width - 10
        height: 5
        cursorShape: Qt.SizeVerCursor
        onPressed: handles.targetWindow.startSystemResize(Qt.TopEdge)
    }
    MouseArea {
        x: 5
        y: handles.height - height
        width: handles.width - 10
        height: 5
        cursorShape: Qt.SizeVerCursor
        onPressed: handles.targetWindow.startSystemResize(Qt.BottomEdge)
    }
}
