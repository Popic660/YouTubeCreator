import QtQuick

Item {
   id: chrome
   property string panelId: ""
   property string title: ""
   property string glyphName: "folder"
   property alias extra: extraSlot.data
   signal panelDragStarted()
   signal panelDragFinished()

   height: 32
   objectName: panelId + "Chrome"

   Rectangle {
      anchors.fill: parent
      color: Theme.canvas
   }

   Glyph {
      id: chromeGlyph
      objectName: panelId + "ChromeGlyph"
      anchors.left: parent.left
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      width: 24
      height: 24
      glyphName: chrome.glyphName
      strokeColor: Theme.text
   }

   Text {
      objectName: panelId + "ChromeTitle"
      anchors.left: chromeGlyph.right
      anchors.leftMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: chrome.title
      color: Theme.text
      font.pixelSize: 14
      font.weight: 500
   }

   Item {
      id: extraSlot
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      height: 32
      width: childrenRect.width
      z: 2
   }

   Item {
      id: proxy
      width: 1
      height: 1
      Drag.keys: ["panel"]
      Drag.source: chrome
      Drag.active: press.drag.active
      Drag.hotSpot.x: press.mouseX
      Drag.hotSpot.y: press.mouseY
   }

   MouseArea {
      id: press
      anchors.fill: parent
      drag.target: proxy
      drag.threshold: 4
      cursorShape: Qt.SizeAllCursor
      z: 1
      onPressed: chrome.panelDragStarted()
      onReleased: chrome.panelDragFinished()
   }
}
