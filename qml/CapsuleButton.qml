import QtQuick
import QtQuick.Controls

Button {
   id: capsule
   property bool filled: false
   property string hint: ""
   hoverEnabled: true
   opacity: enabled ? 1 : 0.5
   implicitHeight: Theme.buttonHeight
   leftPadding: 16
   rightPadding: 16
   font.pixelSize: Theme.buttonTextSize
   font.weight: 500
   background: Rectangle {
      radius: Theme.buttonRadius
      color: capsule.filled
         ? Theme.faceFill(capsule.hovered, capsule.down)
         : Theme.faceTonal(capsule.hovered, capsule.down)
   }
   contentItem: Text {
      text: capsule.text
      color: capsule.filled ? Theme.textInverse : Theme.text
      font: capsule.font
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
   }
   HintTip {
      visible: capsule.enabled && capsule.hovered && capsule.hint.length > 0
      text: capsule.hint
   }
}
