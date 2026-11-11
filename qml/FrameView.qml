import QtQuick

Item {
   id: frame
   objectName: "frameView"
   property string centerMode: "empty"
   property bool hasFrameImage: false

   Rectangle {
      id: surface
      objectName: "frameSurface"
      anchors.centerIn: parent
      color: Theme.canvas
      border.color: Theme.outline
      border.width: 1
      height: Math.min(
         Math.max(parent.height - 16, 0),
         Math.max(parent.width - 16, 0) * 16 / 9)
      width: height * 9 / 16
   }
}
