import QtQuick

Rectangle {
   id: timelineHost
   objectName: "timelineHost"
   property int clipCount: 0
   property string panelId: "timeline"
   signal panelDragStarted()
   signal panelDragFinished()
   implicitHeight: Theme.timelineHeight
   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1

   Item {
      id: timelineHandle
      objectName: "timelineDragHandle"
      property string panelId: "timeline"
      width: parent.width
      height: 32
      Rectangle {
         anchors.fill: parent
         color: Theme.menu
      }
      Text {
         anchors.verticalCenter: parent.verticalCenter
         anchors.left: parent.left
         anchors.leftMargin: 8
         text: "Таймлайн"
         color: Theme.text
         font.pixelSize: 12
      }
      Item {
         id: timelineProxy
         width: 1
         height: 1
         Drag.keys: ["panel"]
         Drag.source: timelineHandle
         Drag.active: timelinePress.drag.active
         Drag.hotSpot.x: timelinePress.mouseX
         Drag.hotSpot.y: timelinePress.mouseY
      }
      MouseArea {
         id: timelinePress
         anchors.fill: parent
         drag.target: timelineProxy
         drag.threshold: 4
         cursorShape: Qt.SizeAllCursor
         onPressed: timelineHost.panelDragStarted()
         onReleased: timelineHost.panelDragFinished()
      }
   }
}
