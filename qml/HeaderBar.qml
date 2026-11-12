import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
   id: header
   objectName: "headerBar"
   property alias query: searchText.text
   implicitHeight: Theme.headerHeight
   height: Theme.headerHeight
   color: Theme.canvas

   RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      spacing: 12

      Item {
         Layout.preferredWidth: Theme.buttonHeight
         Layout.preferredHeight: Theme.buttonHeight
         Layout.alignment: Qt.AlignVCenter

         Rectangle {
            objectName: "brandMark"
            anchors.centerIn: parent
            width: Theme.iconSize
            height: Theme.iconSize
            radius: 6
            color: Theme.brand
            property bool isPlayIcon: false
         }
      }

      Item {
         Layout.fillWidth: true
      }

      Row {
         objectName: "searchField"
         Layout.alignment: Qt.AlignVCenter
         height: Theme.searchHeight

         Rectangle {
            objectName: "searchInput"
            width: 360
            height: Theme.searchHeight
            color: Theme.searchFill
            border.color: Theme.searchBorder
            border.width: 1
            topLeftRadius: Theme.searchCornerRadius
            bottomLeftRadius: Theme.searchCornerRadius
            topRightRadius: 0
            bottomRightRadius: 0

            TextInput {
               id: searchText
               objectName: "searchText"
               anchors.fill: parent
               anchors.leftMargin: 16
               anchors.rightMargin: 8
               verticalAlignment: TextInput.AlignVCenter
               color: Theme.text
               font.pixelSize: Theme.buttonTextSize
               clip: true
               selectByMouse: true
            }
         }

         Rectangle {
            objectName: "searchButton"
            width: Theme.searchButtonWidth
            height: Theme.searchHeight
            color: Theme.searchButton
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: Theme.searchCornerRadius
            bottomRightRadius: Theme.searchCornerRadius

            Glyph {
               objectName: "searchGlyph"
               anchors.centerIn: parent
               width: Theme.iconSize
               height: Theme.iconSize
               glyphName: "search"
               strokeColor: "#f1f1f1"
            }
         }
      }

      Item {
         Layout.fillWidth: true
      }

      ToolButton {
         objectName: "channelMenuButton"
         Layout.alignment: Qt.AlignVCenter
         Layout.preferredWidth: Theme.buttonHeight
         Layout.preferredHeight: Theme.buttonHeight
         padding: 0
         property string glyphSignature: channelGlyph.signature
         background: Rectangle {
            radius: Theme.buttonRadius
            color: Theme.tonal
         }
         contentItem: Glyph {
            id: channelGlyph
            glyphName: "channelMenu"
            strokeColor: Theme.text
         }
         onClicked: {}
      }
   }
}
