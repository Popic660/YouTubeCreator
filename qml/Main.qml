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

   header: HeaderBar {}

   RowLayout {
      anchors.fill: parent
      spacing: 0

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

         TimelineHost {
            Layout.fillWidth: true
         }
      }

      LibraryPane {
         Layout.fillHeight: true
      }
   }
}
