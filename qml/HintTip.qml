import QtQuick
import QtQuick.Controls

ToolTip {
   id: tip
   delay: 400
   timeout: 20000
   padding: 12
   contentWidth: 300
   contentItem: Text {
      text: tip.text
      color: Theme.text
      font.family: "Roboto, Arial, sans-serif"
      font.pixelSize: 13
      wrapMode: Text.WordWrap
      width: 300
   }
   background: Rectangle {
      color: Theme.menu
      radius: 12
   }
}
