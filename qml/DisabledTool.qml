import QtQuick
import QtQuick.Controls

ToolButton {
   id: tool
   property string toolName: ""
   objectName: toolName
   enabled: false
   width: Theme.buttonHeight
   height: Theme.buttonHeight
   padding: 0
   property color iconColor: Theme.textDisabled
   property int radius: Theme.buttonRadius
   property string glyphSignature: mark.signature

   background: Rectangle {
      radius: tool.radius
      color: Theme.tonal
   }
   contentItem: Glyph {
      id: mark
      glyphName: tool.toolName
      strokeColor: tool.iconColor
   }
   onClicked: {}
}
