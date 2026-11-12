import QtQuick
import QtQuick.Controls

Rectangle {
   id: timelineHost
   objectName: "timelineHost"
   property var document: null
   readonly property int clipCount: document ? document.clipCount : 0
   readonly property int audioCount: document ? document.audioCount : 0
   readonly property int itemCount: document ? document.itemCount : 0
   property string panelId: "timeline"
   signal panelDragStarted()
   signal panelDragFinished()
   implicitHeight: Theme.timelineHeight
   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1

   function plotSpan() {
      return Math.max(plot.width - 16, 1)
   }

   function timeToX(ms) {
      if (document === null || document.durationMs <= 0) {
         return 8
      }
      return 8 + ms / document.durationMs * plotSpan()
   }

   function xToTime(px) {
      if (document === null) {
         return 0
      }
      const duration = Math.max(1, document.durationMs)
      const x = Math.min(Math.max(px - 8, 0), plotSpan())
      return Math.round(x / plotSpan() * duration)
   }

   function clipLength(id) {
      return Math.max(0, document.clip_out(id) - document.clip_in(id))
   }

   function clipAt(px, py) {
      if (document === null || itemCount <= 0) {
         return ""
      }
      const time = xToTime(px)
      let track = "a1"
      if (py < 40) {
         track = "v1"
      } else if (py < 80) {
         track = "v2"
      }
      for (let i = 0; i < itemCount; ++i) {
         const id = document.clip_id_at(i)
         if (document.clip_track(id) !== track) {
            continue
         }
         const start = document.clip_start(id)
         const end = start + clipLength(id)
         if (time >= start && time < end) {
            return id
         }
      }
      return ""
   }

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
      Text {
         objectName: "timelineClock"
         anchors.centerIn: parent
         visible: timelineHost.document !== null
            && timelineHost.document.hasClips
         text: {
            if (timelineHost.document === null) {
               return ""
            }
            return Theme.formatClock(timelineHost.document.playheadMs)
               + " / "
               + Theme.formatClock(timelineHost.document.durationMs)
         }
         color: Theme.textSecondary
         font.pixelSize: 12
      }
      Rectangle {
         id: playButton
         objectName: "playPauseButton"
         anchors.verticalCenter: parent.verticalCenter
         anchors.right: parent.right
         anchors.rightMargin: 8
         width: 32
         height: 32
         radius: 16
         color: Theme.faceFill(playPress.containsMouse, playPress.pressed)
         visible: timelineHost.document !== null
            && timelineHost.document.hasClips
         z: 2
         Glyph {
            anchors.centerIn: parent
            glyphName: timelineHost.document && timelineHost.document.playing
               ? "pause" : "play"
            strokeColor: Theme.textInverse
         }
         MouseArea {
            id: playPress
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: timelineHost.document.toggle_play()
         }
         HoverHandler {
            id: playHover
         }
         HintTip {
            visible: playHover.hovered
            text: "Пуск и пауза. Картинка и звук идут с красной линии. " +
               "Тот же жест — клик по кадру 9:16. Клик по дорожке " +
               "перематывает; если ролик играл, после перемотки " +
               "нажмите пуск снова. В конце линия останавливается, " +
               "повторный пуск — с начала."
         }
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

   Text {
      objectName: "timelineHelp"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: timelineHandle.bottom
      anchors.margins: 8
      visible: timelineHost.clipCount === 0 && timelineHost.audioCount === 0
      color: Theme.textSecondary
      font.pixelSize: 12
      wrapMode: Text.WordWrap
      text: "Как работает таймлайн. 1) В папке слева нажмите «⋯» → " +
         "«Импорт видео» — ролик попадёт на V1, звук на A1. " +
         "2) Красная линия — текущее время; клик или протяжка по " +
         "дорожке перематывает кадр. 3) Треугольник справа (или клик " +
         "по кадру) — пуск со звуком. 4) Цветные блоки — клипы; клик " +
         "по блоку выделяет его. 5) Лезвие режет по линии. Экспорт — " +
         "белая кнопка в шапке."
   }

   Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: timelineHandle.bottom
      anchors.bottom: parent.bottom
      anchors.margins: 8
      spacing: 8
      visible: timelineHost.clipCount > 0 || timelineHost.audioCount > 0

      Column {
         width: 28
         spacing: 4
         Repeater {
            model: ["V1", "V2", "A1"]
            Text {
               width: 28
               height: 36
               text: modelData
               color: Theme.textSecondary
               font.pixelSize: 12
               verticalAlignment: Text.AlignVCenter
            }
         }
      }

      Item {
         id: plot
         width: parent.width - 36
         height: parent.height

         Column {
            objectName: "timelineTracks"
            anchors.fill: parent
            spacing: 4

            TrackRow {
               objectName: "trackV1"
               trackName: "v1"
            }
            TrackRow {
               objectName: "trackV2"
               trackName: "v2"
            }
            TrackRow {
               objectName: "trackA1"
               trackName: "a1"
            }
         }

         Repeater {
            objectName: "clipBlockRepeater"
            model: timelineHost.itemCount
            Rectangle {
               objectName: "clipBlock"
               readonly property string clipId:
                  timelineHost.document
                     ? timelineHost.document.clip_id_at(index) : ""
               readonly property string track:
                  timelineHost.document && clipId.length > 0
                     ? timelineHost.document.clip_track(clipId) : ""
               width: {
                  const span = timelineHost.plotSpan()
                  const duration = Math.max(
                     1, timelineHost.document
                        ? timelineHost.document.durationMs : 1)
                  const length = timelineHost.clipLength(clipId)
                  return Math.max(length / duration * span, 8)
               }
               height: 28
               radius: 4
               x: timelineHost.timeToX(
                  timelineHost.document && clipId.length > 0
                     ? timelineHost.document.clip_start(clipId) : 0)
               y: track === "v2" ? 40 : (track === "a1" ? 80 : 4)
               z: 0
               color: track === "a1" ? Theme.plot
                  : track === "v2" ? Theme.menu : Theme.selected
               border.width: timelineHost.document
                  && timelineHost.document.selectedClipId === clipId
                  ? 2 : 1
               border.color: timelineHost.document
                  && timelineHost.document.selectedClipId === clipId
                  ? Theme.link : Theme.outline
               Text {
                  anchors.fill: parent
                  anchors.margins: 4
                  text: track === "v2"
                     ? (timelineHost.document
                        ? timelineHost.document.clip_text(clipId) : "")
                     : track.toUpperCase()
                  color: Theme.text
                  font.pixelSize: 11
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
               }
            }
         }

         Rectangle {
            objectName: "playhead"
            visible: document !== null && document.hasClips
            width: 2
            color: Theme.brand
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            z: 3
            x: timelineHost.timeToX(
               document !== null ? document.playheadMs : 0)
         }

         SliderLike {
            id: seek
            objectName: "playheadSlider"
            visible: document !== null && document.hasClips
            anchors.fill: parent
            z: 1
         }
      }
   }

   component TrackRow: Rectangle {
      property string trackName: ""
      width: parent.width
      height: 36
      radius: 4
      color: Theme.raised
      border.color: Theme.outline
   }

   component SliderLike: MouseArea {
      cursorShape: Qt.PointingHandCursor
      property bool resumeAfterSeek: false
      hoverEnabled: true
      HintTip {
         visible: seekHover.hovered && !pressed
         text: "Перемотка. Клик или протяжка ставит красную линию и " +
            "кадр. Верхняя полоса — видео V1, средняя — текст V2, " +
            "нижняя — звук A1. Клик по цветному блоку ещё и " +
            "выделяет клип (синяя обводка). Если ролик играл, " +
            "после перемотки нажмите пуск, чтобы звук пошёл с нового места."
      }
      HoverHandler {
         id: seekHover
      }
      function seekTo(px) {
         if (document === null) {
            return
         }
         document.playheadMs = timelineHost.xToTime(px)
      }
      onPressed: function(event) {
         resumeAfterSeek = document !== null && document.playing
         if (resumeAfterSeek) {
            document.pause()
         }
         seekTo(event.x)
         const id = timelineHost.clipAt(event.x, event.y)
         if (id.length > 0) {
            document.selectedClipId = id
         }
      }
      onPositionChanged: function(event) {
         if (pressed) {
            seekTo(event.x)
         }
      }
      onReleased: {
         if (resumeAfterSeek && document !== null) {
            document.play()
         }
         resumeAfterSeek = false
      }
      onClicked: function(event) { seekTo(event.x) }
   }
}
