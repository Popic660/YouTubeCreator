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
   readonly property int rowCount: libraryModel ? libraryModel.count : 0
   readonly property bool libraryOpen: store !== null && store.opened

   property string menuFolderId: ""
   property string dialogMode: ""
   property string confirmKind: ""
   property string confirmShortId: ""
   property string selectedId: ""
   property string selectedKind: ""
   signal panelDragStarted()
   signal panelDragFinished()

   implicitWidth: Theme.libraryWidth
   color: Theme.canvas
   border.color: Theme.outline
   border.width: 1

   function select_entry(entryId, kind) {
      selectedId = entryId
      selectedKind = kind
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
      promptField.text = store.folder_prompt(menuFolderId)
      center_dialog(promptDialog)
      promptDialog.open()
   }

   function accept_prompt() {
      if (store !== null) {
         store.set_folder_prompt(menuFolderId, promptField.text)
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

   function accept_delete() {
      if (store !== null && confirmKind === "folder") {
         store.delete_folder(menuFolderId, true)
      }
      if (store !== null && confirmKind === "short") {
         store.delete_short(confirmShortId, true)
      }
      confirmDialog.close()
   }

   component CapsuleButton: Button {
      id: capsule
      property bool filled: false
      implicitHeight: Theme.buttonHeight
      leftPadding: 16
      rightPadding: 16
      font.pixelSize: Theme.buttonTextSize
      font.weight: 500
      background: Rectangle {
         radius: Theme.buttonRadius
         color: capsule.filled ? Theme.fill : Theme.tonal
      }
      contentItem: Text {
         text: capsule.text
         color: capsule.filled ? Theme.textInverse : Theme.text
         font: capsule.font
         horizontalAlignment: Text.AlignHCenter
         verticalAlignment: Text.AlignVCenter
      }
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

   ColumnLayout {
      anchors.fill: parent
      anchors.margins: 8
      spacing: 8

      CapsuleButton {
         objectName: "chooseLibraryButton"
         visible: !pane.libraryOpen
         text: "Выбрать папку"
         filled: true
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
         onClicked: folderDialog.open()
      }

      CapsuleButton {
         objectName: "createRootButton"
         visible: pane.libraryOpen
         text: "Создать папку"
         onClicked: pane.open_name_dialog("createRoot", "")
      }

      Item {
         id: libraryDragHandle
         objectName: "libraryDragHandle"
         property string panelId: "library"
         Layout.fillWidth: true
         Layout.preferredHeight: 32
         Rectangle {
            anchors.fill: parent
            color: Theme.menu
         }
         Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            text: "Папки"
            color: Theme.text
            font.pixelSize: 12
         }
         Item {
            id: libraryProxy
            width: 1
            height: 1
            Drag.keys: ["panel"]
            Drag.source: libraryDragHandle
            Drag.active: libraryPress.drag.active
            Drag.hotSpot.x: libraryPress.mouseX
            Drag.hotSpot.y: libraryPress.mouseY
         }
         MouseArea {
            id: libraryPress
            anchors.fill: parent
            drag.target: libraryProxy
            drag.threshold: 4
            cursorShape: Qt.SizeAllCursor
            onPressed: pane.panelDragStarted()
            onReleased: pane.panelDragFinished()
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
            width: rowColumn.width
            height: kind === "folder" ? 40 : shortCard.implicitHeight

            Item {
               id: ghost
               width: 1
               height: 1
               property string entryId: row.entryId
               property string kind: row.kind
               Drag.active: dragArea.drag.active
               Drag.source: ghost
               Drag.hotSpot.x: 1
               Drag.hotSpot.y: 1
            }

            Rectangle {
               anchors.fill: parent
               radius: 10
               visible: kind === "folder"
               color: pane.selectedId === row.entryId
                  ? Theme.selected : "transparent"
            }

            Repeater {
               model: row.depth
               Rectangle {
                  objectName: "nestLine"
                  x: 8 + index * 12
                  y: 0
                  width: 1
                  height: row.height
                  color: Theme.outline
               }
            }

            Glyph {
               objectName: "folderGlyph"
               visible: kind === "folder"
               x: row.depth * 12
               width: 16
               height: 16
               anchors.verticalCenter: parent.verticalCenter
               glyphName: "folder"
               strokeColor: Theme.text
            }

            Row {
               x: row.depth * 12 + (kind === "folder" ? 20 : 0)
               width: parent.width - x
               height: kind === "folder" ? 40 : implicitHeight
               spacing: 4

               Shape {
                  visible: kind === "folder" && row.hasChildren
                  width: 16
                  height: 16
                  anchors.verticalCenter: parent.verticalCenter
                  ShapePath {
                     strokeColor: Theme.textSecondary
                     strokeWidth: 2
                     fillColor: "transparent"
                     capStyle: ShapePath.RoundCap
                     joinStyle: ShapePath.RoundJoin
                     PathSvg {
                        path: row.expanded
                           ? "M6 9 L12 15 L18 9"
                           : "M9 6 L15 12 L9 18"
                     }
                  }
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
                  Rectangle {
                     objectName: "shortPlaceholder"
                     width: 72
                     height: 128
                     radius: 12
                     color: Theme.raised
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
            }

            MouseArea {
               id: dragArea
               anchors.fill: parent
               anchors.rightMargin: kind === "folder" ? 40 : 0
               drag.target: ghost
               drag.threshold: 12
               onClicked: {
                  if (row.kind === "folder") {
                     pane.libraryModel.toggle_id(row.entryId)
                  }
                  pane.select_entry(row.entryId, row.kind)
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
               objectName: "folderMenuButton"
               visible: kind === "folder"
               anchors.right: parent.right
               anchors.verticalCenter: parent.verticalCenter
               width: Theme.buttonHeight
               height: Theme.buttonHeight
               padding: 0
               onClicked: pane.open_menu(row.entryId)
               background: Rectangle {
                  radius: Theme.buttonRadius
                  color: Theme.tonal
               }
               contentItem: Text {
                  text: "..."
                  color: Theme.text
                  font.pixelSize: 14
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
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
      width: 320
      standardButtons: Dialog.NoButton
      background: Rectangle {
         color: Theme.menu
         radius: 12
      }
      onOpened: pane.center_dialog(this)
      contentItem: ColumnLayout {
         spacing: 12
         Text {
            id: inheritedPrompt
            objectName: "inheritedPrompt"
            Layout.fillWidth: true
            visible: text.length > 0
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
         }
         TextField {
            id: promptField
            objectName: "promptField"
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: 14
            color: Theme.text
            placeholderTextColor: Theme.textDisabled
            background: Rectangle {
               radius: 4
               color: "transparent"
               border.width: promptField.activeFocus ? 2 : 1
               border.color: promptField.activeFocus
                  ? Theme.link : Theme.outline
            }
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
            text: "Удалить вместе с роликами?"
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
               onClicked: confirmDialog.close()
            }
            CapsuleButton {
               objectName: "confirmAccept"
               text: "Удалить"
               filled: true
               onClicked: pane.accept_delete()
            }
         }
      }
   }
}
