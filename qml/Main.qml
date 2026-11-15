import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models

ApplicationWindow {
   id: shell
   objectName: "mainWindow"
   width: 1280
   height: 800
   visible: true
   title: "YouTube Creator"
   color: Theme.canvas
   property bool windowIconReady: false

   readonly property bool channelConnected: libraryStore.channelCount > 0
   readonly property string libraryDock: DockState.libraryDock
   readonly property string timelineDock: DockState.timelineDock
   readonly property string mediaDock: DockState.mediaDock
   readonly property int leftDockWidth: DockState.leftWidth
   readonly property int rightDockWidth: DockState.rightWidth
   readonly property int bottomDockHeight: DockState.bottomHeight
   property string dropTarget: ""
   property string activeTab: "library"
   property bool panelDragging: false
   property string analyticsKind: ""
   property string analyticsId: ""
   property int publishTick: 0
   property string publishPrivacy: "unlisted"
   property string firstPublishCid: ""
   readonly property string centerMode: analyticsKind.length > 0
      ? "analytics" : frameView.centerMode

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
         shell.close_analytics()
         projectDocument.open_short(pane.selectedId)
         if (projectDocument.hasRecovery) {
            center_recovery_dialog()
            recoveryDialog.open()
         }
      } else {
         projectDocument.close()
      }
   }

   function close_analytics() {
      analyticsKind = ""
      analyticsId = ""
   }

   function first_video_id(shortId) {
      const n = libraryStore.publication_count(shortId)
      for (let i = 0; i < n; ++i) {
         const pid = libraryStore.publication_id_at(shortId, i)
         const vid = libraryStore.publication_video_id(pid)
         if (vid.length > 0) {
            return vid
         }
      }
      return ""
   }

   function open_channel_stats(channelId) {
      libraryPane.select_entry("", "")
      analyticsKind = "channel"
      analyticsId = channelId
   }

   function open_video_stats(shortId) {
      const videoId = first_video_id(shortId)
      if (videoId.length === 0) {
         return
      }
      analyticsKind = "video"
      analyticsId = videoId
   }

   function open_publish() {
      const id = libraryPane.selectedId
      publishTitleField.text = libraryStore.short_name(id)
      publishDescriptionField.text = libraryStore.short_script(id)
      publishPrivacy = "unlisted"
      firstChannelCheck.checked = false
      const n = libraryStore.channelCount
      firstPublishCid = n > 0 ? channelAuth.channel_id_at(0) : ""
      publishChannelListModel.clear()
      for (let i = 0; i < n; ++i) {
         publishChannelListModel.append({
            cid: channelAuth.channel_id_at(i),
            title: channelAuth.channel_title_at(i)
         })
      }
      publishTick++
      center_publish_dialog()
      publishDialog.open()
   }

   function selected_publish_channels() {
      const list = []
      if (firstChannelCheck.checked && firstPublishCid.length > 0) {
         list.push(firstPublishCid)
      }
      const n = publishChannelListModel.count
      for (let i = 1; i < n; ++i) {
         const row = extraChannelChecks.itemAt(i - 1)
         if (row && row.checked) {
            list.push(row.cid)
         }
      }
      return list
   }

   function confirm_publish() {
      const channels = selected_publish_channels()
      if (channels.length === 0) {
         return
      }
      publisher.publish(
         libraryPane.selectedId,
         channels,
         publishTitleField.text,
         publishDescriptionField.text,
         publishPrivacy)
      publishTick++
   }

   function center_publish_dialog() {
      const host = shell.contentItem
      publishDialog.parent = host
      Qt.callLater(function() {
         publishDialog.x = Math.round(
            (host.width - publishDialog.width) / 2)
         publishDialog.y = Math.round(
            (host.height - publishDialog.height) / 2)
      })
   }

   function publication_status_text(channelId) {
      const pid = publisher.publication_id(
         libraryPane.selectedId, channelId)
      if (pid.length === 0) {
         return ""
      }
      const videoId = libraryStore.publication_video_id(pid)
      if (videoId.length > 0) {
         return videoId
      }
      const error = libraryStore.publication_error(pid)
      if (error.length > 0) {
         return error
      }
      return libraryStore.publication_status(pid)
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
   CSecretStore {
      id: secretStore
      objectName: "secretStore"
      Component.onCompleted: load()
   }
   CHttpTransport {
      id: httpTransport
      objectName: "httpTransport"
   }
   CPipeline {
      id: pipeline
      objectName: "pipeline"
      store: libraryStore
      document: projectDocument
      secrets: secretStore
      transport: httpTransport
   }
   CChannelAuth {
      id: channelAuth
      objectName: "channelAuth"
      store: libraryStore
      secrets: secretStore
      transport: httpTransport
   }
   CPublisher {
      id: publisher
      objectName: "publisher"
      store: libraryStore
      auth: channelAuth
      transport: httpTransport
      onFinished: shell.publishTick++
   }
   CStatsSync {
      id: statsSync
      objectName: "statsSync"
      store: libraryStore
      auth: channelAuth
      transport: httpTransport
   }
   ListModel {
      id: publishChannelListModel
      objectName: "publishChannelListModel"
   }

   header: HeaderBar {
      id: headerBar
      exportEnabled: projectDocument.hasClips
      publishEnabled: libraryPane.selectedKind === "short"
         && libraryPane.selectedId.length > 0
      channelAuth: channelAuth
      channelCount: libraryStore.channelCount
      onExportRequested: shell.run_export()
      onPublishRequested: shell.open_publish()
      onSettingsRequested: shell.open_settings()
      onConnectChannelRequested: channelAuth.start()
      onDisconnectChannelRequested:
         channelAuth.disconnect_channel(channelId)
      onChannelStatsRequested: shell.open_channel_stats(channelId)
   }

   function run_export() {
      exporter.export_current()
      center_export_dialog()
      exportDialog.open()
   }

   function open_settings() {
      settingsKeyField.text = ""
      settingsKlingKeyField.text = ""
      settingsGoogleSecretField.text = ""
      center_settings_dialog()
      settingsDialog.open()
   }

   function center_settings_dialog() {
      const host = shell.contentItem
      settingsDialog.parent = host
      Qt.callLater(function() {
         settingsDialog.x = Math.round(
            (host.width - settingsDialog.width) / 2)
         settingsDialog.y = Math.round(
            (host.height - settingsDialog.height) / 2)
      })
   }

   function accept_settings() {
      secretStore.baseUrl = settingsBaseField.text
      secretStore.chatModel = settingsChatField.text
      secretStore.ttsModel = settingsTtsField.text
      secretStore.voice = settingsVoiceField.text
      if (settingsKeyField.text.length > 0) {
         secretStore.apiKey = settingsKeyField.text
      }
      secretStore.klingBaseUrl = settingsKlingBaseField.text
      secretStore.klingModel = settingsKlingModelField.text
      if (settingsKlingKeyField.text.length > 0) {
         secretStore.klingApiKey = settingsKlingKeyField.text
      }
      secretStore.googleClientId = settingsGoogleIdField.text
      if (settingsGoogleSecretField.text.length > 0) {
         secretStore.googleClientSecret =
            settingsGoogleSecretField.text
      }
      secretStore.save()
      settingsKeyField.text = ""
      settingsKlingKeyField.text = ""
      settingsGoogleSecretField.text = ""
      settingsDialog.close()
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

            Item {
               Layout.fillWidth: true
               Layout.fillHeight: true

               FrameView {
                  id: frameView
                  document: projectDocument
                  anchors.fill: parent
                  visible: shell.centerMode !== "analytics"
               }
               AnalyticsView {
                  id: analyticsView
                  store: libraryStore
                  statsSync: statsSync
                  kind: shell.analyticsKind
                  targetId: shell.analyticsId
                  anchors.fill: parent
                  visible: shell.centerMode === "analytics"
               }
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
      pipeline: pipeline
      onSelectedIdChanged: shell.apply_selection()
      onSelectedKindChanged: shell.apply_selection()
      onEntryClicked: function(entryId, kind) {
         if (kind === "short") {
            shell.close_analytics()
         }
      }
      onStatsRequested: function(shortId) {
         shell.open_video_stats(shortId)
      }
   }

   TimelineHost {
      parent: shell.timelineDock === "left" ? leftDock.slot
         : shell.timelineDock === "right" ? rightDock.slot
         : bottomDock.slot
      anchors.fill: parent
      visible: shell.panel_visible("timeline")
         && shell.centerMode !== "analytics"
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

   Dialog {
      id: publishDialog
      objectName: "publishDialog"
      modal: true
      width: 440
      title: "Публикация"
      standardButtons: Dialog.NoButton
      background: Rectangle {
         objectName: "publishDialogSurface"
         color: Theme.menu
         radius: 12
      }
      onOpened: shell.center_publish_dialog()
      contentItem: ColumnLayout {
         spacing: 12
         TextField {
            id: publishTitleField
            objectName: "publishTitleField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Название"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: publishTitleField.activeFocus ? 2 : 1
               border.color: publishTitleField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: publishDescriptionField
            objectName: "publishDescriptionField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Описание"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: publishDescriptionField.activeFocus
                  ? 2 : 1
               border.color: publishDescriptionField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         Text {
            objectName: "publishQuotaLabel"
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Theme.textSecondary
            font.pixelSize: 12
            text: {
               shell.publishTick
               return "Осталось " + libraryStore.quota_remaining() +
                  " выгрузок сегодня. Локальный счёт, сброс в " +
                  "полночь PT."
            }
         }
         Column {
            id: publishChannelList
            objectName: "publishChannelList"
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
               visible: firstPublishCid.length > 0
               spacing: 8
               Layout.fillWidth: true
               Rectangle {
                  id: firstChannelCheck
                  objectName: firstPublishCid.length > 0
                     ? "publishChannelCheck-" + firstPublishCid
                     : "publishChannelCheck"
                  property bool checked: false
                  width: 20
                  height: 20
                  radius: 4
                  color: checked ? Theme.fill : "transparent"
                  border.color: Theme.outline
                  MouseArea {
                     anchors.fill: parent
                     onClicked: firstChannelCheck.checked =
                        !firstChannelCheck.checked
                  }
               }
               Text {
                  text: firstPublishCid.length > 0
                     ? libraryStore.channel_title(firstPublishCid)
                     : ""
                  color: Theme.text
                  font.pixelSize: 14
                  Layout.fillWidth: true
               }
               Text {
                  objectName: firstPublishCid.length > 0
                     ? "publishChannelStatus-" + firstPublishCid
                     : "publishChannelStatus"
                  color: Theme.textSecondary
                  font.pixelSize: 12
                  text: {
                     shell.publishTick
                     return shell.publication_status_text(
                        firstPublishCid)
                  }
               }
            }
            Repeater {
               id: extraChannelChecks
               model: Math.max(0, publishChannelListModel.count - 1)
               RowLayout {
                  property string cid:
                     publishChannelListModel.get(index + 1).cid
                  property alias checked: extraBox.checked
                  spacing: 8
                  Layout.fillWidth: true
                  Rectangle {
                     id: extraBox
                     objectName: "publishChannelCheck-" + cid
                     property bool checked: false
                     width: 20
                     height: 20
                     radius: 4
                     color: checked ? Theme.fill : "transparent"
                     border.color: Theme.outline
                     MouseArea {
                        anchors.fill: parent
                        onClicked: extraBox.checked = !extraBox.checked
                     }
                  }
                  Text {
                     text: publishChannelListModel.get(index + 1).title
                     color: Theme.text
                     font.pixelSize: 14
                     Layout.fillWidth: true
                  }
               }
            }
         }
         Row {
            spacing: 8
            Rectangle {
               objectName: "publishPrivacy-private"
               height: 32
               width: privacyPrivateLabel.implicitWidth + 24
               radius: 8
               color: shell.publishPrivacy === "private"
                  ? Theme.fill : Theme.tonal
               Text {
                  id: privacyPrivateLabel
                  anchors.centerIn: parent
                  text: "Личный"
                  color: shell.publishPrivacy === "private"
                     ? Theme.textInverse : Theme.text
                  font.pixelSize: 14
                  font.weight: 500
               }
               MouseArea {
                  anchors.fill: parent
                  onClicked: shell.publishPrivacy = "private"
               }
            }
            Rectangle {
               objectName: "publishPrivacy-unlisted"
               height: 32
               width: privacyUnlistedLabel.implicitWidth + 24
               radius: 8
               color: shell.publishPrivacy === "unlisted"
                  ? Theme.fill : Theme.tonal
               Text {
                  id: privacyUnlistedLabel
                  anchors.centerIn: parent
                  text: "По ссылке"
                  color: shell.publishPrivacy === "unlisted"
                     ? Theme.textInverse : Theme.text
                  font.pixelSize: 14
                  font.weight: 500
               }
               MouseArea {
                  anchors.fill: parent
                  onClicked: shell.publishPrivacy = "unlisted"
               }
            }
            Rectangle {
               objectName: "publishPrivacy-public"
               height: 32
               width: privacyPublicLabel.implicitWidth + 24
               radius: 8
               color: shell.publishPrivacy === "public"
                  ? Theme.fill : Theme.tonal
               Text {
                  id: privacyPublicLabel
                  anchors.centerIn: parent
                  text: "Открытый"
                  color: shell.publishPrivacy === "public"
                     ? Theme.textInverse : Theme.text
                  font.pixelSize: 14
                  font.weight: 500
               }
               MouseArea {
                  anchors.fill: parent
                  onClicked: shell.publishPrivacy = "public"
               }
            }
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "publishCancel"
               text: "Отмена"
               onClicked: publishDialog.close()
            }
            CapsuleButton {
               objectName: "publishConfirm"
               text: "Опубликовать"
               filled: true
               onClicked: shell.confirm_publish()
            }
         }
      }
   }

   Dialog {
      id: settingsDialog
      objectName: "settingsDialog"
      modal: true
      width: 400
      title: "Модели"
      standardButtons: Dialog.NoButton
      background: Rectangle {
         objectName: "settingsDialogSurface"
         color: Theme.menu
         radius: 12
      }
      onOpened: {
         settingsBaseField.text = secretStore.baseUrl
         settingsChatField.text = secretStore.chatModel
         settingsTtsField.text = secretStore.ttsModel
         settingsVoiceField.text = secretStore.voice
         settingsKeyField.text = ""
         settingsKlingBaseField.text = secretStore.klingBaseUrl
         settingsKlingModelField.text = secretStore.klingModel
         settingsKlingKeyField.text = ""
         settingsGoogleIdField.text = secretStore.googleClientId
         settingsGoogleSecretField.text = ""
         shell.center_settings_dialog()
      }
      contentItem: ColumnLayout {
         spacing: 12
         TextField {
            id: settingsBaseField
            objectName: "settingsBaseField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Адрес API"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsBaseField.activeFocus ? 2 : 1
               border.color: settingsBaseField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsChatField
            objectName: "settingsChatField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Модель чата"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsChatField.activeFocus ? 2 : 1
               border.color: settingsChatField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsTtsField
            objectName: "settingsTtsField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Модель голоса"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsTtsField.activeFocus ? 2 : 1
               border.color: settingsTtsField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsVoiceField
            objectName: "settingsVoiceField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Голос"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsVoiceField.activeFocus ? 2 : 1
               border.color: settingsVoiceField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsKeyField
            objectName: "settingsKeyField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            echoMode: TextInput.Password
            placeholderText: secretStore.hasKey
               ? "Ключ задан"
               : "Ключ API"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsKeyField.activeFocus ? 2 : 1
               border.color: settingsKeyField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsKlingBaseField
            objectName: "settingsKlingBaseField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Адрес Kling"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsKlingBaseField.activeFocus ? 2 : 1
               border.color: settingsKlingBaseField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsKlingModelField
            objectName: "settingsKlingModelField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Модель видео"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsKlingModelField.activeFocus
                  ? 2 : 1
               border.color: settingsKlingModelField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsKlingKeyField
            objectName: "settingsKlingKeyField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            echoMode: TextInput.Password
            placeholderText: secretStore.hasKlingKey
               ? "Ключ Kling задан"
               : "Ключ Kling"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsKlingKeyField.activeFocus ? 2 : 1
               border.color: settingsKlingKeyField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsGoogleIdField
            objectName: "settingsGoogleIdField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderText: "Google client id"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsGoogleIdField.activeFocus ? 2 : 1
               border.color: settingsGoogleIdField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         TextField {
            id: settingsGoogleSecretField
            objectName: "settingsGoogleSecretField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            echoMode: TextInput.Password
            placeholderText: secretStore.hasGoogleSecret
               ? "Секрет Google задан"
               : "Секрет Google"
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: settingsGoogleSecretField.activeFocus
                  ? 2 : 1
               border.color: settingsGoogleSecretField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "settingsCancel"
               text: "Отмена"
               onClicked: settingsDialog.close()
            }
            CapsuleButton {
               objectName: "settingsSave"
               text: "Сохранить"
               filled: true
               onClicked: shell.accept_settings()
            }
         }
      }
   }
}
