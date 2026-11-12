import QtQuick

Item {
   id: frame
   objectName: "frameView"
   property var document: null
   property alias compositor: frameCompositor
   readonly property bool hasFrameImage: frameCompositor.hasFrame
   readonly property string centerMode: hasFrameImage ? "preview" : "empty"
   readonly property int previewWidth: frameCompositor.previewWidth
   readonly property int previewHeight: frameCompositor.previewHeight
   readonly property bool leftEdgeOpaque: frameCompositor.leftEdgeOpaque
   readonly property int lastSourceMs: frameCompositor.lastSourceMs

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
      clip: true

      CFrameCompositor {
         id: frameCompositor
         objectName: "frameCompositor"
         anchors.fill: parent
         document: frame.document
      }
      MouseArea {
         anchors.fill: parent
         enabled: frame.document !== null && frame.document.hasClips
         cursorShape: Qt.PointingHandCursor
         hoverEnabled: true
         onClicked: frame.document.toggle_play()
      }
      HoverHandler {
         id: frameHover
      }
      HintTip {
         visible: frameHover.hovered
         text: frame.document && frame.document.hasClips
            ? "Просмотр. Клик — пуск или пауза. Картинка и звук " +
              "идут вместе, с красной линии на таймлайне. Перемотка " +
              "— клик по дорожке внизу. Пуск также есть треугольником " +
              "на шапке таймлайна."
            : "Здесь будет кадр 9:16. Импортируйте файл в панель " +
              "«Медиа», создайте ролик в папке и перенесите ассет " +
              "на таймлайн. Клик по кадру запустит просмотр со звуком."
      }
   }
}
