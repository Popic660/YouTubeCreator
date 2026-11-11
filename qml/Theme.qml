pragma Singleton

import QtQuick

QtObject {
   readonly property color canvas: "#0f0f0f"
   readonly property color raised: "#212121"
   readonly property color menu: "#282828"
   readonly property color selected: "#272727"
   readonly property color plot: "#3f3f3f"
   readonly property color searchFill: "#121212"
   readonly property color searchBorder: "#303030"
   readonly property color text: "#f1f1f1"
   readonly property color textSecondary: "#aaaaaa"
   readonly property color textDisabled: "#717171"
   readonly property color textInverse: "#0f0f0f"
   readonly property color link: "#3ea6ff"
   readonly property color linkHover: "#65b8ff"
   readonly property color linkPressed: "#065fd4"
   readonly property color fill: "#f1f1f1"
   readonly property color fillHover: "#d9d9d9"
   readonly property color tonal: Qt.rgba(1, 1, 1, 0.1)
   readonly property color tonalHover: Qt.rgba(1, 1, 1, 0.2)
   readonly property color outline: Qt.rgba(1, 1, 1, 0.2)
   readonly property color outlineStrong: "#3f3f3f"
   readonly property color searchButton: Qt.rgba(1, 1, 1, 0.08)
   readonly property color brand: "#ff0033"
   readonly property color divider: Qt.rgba(1, 1, 1, 0.2)

   readonly property int headerHeight: 56
   readonly property int buttonHeight: 40
   readonly property int buttonRadius: 20
   readonly property int buttonTextSize: 14
   readonly property int searchHeight: 40
   readonly property int searchButtonWidth: 64
   readonly property int searchCornerRadius: 40
   readonly property int iconSize: 24
   readonly property int libraryWidth: 240
   readonly property int timelineHeight: 160
}
