import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
   id: shell
   objectName: "mainWindow"
   width: 1280
   height: 800
   visible: true
   title: "YouTube Creator"
   color: Theme.canvas
   property bool windowIconReady: false

   readonly property bool channelConnected: false
   readonly property string libraryDock: DockState.libraryDock
   readonly property string timelineDock: DockState.timelineDock
   readonly property string mediaDock: DockState.mediaDock
   readonly property int leftDockWidth: DockState.leftWidth
   readonly property int rightDockWidth: DockState.rightWidth
   readonly property int bottomDockHeight: DockState.bottomHeight
   property string dropTarget: ""
   property string activeTab: "library"
   property bool panelDragging: false

   function start_panel_drag() {
      panelDragging = true
   }

   function end_panel_drag() {
      panelDragging = false
      dropTarget = ""
   }

   function place_panel(panel, dock) {
      if (panel === "library") {
         DockState.libraryDock = dock
      }
      if (panel === "timeline") {
         DockState.timelineDock = dock
      }
      if (panel === "media") {
         DockState.mediaDock = dock
      }
      activeTab = panel
      dropTarget = ""
   }

   function panels_in(dock) {
      const ids = []
      if (mediaDock === dock) {
         ids.push("media")
      }
      if (libraryDock === dock) {
         ids.push("library")
      }
      if (timelineDock === dock) {
         ids.push("timeline")
      }
      return ids
   }

   function panel_title(id) {
      if (id === "media") {
         return "Медиа"
      }
      if (id === "library") {
         return "Папки"
      }
      return "Таймлайн"
   }

   function panel_visible(id) {
      const dock = id === "media" ? mediaDock
         : id === "library" ? libraryDock : timelineDock
      const ids = panels_in(dock)
      if (ids.length <= 1) {
         return true
      }
      return activeTab === id
   }

   function show_drop_target(dock) {
      dropTarget = dock
   }

   function clear_drop_target() {
      dropTarget = ""
   }

   function apply_selection() {
      const pane = libraryPane
      if (pane.selectedKind === "short" && pane.selectedId.length > 0) {
         projectDocument.open_short(pane.selectedId)
         if (projectDocument.hasRecovery) {
            center_recovery_dialog()
            recoveryDialog.open()
         }
      } else {
         projectDocument.close()
      }
   }

   function center_recovery_dialog() {
      const host = shell.contentItem
      recoveryDialog.parent = host
      Qt.callLater(function() {
         recoveryDialog.x = Math.round(
            (host.width - recoveryDialog.width) / 2)
         recoveryDialog.y = Math.round(
            (host.height - recoveryDialog.height) / 2)
      })
   }

   function handle_tool(name) {
      const video = projectDocument.first_clip_on("v1")
      if (name === "toolSelect") {
         projectDocument.selectedClipId = video
      } else if (name === "toolRazor" || name === "opSplit") {
         const duration = Math.max(projectDocument.durationMs, 1)
         if (projectDocument.playheadMs <= 0 ||
             projectDocument.playheadMs >= duration) {
            projectDocument.playheadMs = Math.floor(duration / 2)
         }
         projectDocument.split_at_playhead()
      } else if (name === "toolHand") {
         projectDocument.set_transform(
            video, projectDocument.clip_scale(video),
            projectDocument.clip_offset_x(video) + 12,
            projectDocument.clip_offset_y(video))
      } else if (name === "toolZoom") {
         projectDocument.set_transform(
            video, projectDocument.clip_scale(video) * 1.25,
            projectDocument.clip_offset_x(video),
            projectDocument.clip_offset_y(video))
      } else if (name === "opCrop") {
         projectDocument.apply_cover()
      } else if (name === "opTransform") {
         projectDocument.set_transform(video, 1.2, 8, 8)
      } else if (name === "opVolume") {
         const audio = projectDocument.first_clip_on("a1")
         projectDocument.set_volume(audio, 0.4)
      } else if (name === "opDelete") {
         projectDocument.delete_selected_clip()
      } else if (name === "toolText") {
         projectDocument.add_text("Текст")
      }
   }

   FontLoader {
      id: robotoRegular
      source: "qrc:/fonts/Roboto-Regular.ttf"
   }
   FontLoader {
      id: robotoMedium
      source: "qrc:/fonts/Roboto-Medium.ttf"
   }
   FontLoader {
      id: robotoBold
      source: "qrc:/fonts/Roboto-Bold.ttf"
   }

   readonly property bool fontsReady: robotoRegular.status === FontLoader.Ready
      && robotoMedium.status === FontLoader.Ready
      && robotoBold.status === FontLoader.Ready
   readonly property color textColor: Theme.text
   readonly property color textSecondaryColor: Theme.textSecondary
   readonly property color linkColor: Theme.link

   font.family: fontsReady ? robotoRegular.name : "Arial"
   font.pixelSize: Theme.buttonTextSize

   background: Rectangle {
      color: Theme.canvas
   }

   Component.onCompleted: {
      windowIconReady = WindowState.apply_icon(shell)
      WindowState.restore_geometry(shell)
   }
   onClosing: function(close) {
      WindowState.save_geometry(shell)
   }

   CLibraryStore {
      id: libraryStore
      objectName: "libraryStore"
      Component.onCompleted: open_saved()
   }
   CLibraryModel {
      id: libraryModel
      objectName: "libraryModel"
      store: libraryStore
      filter: headerBar.query
   }
   CMediaModel {
      id: mediaModel
      objectName: "mediaModel"
      store: libraryStore
      filter: headerBar.query
   }
   CProjectDocument {
      id: projectDocument
      objectName: "projectDocument"
      store: libraryStore
   }
   CExporter {
      id: exporter
      objectName: "exporter"
      document: projectDocument
      compositor: frameView.compositor
   }
   CPreviewAudio {
      id: previewAudio
      objectName: "previewAudio"
      document: projectDocument
   }

   header: HeaderBar {
      id: headerBar
      exportEnabled: projectDocument.hasClips
      onExportRequested: shell.run_export()
   }

   function run_export() {
      exporter.export_current()
      center_export_dialog()
      exportDialog.open()
   }

   function center_export_dialog() {
      const host = shell.contentItem
      exportDialog.parent = host
      Qt.callLater(function() {
         exportDialog.x = Math.round((host.width - exportDialog.width) / 2)
         exportDialog.y = Math.round(
            (host.height - exportDialog.height) / 2)
      })
   }

   component DockTabChip: Rectangle {
      id: chip
      property string panelId: ""
      property string hostDock: ""
      visible: (panelId === "media" && shell.mediaDock === hostDock)
         || (panelId === "library" && shell.libraryDock === hostDock)
         || (panelId === "timeline" && shell.timelineDock === hostDock)
      height: 32
      width: tabLabel.implicitWidth + 16
      radius: 8
      color: shell.activeTab === panelId ? Theme.fill : Theme.tonal
      Text {
         id: tabLabel
         anchors.centerIn: parent
         text: shell.panel_title(chip.panelId)
         color: shell.activeTab === chip.panelId
            ? Theme.textInverse : Theme.text
         font.pixelSize: 14
         font.weight: 500
      }
      MouseArea {
         anchors.fill: parent
         onClicked: shell.activeTab = chip.panelId
      }
   }

   component DockBox: Rectangle {
      id: dock
      property string dockName: "right"
      property alias slot: slotItem
      readonly property int panelCount:
         (shell.mediaDock === dockName ? 1 : 0)
         + (shell.libraryDock === dockName ? 1 : 0)
         + (shell.timelineDock === dockName ? 1 : 0)
      readonly property bool occupied: panelCount > 0
      readonly property bool highlighted: shell.dropTarget === dockName
      objectName: dockName === "left" ? "dockLeft"
         : dockName === "right" ? "dockRight" : "dockBottom"
      color: Theme.canvas
      border.color: highlighted ? Theme.link : "transparent"
      border.width: highlighted ? 2 : 0

      Row {
         id: tabRow
         objectName: "dockTabs"
         visible: dock.panelCount > 1
         height: 32
         spacing: 4
         z: 2
         DockTabChip {
            objectName: "tabMedia"
            panelId: "media"
            hostDock: dock.dockName
         }
         DockTabChip {
            objectName: "tabLibrary"
            panelId: "library"
            hostDock: dock.dockName
         }
         DockTabChip {
            objectName: "tabTimeline"
            panelId: "timeline"
            hostDock: dock.dockName
         }
      }

      Item {
         id: slotItem
         anchors.fill: parent
         anchors.topMargin: dock.panelCount > 1 ? 32 : 0
      }

      DropArea {
         anchors.fill: parent
         enabled: shell.panelDragging
         z: 4
         keys: ["panel"]
         onEntered: shell.show_drop_target(dock.dockName)
         onExited: shell.clear_drop_target()
         onDropped: function(drop) {
            if (drop.source && drop.source.panelId) {
               shell.place_panel(drop.source.panelId, dock.dockName)
            }
         }
      }
   }

   component DockSplitter: MouseArea {
      property string axis: "width"
      property string dockName: "right"
      width: axis === "width" ? 4 : parent.width
      height: axis === "height" ? 4 : parent.height
      cursorShape: axis === "width" ? Qt.SplitHCursor : Qt.SplitVCursor
      property real pressPos: 0
      property int startSize: 0
      onPressed: function(mouse) {
         const point = mapToItem(shell.contentItem, mouse.x, mouse.y)
         pressPos = axis === "width" ? point.x : point.y
         if (dockName === "left") {
            startSize = shell.leftDockWidth
         } else if (dockName === "bottom") {
            startSize = shell.bottomDockHeight
         } else {
            startSize = shell.rightDockWidth
         }
      }
      onPositionChanged: function(mouse) {
         if (!pressed) {
            return
         }
         const point = mapToItem(shell.contentItem, mouse.x, mouse.y)
         const current = axis === "width" ? point.x : point.y
         const delta = current - pressPos
         if (dockName === "left") {
            DockState.leftWidth = startSize + delta
         } else if (dockName === "bottom") {
            DockState.bottomHeight = startSize - delta
         } else {
            DockState.rightWidth = startSize - delta
         }
      }
   }

   RowLayout {
      anchors.fill: parent
      spacing: 0

      DockBox {
         id: leftDock
         dockName: "left"
         visible: leftDock.occupied || leftDock.highlighted
         Layout.preferredWidth: leftDock.visible
            ? (leftDock.occupied ? shell.leftDockWidth : 48) : 0
         Layout.fillHeight: true
      }
      DockSplitter {
         objectName: "splitterLeft"
         dockName: "left"
         visible: leftDock.occupied
         Layout.preferredWidth: visible ? 4 : 0
         Layout.fillHeight: true
      }

      ColumnLayout {
         Layout.fillWidth: true
         Layout.fillHeight: true
         spacing: 0

         RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ToolColumn {
               objectName: "toolColumn"
               Layout.alignment: Qt.AlignTop
               DisabledTool {
                  toolName: "toolSelect"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "toolRazor"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "toolHand"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "toolText"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "toolZoom"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
            }

            FrameView {
               id: frameView
               document: projectDocument
               Layout.fillWidth: true
               Layout.fillHeight: true
            }

            ToolColumn {
               objectName: "operationColumn"
               Layout.alignment: Qt.AlignTop
               DisabledTool {
                  toolName: "opSplit"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "opCrop"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "opTransform"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "opVolume"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
               DisabledTool {
                  toolName: "opDelete"
                  toolsEnabled: projectDocument.hasClips
                  onActivated: function(name) {
                     shell.handle_tool(name)
                  }
               }
            }
         }

         DockSplitter {
            objectName: "splitterBottom"
            axis: "height"
            dockName: "bottom"
            visible: bottomDock.occupied
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 4 : 0
         }
         DockBox {
            id: bottomDock
            dockName: "bottom"
            visible: bottomDock.occupied || bottomDock.highlighted
            Layout.fillWidth: true
            Layout.preferredHeight: bottomDock.visible
               ? (bottomDock.occupied ? shell.bottomDockHeight : 32) : 0
         }
      }

      DockSplitter {
         objectName: "splitterRight"
         dockName: "right"
         visible: rightDock.occupied
         Layout.preferredWidth: visible ? 4 : 0
         Layout.fillHeight: true
      }
      DockBox {
         id: rightDock
         dockName: "right"
         visible: rightDock.occupied || rightDock.highlighted
         Layout.preferredWidth: rightDock.visible
            ? (rightDock.occupied ? shell.rightDockWidth : 48) : 0
         Layout.fillHeight: true
      }
   }

   MediaPane {
      id: mediaPane
      parent: shell.mediaDock === "right" ? rightDock.slot
         : shell.mediaDock === "bottom" ? bottomDock.slot
         : leftDock.slot
      anchors.fill: parent
      visible: shell.panel_visible("media")
      onPanelDragStarted: shell.start_panel_drag()
      onPanelDragFinished: shell.end_panel_drag()
      store: libraryStore
      mediaModel: mediaModel
   }

   LibraryPane {
      id: libraryPane
      parent: shell.libraryDock === "left" ? leftDock.slot
         : shell.libraryDock === "bottom" ? bottomDock.slot
         : rightDock.slot
      anchors.fill: parent
      visible: shell.panel_visible("library")
      onPanelDragStarted: shell.start_panel_drag()
      onPanelDragFinished: shell.end_panel_drag()
      store: libraryStore
      libraryModel: libraryModel
      onSelectedIdChanged: shell.apply_selection()
      onSelectedKindChanged: shell.apply_selection()
   }

   TimelineHost {
      parent: shell.timelineDock === "left" ? leftDock.slot
         : shell.timelineDock === "right" ? rightDock.slot
         : bottomDock.slot
      anchors.fill: parent
      visible: shell.panel_visible("timeline")
      document: projectDocument
      onPanelDragStarted: shell.start_panel_drag()
      onPanelDragFinished: shell.end_panel_drag()
   }

   Item {
      anchors.fill: parent
      visible: shell.panelDragging
      z: 30

      DropArea {
         width: 72
         anchors.left: parent.left
         anchors.top: parent.top
         anchors.bottom: parent.bottom
         keys: ["panel"]
         onEntered: shell.show_drop_target("left")
         onExited: shell.clear_drop_target()
         onDropped: function(drop) {
            if (drop.source && drop.source.panelId) {
               shell.place_panel(drop.source.panelId, "left")
            }
         }
         Rectangle {
            anchors.fill: parent
            color: Theme.link
            opacity: shell.dropTarget === "left" ? 0.35 : 0.12
         }
      }
      DropArea {
         width: 72
         anchors.right: parent.right
         anchors.top: parent.top
         anchors.bottom: parent.bottom
         keys: ["panel"]
         onEntered: shell.show_drop_target("right")
         onExited: shell.clear_drop_target()
         onDropped: function(drop) {
            if (drop.source && drop.source.panelId) {
               shell.place_panel(drop.source.panelId, "right")
            }
         }
         Rectangle {
            anchors.fill: parent
            color: Theme.link
            opacity: shell.dropTarget === "right" ? 0.35 : 0.12
         }
      }
      DropArea {
         height: 72
         anchors.left: parent.left
         anchors.right: parent.right
         anchors.bottom: parent.bottom
         keys: ["panel"]
         onEntered: shell.show_drop_target("bottom")
         onExited: shell.clear_drop_target()
         onDropped: function(drop) {
            if (drop.source && drop.source.panelId) {
               shell.place_panel(drop.source.panelId, "bottom")
            }
         }
         Rectangle {
            anchors.fill: parent
            color: Theme.link
            opacity: shell.dropTarget === "bottom" ? 0.35 : 0.12
         }
      }
   }

   Dialog {
      id: recoveryDialog
      objectName: "recoveryDialog"
      modal: true
      width: 400
      title: "Восстановление"
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: shell.center_recovery_dialog()
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.text
            font.pixelSize: 14
            text: "Есть снимок таймлайна после правки. " +
               "Восстановить его, отложить или отбросить?"
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "recoveryRestore"
               text: "Восстановить"
               filled: true
               onClicked: {
                  projectDocument.open_short(
                     libraryPane.selectedId, "restore")
                  recoveryDialog.close()
               }
            }
            CapsuleButton {
               objectName: "recoveryDefer"
               text: "Отложить"
               onClicked: recoveryDialog.close()
            }
            CapsuleButton {
               objectName: "recoveryDiscard"
               text: "Отбросить"
               onClicked: {
                  projectDocument.open_short(
                     libraryPane.selectedId, "discard")
                  recoveryDialog.close()
               }
            }
         }
      }
   }

   Dialog {
      id: exportDialog
      objectName: "exportDialog"
      modal: true
      width: 400
      title: exporter.lastPath.length > 0 ? "Экспорт готов" : "Экспорт"
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: shell.center_export_dialog()
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            objectName: "exportDialogText"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.text
            font.pixelSize: 14
            text: {
               if (exporter.lastPath.length > 0) {
                  return "Файл записан:\n" + exporter.lastPath +
                     "\n\nЭто вертикальный MP4 1080×1920. Звук — с " +
                     "дорожки A1. Можно открыть папку exports внутри " +
                     "библиотеки."
               }
               if (exporter.lastError.length > 0) {
                  return exporter.lastError
               }
               return "Экспорт не удался. Выберите ролик с клипами и " +
                  "нажмите «Экспорт» ещё раз."
            }
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "exportDialogClose"
               text: "Закрыть"
               filled: true
               onClicked: exportDialog.close()
            }
         }
      }
   }
}
