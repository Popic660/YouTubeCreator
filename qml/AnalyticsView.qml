import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
   id: view
   objectName: "analyticsView"
   property var store: null
   property var statsSync: null
   property string kind: "channel"
   property string targetId: ""
   property int periodDays: 28

   readonly property string payloadText: {
      if (store === null || targetId.length === 0) {
         return ""
      }
      return store.stats_payload(kind, targetId)
   }
   readonly property var payload: {
      if (payloadText.length === 0) {
         return ({})
      }
      try {
         return JSON.parse(payloadText)
      } catch (error) {
         return ({})
      }
   }
   readonly property var points: {
      const all = payload.points || []
      if (all.length === 0) {
         return []
      }
      const cut = all.length > periodDays
         ? all.slice(all.length - periodDays) : all
      return cut
   }
   readonly property string syncedLabel: {
      if (store === null || targetId.length === 0) {
         return ""
      }
      const ms = store.stats_synced_ms(kind, targetId)
      if (ms <= 0) {
         return ""
      }
      return new Date(ms).toLocaleString()
   }
   readonly property string missing: "нет в этом канале"

   function metricText(key) {
      const value = payload[key]
      if (value === undefined || value === null || value === "") {
         return "—"
      }
      return String(value)
   }

   function refresh_now() {
      if (statsSync !== null && targetId.length > 0) {
         statsSync.refresh(kind, targetId)
      }
   }

   ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      Text {
         objectName: "analyticsTitle"
         text: view.kind === "channel" ? "Статистика канала"
            : "Статистика ролика"
         color: Theme.text
         font.pixelSize: 20
         font.weight: 700
      }

      Row {
         spacing: 8

         Rectangle {
            objectName: "chip7"
            height: 32
            width: chip7Label.implicitWidth + 24
            radius: 8
            color: view.periodDays === 7 ? Theme.fill : Theme.tonal
            Text {
               id: chip7Label
               anchors.centerIn: parent
               text: "7"
               color: view.periodDays === 7 ? Theme.textInverse
                  : Theme.text
               font.pixelSize: 14
               font.weight: 500
            }
            MouseArea {
               anchors.fill: parent
               onClicked: view.periodDays = 7
            }
         }
         Rectangle {
            objectName: "chip28"
            height: 32
            width: chip28Label.implicitWidth + 24
            radius: 8
            color: view.periodDays === 28 ? Theme.fill : Theme.tonal
            Text {
               id: chip28Label
               anchors.centerIn: parent
               text: "28"
               color: view.periodDays === 28 ? Theme.textInverse
                  : Theme.text
               font.pixelSize: 14
               font.weight: 500
            }
            MouseArea {
               anchors.fill: parent
               onClicked: view.periodDays = 28
            }
         }
         Rectangle {
            objectName: "chip90"
            height: 32
            width: chip90Label.implicitWidth + 24
            radius: 8
            color: view.periodDays === 90 ? Theme.fill : Theme.tonal
            Text {
               id: chip90Label
               anchors.centerIn: parent
               text: "90"
               color: view.periodDays === 90 ? Theme.textInverse
                  : Theme.text
               font.pixelSize: 14
               font.weight: 500
            }
            MouseArea {
               anchors.fill: parent
               onClicked: view.periodDays = 90
            }
         }
      }

      GridLayout {
         columns: 3
         columnSpacing: 16
         rowSpacing: 8
         Layout.fillWidth: true
         Repeater {
            model: view.kind === "channel" ? [
               { key: "subscribers", label: "Подписчики" },
               { key: "views", label: "Просмотры" },
               { key: "watch_time", label: "Время просмотра" },
               { key: "avg_duration", label: "Средняя длительность" },
               { key: "likes", label: "Лайки" },
               { key: "impressions", label: "Показы" },
               { key: "ctr", label: "CTR" }
            ] : [
               { key: "views", label: "Просмотры" },
               { key: "likes", label: "Лайки" },
               { key: "comments", label: "Комментарии" },
               { key: "watch_time", label: "Время просмотра" },
               { key: "avg_duration", label: "Средняя длительность" },
               { key: "impressions", label: "Показы" },
               { key: "ctr", label: "CTR" }
            ]
            Column {
               Text {
                  text: modelData.label
                  color: Theme.textSecondary
                  font.pixelSize: 12
               }
               Text {
                  objectName: "metric-" + modelData.key
                  text: view.metricText(modelData.key)
                  color: Theme.text
                  font.pixelSize: 16
                  font.weight: 500
               }
            }
         }
      }

      Rectangle {
         id: plotSurface
         objectName: "plotSurface"
         Layout.fillWidth: true
         Layout.fillHeight: true
         radius: 12
         color: Theme.plot

         Text {
            visible: view.points.length === 0
            anchors.centerIn: parent
            text: view.payloadText.length === 0
               ? "Нет данных. Нажмите «Обновить»."
               : "Нет точек графика за период"
            color: Theme.textSecondary
            font.pixelSize: 12
         }

         Canvas {
            id: plotCanvas
            anchors.fill: parent
            anchors.margins: 12
            visible: view.points.length > 0
            onPaint: {
               const ctx = getContext("2d")
               ctx.clearRect(0, 0, width, height)
               const items = view.points
               let max = 1
               for (let i = 0; i < items.length; ++i) {
                  const value = Number(items[i].views || 0)
                  if (value > max) {
                     max = value
                  }
               }
               ctx.strokeStyle = Theme.textSecondary
               ctx.lineWidth = 1
               ctx.beginPath()
               ctx.moveTo(0, height - 1)
               ctx.lineTo(width, height - 1)
               ctx.stroke()
               ctx.strokeStyle = Theme.text
               ctx.lineWidth = 2
               ctx.beginPath()
               for (let i = 0; i < items.length; ++i) {
                  const x = items.length === 1 ? width / 2
                     : i * (width / (items.length - 1))
                  const y = height - 4 -
                     (Number(items[i].views || 0) / max) * (height - 8)
                  if (i === 0) {
                     ctx.moveTo(x, y)
                  } else {
                     ctx.lineTo(x, y)
                  }
               }
               ctx.stroke()
            }
         }
      }

      Text {
         objectName: "analyticsDelay"
         Layout.fillWidth: true
         wrapMode: Text.Wrap
         color: Theme.textSecondary
         font.pixelSize: 12
         text: "Данные YouTube. Задержка может быть до двух суток."
      }

      Text {
         objectName: "analyticsSynced"
         visible: view.syncedLabel.length > 0
         color: Theme.textSecondary
         font.pixelSize: 12
         text: "Обновлено: " + view.syncedLabel
      }

      RowLayout {
         Layout.alignment: Qt.AlignLeft
         CapsuleButton {
            objectName: "analyticsRefresh"
            text: "Обновить"
            filled: true
            onClicked: view.refresh_now()
         }
      }
   }

   onPointsChanged: plotCanvas.requestPaint()
   onPeriodDaysChanged: plotCanvas.requestPaint()
}
