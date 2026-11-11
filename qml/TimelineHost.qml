import QtQuick

Rectangle {
   objectName: "timelineHost"
   property int clipCount: 0
   implicitHeight: Theme.timelineHeight
   height: Theme.timelineHeight
   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1
}
