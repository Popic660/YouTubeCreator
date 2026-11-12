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
      dropTarget = ""
   }

   function show_drop_target(dock) {
      dropTarget = dock
   }

   function clear_drop_target() {
      dropTarget = ""
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

   header: HeaderBar {
      id: headerBar
   }

   component DockBox: Rectangle {
      id: dock
      property string dockName: "right"
      property alias slot: slotItem
      readonly property bool occupied: shell.libraryDock === dockName
         || shell.timelineDock === dockName
      readonly property bool highlighted: shell.dropTarget === dockName
      objectName: dockName === "left" ? "dockLeft"
         : dockName === "right" ? "dockRight" : "dockBottom"
      color: Theme.canvas
      border.color: highlighted ? Theme.link : "transparent"
      border.width: highlighted ? 2 : 0

      Loader {
         id: tabLoader
         active: shell.libraryDock === dock.dockName
            && shell.timelineDock === dock.dockName
         z: 2
         sourceComponent: Row {
            objectName: "dockTabs"
            height: 32
            spacing: 4
            Button {
               objectName: "tabLibrary"
               text: "Папки"
               height: 32
               onClicked: shell.activeTab = "library"
            }
            Button {
               objectName: "tabTimeline"
               text: "Таймлайн"
               height: 32
               onClicked: shell.activeTab = "timeline"
            }
         }
      }

      Item {
         id: slotItem
         anchors.fill: parent
         anchors.topMargin: tabLoader.active ? 32 : 0
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
               DisabledTool { toolName: "toolSelect" }
               DisabledTool { toolName: "toolRazor" }
               DisabledTool { toolName: "toolHand" }
               DisabledTool { toolName: "toolText" }
               DisabledTool { toolName: "toolZoom" }
            }

            FrameView {
               Layout.fillWidth: true
               Layout.fillHeight: true
            }

            ToolColumn {
               objectName: "operationColumn"
               Layout.alignment: Qt.AlignTop
               DisabledTool { toolName: "opSplit" }
               DisabledTool { toolName: "opCrop" }
               DisabledTool { toolName: "opTransform" }
               DisabledTool { toolName: "opVolume" }
               DisabledTool { toolName: "opDelete" }
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

   LibraryPane {
      parent: shell.libraryDock === "left" ? leftDock.slot
         : shell.libraryDock === "bottom" ? bottomDock.slot
         : rightDock.slot
      anchors.fill: parent
      visible: shell.libraryDock !== shell.timelineDock
         || shell.activeTab === "library"
      onPanelDragStarted: shell.start_panel_drag()
      onPanelDragFinished: shell.end_panel_drag()
      store: libraryStore
      libraryModel: libraryModel
   }

   TimelineHost {
      parent: shell.timelineDock === "left" ? leftDock.slot
         : shell.timelineDock === "right" ? rightDock.slot
         : bottomDock.slot
      anchors.fill: parent
      visible: shell.libraryDock !== shell.timelineDock
         || shell.activeTab === "timeline"
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
}
