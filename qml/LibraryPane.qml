import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Shapes

Rectangle {
   id: pane
   objectName: "libraryPane"
   property CLibraryStore store: null
   property CLibraryModel libraryModel: null
   property CPipeline pipeline: null
   readonly property int rowCount: libraryModel ? libraryModel.count : 0
   readonly property bool libraryOpen: store !== null && store.opened

   property string menuFolderId: ""
   property string dialogMode: ""
   property string confirmKind: ""
   property string confirmShortId: ""
   property string selectedId: ""
   property string selectedKind: ""
   property string panelId: "library"
   signal panelDragStarted()
   signal panelDragFinished()
   signal entryClicked(string entryId, string kind)
   signal statsRequested(string shortId)

   implicitWidth: Theme.libraryWidth
   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1

   function select_entry(entryId, kind) {
      selectedId = entryId
      selectedKind = kind
   }

   function activate_entry(entryId, kind, mouse) {
      select_entry(entryId, kind)
      entryClicked(entryId, kind)
      if (mouse && mouse.button === Qt.RightButton) {
         if (kind === "short") {
            open_short_menu(entryId)
         } else {
            open_menu(entryId)
         }
         return
      }
      if (kind === "folder" && libraryModel !== null) {
         libraryModel.toggle_id(entryId)
      }
   }

   function apply_library_folder(value) {
      if (store !== null && store.open(value)) {
         store.remember()
      }
   }

   function decline_library_folder() {
   }

   function center_dialog(dialog) {
      const host = Window.window.contentItem
      dialog.parent = host
      Qt.callLater(function() {
         dialog.x = Math.round((host.width - dialog.width) / 2)
         dialog.y = Math.round((host.height - dialog.height) / 2)
      })
   }

   function format_char_count(count) {
      const n = Math.max(0, count)
      const mod100 = n % 100
      const mod10 = n % 10
      let word = "символов"
      if (mod100 < 11 || mod100 > 14) {
         if (mod10 === 1) {
            word = "символ"
         } else if (mod10 >= 2 && mod10 <= 4) {
            word = "символа"
         }
      }
      return n + " " + word
   }

   function handle_drop(sourceId, sourceKind, targetFolderId) {
      if (store === null) {
         return false
      }
      if (sourceKind === "short") {
         return store.move_short(sourceId, targetFolderId)
      }
      if (sourceKind === "folder") {
         return store.reparent_folder(sourceId, targetFolderId)
      }
      return false
   }

   function open_menu(folderId) {
      menuFolderId = folderId
      folderMenu.popup(pane)
   }

   function open_name_dialog(mode, initialText) {
      dialogMode = mode
      nameField.text = initialText
      center_dialog(nameDialog)
      nameDialog.open()
   }

   function accept_name() {
      if (store === null) {
         nameDialog.close()
         return
      }
      const value = nameField.text
      if (dialogMode === "createRoot") {
         store.create_folder("", value)
      } else if (dialogMode === "createChild") {
         store.create_folder(menuFolderId, value)
      } else if (dialogMode === "createShort") {
         store.create_short(menuFolderId, value)
      } else if (dialogMode === "renameFolder") {
         store.rename_folder(menuFolderId, value)
      }
      nameDialog.close()
   }

   function open_prompt_dialog() {
      if (store === null) {
         return
      }
      const parentId = store.folder_parent(menuFolderId)
      inheritedPrompt.text = parentId.length === 0
         ? ""
         : store.effective_prompt(parentId)
      promptEditor.text = store.folder_prompt(menuFolderId)
      center_dialog(promptDialog)
      promptDialog.open()
   }

   function accept_prompt() {
      if (store !== null) {
         store.set_folder_prompt(menuFolderId, promptEditor.text)
      }
      promptDialog.close()
   }

   function begin_delete_folder() {
      if (store === null) {
         return
      }
      if (store.folder_needs_confirmation(menuFolderId)) {
         confirmKind = "folder"
         center_dialog(confirmDialog)
         confirmDialog.open()
         return
      }
      store.delete_folder(menuFolderId, false)
   }

   function open_short_menu(shortId) {
      confirmShortId = shortId
      shortMenu.popup(pane)
   }

   function open_topic_dialog() {
      if (store === null || confirmShortId.length === 0) {
         return
      }
      topicEditor.text = store.short_topic(confirmShortId)
      center_dialog(topicDialog)
      topicDialog.open()
   }

   function accept_topic() {
      if (store === null) {
         topicDialog.close()
         return
      }
      store.set_topic(confirmShortId, topicEditor.text)
      if (topicEditor.text.trim().length === 0) {
         topicDialog.close()
         return
      }
      if (pipeline !== null) {
         pipeline.run(confirmShortId)
      }
      topicDialog.close()
   }

   function begin_delete_short(shortId) {
      if (store === null || !shortId || shortId.length === 0) {
         return
      }
      confirmShortId = shortId
      confirmKind = "short"
      center_dialog(confirmDialog)
      confirmDialog.open()
   }

   function accept_delete() {
      if (store !== null && confirmKind === "folder") {
         store.delete_folder(menuFolderId, true)
      }
      if (store !== null && confirmKind === "short") {
         const id = confirmShortId
         store.delete_short(id, true)
         if (selectedId === id) {
            select_entry("", "")
         }
      }
      confirmDialog.close()
   }

   component LibraryMenuItem: MenuItem {
      id: item
      implicitHeight: 44
      background: Rectangle {
         radius: 8
         color: item.highlighted ? Theme.tonal : "transparent"
      }
      contentItem: Text {
         text: item.text
         color: Theme.text
         font.pixelSize: 16
         leftPadding: 16
         verticalAlignment: Text.AlignVCenter
      }
   }

   component CountedTextArea: ColumnLayout {
      id: counted
      spacing: 8
      property alias text: area.text
      property alias placeholderText: area.placeholderText
      property string fieldObjectName: ""
      property string frameObjectName: ""
      property string scrollObjectName: ""
      property string countObjectName: ""

      Rectangle {
         id: fieldFrame
         objectName: counted.frameObjectName
         Layout.fillWidth: true
         implicitHeight: 240
         Layout.preferredHeight: 240
         radius: 4
         color: "transparent"
         border.width: area.activeFocus ? 2 : 1
         border.color: area.activeFocus ? Theme.link : Theme.outline
         clip: true

         Flickable {
            id: flick
            objectName: counted.scrollObjectName
            anchors.fill: parent
            anchors.margins: 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            TextArea.flickable: TextArea {
               id: area
               objectName: counted.fieldObjectName
               wrapMode: TextEdit.Wrap
               selectByMouse: true
               persistentSelection: true
               font.pixelSize: 14
               color: Theme.text
               placeholderTextColor: Theme.textDisabled
               leftPadding: 12
               rightPadding: 12
               topPadding: 8
               bottomPadding: 8
               background: Item {}
            }

            ScrollBar.vertical: ScrollBar {
               policy: ScrollBar.AsNeeded
            }
            ScrollBar.horizontal: ScrollBar {
               policy: ScrollBar.AlwaysOff
            }
         }
      }

      Text {
         id: countText
         objectName: counted.countObjectName
         Layout.fillWidth: true
         color: Theme.textSecondary
         font.pixelSize: 12
         text: pane.format_char_count(area.text.length)
      }
   }

   ColumnLayout {
      anchors.fill: parent
      anchors.margins: 8
      spacing: 8

      CapsuleButton {
         objectName: "chooseLibraryButton"
         visible: !pane.libraryOpen
         text: "Выбрать папку"
         filled: true
         hint: "Укажите папку на диске, где будут храниться ролики, " +
            "исходники и экспорты. Это корень библиотеки. Потом сюда " +
            "же можно вернуться через «Сменить папку»."
         onClicked: folderDialog.open()
      }

      Text {
         visible: !pane.libraryOpen
         text: "Выберите папку библиотеки"
         color: Theme.textSecondary
         font.pixelSize: 12
         wrapMode: Text.WordWrap
         Layout.fillWidth: true
      }

      CapsuleButton {
         objectName: "changeLibraryButton"
         visible: pane.libraryOpen
         text: "Сменить папку"
         hint: "Открыть другую папку библиотеки. Текущие ролики не " +
            "удаляются — просто закрывается это дерево."
         onClicked: folderDialog.open()
      }

      CapsuleButton {
         objectName: "createRootButton"
         visible: pane.libraryOpen
         text: "Создать папку"
         hint: "Новая папка в корне дерева. Внутри папки через «⋯»: " +
            "ещё папка или черновик ролика."
         onClicked: pane.open_name_dialog("createRoot", "")
      }

      PanelChrome {
         id: libraryDragHandle
         objectName: "libraryDragHandle"
         panelId: "library"
         title: "Папки"
         glyphName: "folder"
         Layout.fillWidth: true
         onPanelDragStarted: pane.panelDragStarted()
         onPanelDragFinished: pane.panelDragFinished()
         extra: CapsuleButton {
            id: deleteShortButton
            objectName: "deleteShortButton"
            visible: pane.selectedKind === "short"
               && pane.selectedId.length > 0
            implicitHeight: 32
            text: "Удалить"
            hint: "Удалить выбранный ролик из папки. Появится вопрос; " +
               "«Отмена» ничего не трогает. То же действие — правая " +
               "кнопка мыши по превью ролика."
            onClicked: pane.begin_delete_short(pane.selectedId)
         }
      }

      Loader {
         Layout.fillWidth: true
         active: pane.libraryOpen && pane.libraryModel !== null
            && pane.libraryModel.filter.length > 0
            && pane.libraryModel.count === 0
         sourceComponent: Text {
            objectName: "notFoundMessage"
            text: "Ничего не найдено"
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            width: pane.width - 16
         }
      }

      Flickable {
         objectName: "libraryList"
         Layout.fillWidth: true
         Layout.fillHeight: true
         clip: true
         contentWidth: width
         contentHeight: rowColumn.implicitHeight
         boundsBehavior: Flickable.StopAtBounds

         Column {
            id: rowColumn
            width: parent.width
            spacing: 4

            Repeater {
               model: pane.libraryModel
               delegate: Item {
            id: row
            readonly property string entryId: model.entryId
            readonly property string kind: model.kind
            readonly property string name: model.name
            readonly property int depth: model.depth
            readonly property bool expanded: model.expanded
            readonly property bool hasChildren: model.hasChildren
            readonly property bool hasPoster: !!model.hasPoster
            readonly property string posterPath: model.posterPath || ""
            readonly property int durationMs: model.durationMs || 0
            width: rowColumn.width
            height: kind === "folder" ? 40 : 40 + shortCard.implicitHeight

            Item {
               id: ghost
               width: 1
               height: 1
               property string entryId: row.entryId
               property string kind: row.kind
               Drag.active: dragArea.drag.active || shortDrag.drag.active
               Drag.source: ghost
               Drag.hotSpot.x: 1
               Drag.hotSpot.y: 1
            }

            Rectangle {
               anchors.fill: parent
               radius: 10
               visible: kind === "folder"
               color: pane.selectedId === row.entryId
                  ? Theme.tonal : "transparent"
            }

            Repeater {
               model: row.depth
               Rectangle {
                  objectName: "nestLine"
                  x: 8 + index * 16
                  y: 0
                  width: 1
                  height: row.height
                  color: Theme.textDisabled
               }
            }

            Glyph {
               objectName: "folderGlyph"
               visible: kind === "folder"
               x: 8 + row.depth * 16
               y: 8
               width: 24
               height: 24
               glyphName: "folder"
               strokeColor: Theme.text
            }

            Glyph {
               objectName: "shortGlyph"
               visible: kind === "short"
               x: 8 + row.depth * 16
               y: 8
               width: 24
               height: 24
               glyphName: "short"
               strokeColor: Theme.text
            }

            Row {
               x: 8 + row.depth * 16 + 24
               width: parent.width - x
               height: kind === "folder" ? 40 : implicitHeight
               spacing: 4

               Glyph {
                  visible: kind === "folder" && row.hasChildren
                  width: 18
                  height: 18
                  anchors.verticalCenter: parent.verticalCenter
                  glyphName: row.expanded ? "chevronDown"
                                          : "chevronRight"
                  strokeColor: Theme.textDisabled
               }

               Text {
                  visible: kind === "folder"
                  width: parent.width - 64
                  height: 40
                  text: row.name
                  color: Theme.text
                  font.pixelSize: 14
                  font.weight: 500
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
               }

               Column {
                  id: shortCard
                  visible: kind === "short"
                  width: 96
                  spacing: 4
                  Item {
                     id: shortHead
                     width: 96
                     height: headCol.implicitHeight
                     Column {
                        id: headCol
                        width: 96
                        spacing: 4
                        Rectangle {
                           objectName: "shortPlaceholder"
                           visible: !row.hasPoster
                           width: 72
                           height: 128
                           radius: 12
                           color: Theme.raised
                        }
                        Rectangle {
                           objectName: row.hasPoster
                              ? "shortPreview" : ""
                           visible: row.hasPoster
                           width: 72
                           height: 128
                           radius: 12
                           clip: true
                           color: Theme.canvas
                           layer.enabled: true
                           layer.smooth: true
                           Image {
                              anchors.fill: parent
                              source: row.hasPoster
                                 ? "file:///" + String(
                                    row.posterPath).replace(
                                       /\\/g, "/")
                                 : ""
                              fillMode: Image.PreserveAspectCrop
                           }
                           Loader {
                              active: row.hasPoster
                              anchors.right: parent.right
                              anchors.bottom: parent.bottom
                              anchors.margins: 4
                              sourceComponent: Rectangle {
                                 objectName: "durationBadge"
                                 height: 20
                                 width: badgeText.implicitWidth + 8
                                 radius: 4
                                 color: Theme.badge
                                 Text {
                                    id: badgeText
                                    objectName: "durationText"
                                    anchors.centerIn: parent
                                    text: {
                                       const total = Math.floor(
                                          row.durationMs / 1000)
                                       const minutes = Math.floor(
                                          total / 60)
                                       const seconds = total % 60
                                       return minutes + ":"
                                          + (seconds < 10
                                             ? "0" : "")
                                          + seconds
                                    }
                                    color: Theme.badgeText
                                    font.pixelSize: 12
                                    font.weight: 500
                                 }
                              }
                           }
                        }
                        Text {
                           objectName: "shortTitle"
                           width: 72
                           text: row.name
                           color: Theme.text
                           font.pixelSize: 14
                           font.weight: 500
                           wrapMode: Text.WordWrap
                           maximumLineCount: 2
                           elide: Text.ElideRight
                        }
                     }
                     MouseArea {
                        id: shortDrag
                        objectName: "shortDrag"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton |
                           Qt.RightButton
                        drag.target: ghost
                        drag.threshold: 12
                        onClicked: function(mouse) {
                           pane.activate_entry(
                              row.entryId, row.kind, mouse)
                        }
                     }
                  }
                  Loader {
                     id: pipelineLoader
                     active: kind === "short"
                     width: 96
                     sourceComponent: Column {
                        id: pipelineStatus
                        objectName: "pipelineStatus"
                        width: 96
                        spacing: 4
                        visible: pane.store !== null && (
                           (pane.pipeline &&
                              pane.pipeline.activeShortId ===
                                 row.entryId &&
                              (pane.pipeline.running ||
                               pane.pipeline.lastError.length > 0)) ||
                           pane.store.task_status(row.entryId) ===
                              "interrupted" ||
                           pane.store.task_status(row.entryId) ===
                              "error")
                        Text {
                           objectName: "pipelineStep"
                           width: parent.width
                           color: Theme.textSecondary
                           font.pixelSize: 12
                           wrapMode: Text.WordWrap
                           text: pane.pipeline &&
                              pane.pipeline.activeShortId ===
                                 row.entryId
                              ? pane.pipeline.currentStep
                              : pane.store.task_step(row.entryId)
                        }
                        Text {
                           objectName: "pipelineProgress"
                           width: parent.width
                           color: Theme.textSecondary
                           font.pixelSize: 12
                           text: String(pane.pipeline &&
                              pane.pipeline.activeShortId ===
                                 row.entryId
                              ? pane.pipeline.progress
                              : pane.store.task_progress(
                                 row.entryId))
                        }
                        Text {
                           objectName: "pipelineError"
                           width: parent.width
                           visible: text.length > 0
                           color: Theme.error
                           font.pixelSize: 12
                           wrapMode: Text.WordWrap
                           text: pane.pipeline &&
                              pane.pipeline.activeShortId ===
                                 row.entryId &&
                              pane.pipeline.lastError.length > 0
                              ? pane.pipeline.lastError
                              : pane.store.task_error(row.entryId)
                        }
                        CapsuleButton {
                           objectName: "pipelineCancel"
                           visible: pane.pipeline &&
                              pane.pipeline.running &&
                              pane.pipeline.activeShortId ===
                                 row.entryId
                           text: "Отмена"
                           onClicked: pane.pipeline.cancel()
                        }
                        CapsuleButton {
                           objectName: "pipelineRetry"
                           text: "Повтор"
                           onClicked: {
                              if (pane.pipeline) {
                                 pane.pipeline.retry(row.entryId)
                              }
                           }
                        }
                     }
                  }
               }
            }

            MouseArea {
               id: dragArea
               anchors.left: parent.left
               anchors.top: parent.top
               height: parent.height
               width: kind === "folder"
                  ? parent.width - 40
                  : 8 + row.depth * 16 + 24
               acceptedButtons: Qt.LeftButton | Qt.RightButton
               drag.target: ghost
               drag.threshold: 12
               onClicked: function(mouse) {
                  pane.activate_entry(row.entryId, row.kind, mouse)
               }
            }

            DropArea {
               anchors.fill: parent
               enabled: kind === "folder"
               onDropped: function(drop) {
                  if (drop.source) {
                     pane.handle_drop(
                        drop.source.entryId,
                        drop.source.kind,
                        row.entryId)
                  }
               }
            }

            ToolButton {
               id: folderMenuButton
               objectName: "folderMenuButton"
               visible: kind === "folder"
               anchors.right: parent.right
               anchors.verticalCenter: parent.verticalCenter
               width: Theme.buttonHeight
               height: Theme.buttonHeight
               padding: 0
               hoverEnabled: true
               onClicked: pane.open_menu(row.entryId)
               background: Rectangle {
                  radius: Theme.buttonRadius
                  color: Theme.faceTonal(
                     folderMenuButton.hovered, folderMenuButton.down)
               }
               contentItem: Text {
                  text: "..."
                  color: Theme.text
                  font.pixelSize: 14
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
               }
               HintTip {
                  visible: folderMenuButton.hovered
                  text: "Меню папки: создать вложенную папку, черновик, " +
                     "переименовать, удалить папку, промпт."
               }
            }
         }
            }
         }
      }
   }

   FolderDialog {
      id: folderDialog
      title: "Папка библиотеки"
      onAccepted: pane.apply_library_folder(selectedFolder)
      onRejected: pane.decline_library_folder()
   }

   Menu {
      id: shortMenu
      objectName: "shortMenu"
      padding: 8
      background: Rectangle {
         objectName: "shortMenuSurface"
         color: Theme.menu
         radius: 12
         implicitWidth: 240
         implicitHeight: 100
      }
      LibraryMenuItem {
         objectName: "menuTopicVoice"
         text: "Тема и голос"
         onTriggered: pane.open_topic_dialog()
      }
      LibraryMenuItem {
         objectName: "menuStats"
         text: "Статистика"
         onTriggered: {
            if (pane.store !== null &&
                pane.store.short_has_video(pane.confirmShortId)) {
               pane.statsRequested(pane.confirmShortId)
            }
         }
      }
      LibraryMenuItem {
         objectName: "menuDeleteShort"
         text: "Удалить ролик"
         onTriggered: pane.begin_delete_short(pane.confirmShortId)
      }
   }

   Menu {
      id: folderMenu
      objectName: "folderMenu"
      padding: 8
      background: Rectangle {
         objectName: "folderMenuSurface"
         color: Theme.menu
         radius: 12
         implicitWidth: 240
         implicitHeight: 240
      }
      LibraryMenuItem {
         objectName: "menuCreateFolder"
         text: "Создать папку"
         onTriggered: pane.open_name_dialog("createChild", "")
      }
      LibraryMenuItem {
         objectName: "menuCreateShort"
         text: "Создать ролик"
         onTriggered: pane.open_name_dialog("createShort", "")
      }
      LibraryMenuItem {
         objectName: "menuRename"
         text: "Переименовать"
         onTriggered: pane.open_name_dialog(
            "renameFolder",
            pane.store.folder_name(pane.menuFolderId))
      }
      LibraryMenuItem {
         objectName: "menuDelete"
         text: "Удалить"
         onTriggered: pane.begin_delete_folder()
      }
      LibraryMenuItem {
         objectName: "menuPrompt"
         text: "Изменить промпт"
         onTriggered: pane.open_prompt_dialog()
      }
   }

   Dialog {
      id: nameDialog
      objectName: "nameDialog"
      modal: true
      width: 320
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: pane.center_dialog(this)
      contentItem: ColumnLayout {
         spacing: 12
         TextField {
            id: nameField
            objectName: "nameField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: nameField.activeFocus ? 2 : 1
               border.color: nameField.activeFocus
                  ? Theme.link : Theme.outline
            }
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "nameCancel"
               text: "Отмена"
               onClicked: nameDialog.close()
            }
            CapsuleButton {
               objectName: "nameAccept"
               text: "Готово"
               filled: true
               onClicked: pane.accept_name()
            }
         }
      }
   }

   Dialog {
      id: promptDialog
      objectName: "promptDialog"
      modal: true
      width: 520
      padding: 16
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: pane.center_dialog(this)
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            objectName: "promptDialogTitle"
            Layout.fillWidth: true
            color: Theme.text
            font.pixelSize: 20
            font.weight: 700
            wrapMode: Text.WordWrap
            text: "Введите промт для папки"
         }
         Text {
            objectName: "promptDialogHint"
            Layout.fillWidth: true
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            text: "Общий стиль шортсов для роликов в папке."
         }
         Flickable {
            id: inheritedScroll
            objectName: "inheritedPromptScroll"
            visible: inheritedPrompt.text.length > 0
            Layout.fillWidth: true
            implicitHeight: Math.min(
               inheritedPrompt.implicitHeight, 96)
            Layout.preferredHeight: implicitHeight
            contentWidth: width
            contentHeight: inheritedPrompt.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Text {
               id: inheritedPrompt
               objectName: "inheritedPrompt"
               width: inheritedScroll.width
               color: Theme.textSecondary
               font.pixelSize: 12
               wrapMode: Text.WordWrap
            }
         }
         CountedTextArea {
            id: promptEditor
            Layout.fillWidth: true
            placeholderText: "Стиль, аудитория и назначение роликов"
            fieldObjectName: "promptField"
            frameObjectName: "promptFieldFrame"
            scrollObjectName: "promptScroll"
            countObjectName: "promptCharCount"
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "promptCancel"
               text: "Отмена"
               onClicked: promptDialog.close()
            }
            CapsuleButton {
               objectName: "promptAccept"
               text: "Готово"
               filled: true
               onClicked: pane.accept_prompt()
            }
         }
      }
   }

   Dialog {
      id: topicDialog
      objectName: "topicDialog"
      modal: true
      width: 520
      padding: 16
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: pane.center_dialog(this)
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            objectName: "topicDialogTitle"
            Layout.fillWidth: true
            color: Theme.text
            font.pixelSize: 20
            font.weight: 700
            wrapMode: Text.WordWrap
            text: "Введите тему и голос для видео"
         }
         Text {
            objectName: "topicDialogHint"
            Layout.fillWidth: true
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            text: "О чём этот ролик. Стиль берётся из промта папки."
         }
         CountedTextArea {
            id: topicEditor
            Layout.fillWidth: true
            placeholderText: "О чём этот ролик и какой голос"
            fieldObjectName: "topicField"
            frameObjectName: "topicFieldFrame"
            scrollObjectName: "topicScroll"
            countObjectName: "topicCharCount"
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "topicCancel"
               text: "Отмена"
               onClicked: topicDialog.close()
            }
            CapsuleButton {
               objectName: "topicGenerate"
               text: "Сгенерировать"
               filled: true
               onClicked: pane.accept_topic()
            }
         }
      }
   }

   Dialog {
      id: confirmDialog
      objectName: "confirmDialog"
      modal: true
      width: 320
      title: "Удалить?"
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: pane.center_dialog(this)
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            objectName: "confirmMessage"
            text: confirmKind === "short"
               ? "Удалить ролик из папки? Монтаж и копия файла " +
                 "пропадут. Отмена ничего не удалит."
               : "Удалить папку вместе с роликами внутри? Отмена " +
                 "ничего не удалит."
            color: Theme.text
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
         }
         RowLayout {
            Layout.alignment: Qt.AlignRight
            CapsuleButton {
               objectName: "confirmCancel"
               text: "Отмена"
               hint: "Закрыть окно. Ничего не удалится."
               onClicked: confirmDialog.close()
            }
            CapsuleButton {
               objectName: "confirmAccept"
               text: "Удалить"
               filled: true
               hint: "Да, удалить. Это нельзя отменить из программы."
               onClicked: pane.accept_delete()
            }
         }
      }
   }
}
