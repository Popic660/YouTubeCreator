import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Rectangle {
   id: pane
   objectName: "mediaPane"
   property CLibraryStore store: null
   property CMediaModel mediaModel: null
   property bool gridMode: false
   property int lastScrubMs: -1
   property string selectedId: ""
   property string selectedKind: ""
   property string panelId: "media"
   readonly property int rowCount: mediaModel ? mediaModel.count : 0
   signal panelDragStarted()
   signal panelDragFinished()

   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1

   function hover_scrub(x, width, durationMs) {
      if (width <= 0 || durationMs <= 0) {
         lastScrubMs = 0
         return lastScrubMs
      }
      const t = Math.max(0, Math.min(1, x / width))
      lastScrubMs = Math.floor(t * durationMs)
      return lastScrubMs
   }

   function select_entry(entryId, kind) {
      selectedId = entryId
      selectedKind = kind
   }

   ColumnLayout {
      anchors.fill: parent
      anchors.margins: 8
      spacing: 8

      PanelChrome {
         id: mediaChrome
         Layout.fillWidth: true
         panelId: "media"
         title: "Медиа"
         glyphName: "bin"
         onPanelDragStarted: pane.panelDragStarted()
         onPanelDragFinished: pane.panelDragFinished()
         extra: Row {
            spacing: 4
            CapsuleButton {
               objectName: "importMediaButton"
               implicitHeight: 32
               text: "Импорт"
               hint: "Скопировать видео, звук или картинку в пул. " +
                  "Новый ролик не создаётся."
               onClicked: importDialog.open()
            }
            CapsuleButton {
               objectName: "importFolderButton"
               implicitHeight: 32
               text: "Папка"
               hint: "Импортировать папку как бины и ассеты."
               onClicked: folderImportDialog.open()
            }
            CapsuleButton {
               objectName: "mediaGridButton"
               implicitHeight: 32
               text: pane.gridMode ? "Список" : "Сетка"
               onClicked: pane.gridMode = !pane.gridMode
            }
         }
      }

      Loader {
         Layout.fillWidth: true
         active: pane.mediaModel !== null
            && pane.mediaModel.filter.length > 0
            && pane.mediaModel.count === 0
         sourceComponent: Text {
            objectName: "mediaNotFoundMessage"
            text: "Ничего не найдено"
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: pane.width - 16
         }
      }

      Flickable {
         Layout.fillWidth: true
         Layout.fillHeight: true
         clip: true
         contentWidth: width
         contentHeight: pane.gridMode ? gridWrap.implicitHeight
                                      : listColumn.implicitHeight
         boundsBehavior: Flickable.StopAtBounds

         Column {
            id: listColumn
            visible: !pane.gridMode
            width: parent.width
            spacing: 4

            Repeater {
               model: pane.mediaModel
               delegate: Item {
                  id: row
                  readonly property string entryId: model.entryId
                  readonly property string kind: model.kind
                  readonly property string name: model.name
                  readonly property int depth: model.depth
                  readonly property bool expanded: model.expanded
                  readonly property bool hasChildren: model.hasChildren
                  readonly property string glyph: model.glyphName
                  readonly property int durationMs: model.durationMs || 0
                  width: listColumn.width
                  height: 40

                  Rectangle {
                     anchors.fill: parent
                     radius: 10
                     color: pane.selectedId === row.entryId
                        || hover.containsMouse
                        ? Theme.tonal : "transparent"
                  }

                  Repeater {
                     model: row.depth
                     Rectangle {
                        objectName: "mediaNestLine"
                        x: 8 + index * 16
                        y: 0
                        width: 1
                        height: row.height
                        color: Theme.textDisabled
                     }
                  }

                  Glyph {
                     objectName: row.kind === "bin" ? "binGlyph"
                        : "assetGlyph"
                     x: 8 + row.depth * 16
                     width: 24
                     height: 24
                     anchors.verticalCenter: parent.verticalCenter
                     glyphName: row.expanded && row.kind === "bin"
                        ? "chevronDown"
                        : row.kind === "bin" && row.hasChildren
                           ? "chevronRight" : row.glyph
                     strokeColor: Theme.text
                  }

                  Text {
                     x: 36 + row.depth * 16
                     width: parent.width - x - 8
                     height: 40
                     text: row.name
                     color: Theme.text
                     font.pixelSize: 14
                     font.weight: 500
                     verticalAlignment: Text.AlignVCenter
                     elide: Text.ElideRight
                  }

                  MouseArea {
                     id: hover
                     anchors.fill: parent
                     hoverEnabled: true
                     onClicked: {
                        pane.select_entry(row.entryId, row.kind)
                        if (row.kind === "bin") {
                           pane.mediaModel.toggle_id(row.entryId)
                        }
                     }
                  }
               }
            }
         }

         Flow {
            id: gridWrap
            visible: pane.gridMode
            width: parent.width
            spacing: 8

            Repeater {
               model: pane.mediaModel
               delegate: Item {
                  visible: model.kind !== "bin"
                  width: 96
                  height: 128

                  Rectangle {
                     id: thumb
                     objectName: "mediaPreview"
                     width: 96
                     height: 72
                     radius: 12
                     color: Theme.raised
                     clip: true

                     MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: function(mouse) {
                           pane.hover_scrub(
                              mouse.x, thumb.width,
                              model.durationMs || 0)
                        }
                     }

                     Rectangle {
                        objectName: "mediaDurationBadge"
                        visible: model.durationMs > 0
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        height: 20
                        width: badgeLabel.implicitWidth + 8
                        radius: 4
                        color: Theme.badge
                        Text {
                           id: badgeLabel
                           anchors.centerIn: parent
                           text: Theme.formatClock(model.durationMs)
                           color: Theme.badgeText
                           font.pixelSize: 12
                           font.weight: 500
                        }
                     }
                  }

                  Text {
                     objectName: "mediaCardTitle"
                     anchors.top: thumb.bottom
                     anchors.topMargin: 4
                     width: 96
                     text: model.name
                     color: Theme.text
                     font.pixelSize: 14
                     wrapMode: Text.WordWrap
                     maximumLineCount: 2
                     elide: Text.ElideRight
                  }
               }
            }
         }
      }
   }

   FileDialog {
      id: importDialog
      objectName: "mediaImportDialog"
      title: "Импорт в пул"
      nameFilters: [
         "Медиа (*.mp4 *.mov *.mkv *.webm *.mp3 *.wav *.png *.jpg *.jpeg *.webp)"
      ]
      onAccepted: {
         if (pane.store !== null) {
            pane.store.import_media("", selectedFile)
         }
      }
   }

   FolderDialog {
      id: folderImportDialog
      title: "Импорт папки"
      onAccepted: {
         if (pane.store !== null) {
            pane.store.import_folder("", selectedFolder)
         }
      }
   }
}
