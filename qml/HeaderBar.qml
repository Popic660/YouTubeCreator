import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
   id: header
   objectName: "headerBar"
   property alias query: searchText.text
   property bool exportEnabled: false
   property var channelAuth: null
   property int channelCount: 0
   signal exportRequested()
   signal settingsRequested()
   signal connectChannelRequested()
   signal disconnectChannelRequested(string channelId)

   function channelIdAt(index) {
      if (!channelAuth) {
         return ""
      }
      return channelAuth.channel_id_at(index)
   }

   function channelTitleAt(index) {
      if (!channelAuth) {
         return ""
      }
      return channelAuth.channel_title_at(index)
   }

   component ChannelMenuItem: MenuItem {
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
            color: searchHover.hovered || searchPress.pressed
               ? Theme.tonalHover : Theme.searchButton
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
            HoverHandler {
               id: searchHover
            }
            MouseArea {
               id: searchPress
               anchors.fill: parent
               hoverEnabled: true
               acceptedButtons: Qt.NoButton
            }
            HintTip {
               visible: searchHover.hovered
               text: "Поиск по дереву слева. Введите часть имени " +
                  "папки или ролика — список сузится. Очистите поле, " +
                  "чтобы снова увидеть всё."
            }
         }
      }

      Item {
         Layout.fillWidth: true
      }

      Item {
         Layout.alignment: Qt.AlignVCenter
         implicitWidth: exportButton.implicitWidth
         implicitHeight: exportButton.implicitHeight
         Layout.preferredWidth: implicitWidth
         Layout.preferredHeight: implicitHeight

         CapsuleButton {
            id: exportButton
            objectName: "exportButton"
            text: "Экспорт"
            filled: true
            enabled: header.exportEnabled
            hint: "Собрать вертикальный MP4 1080×1920. Как работать: " +
               "1) выберите ролик с клипами в дереве слева; " +
               "2) при необходимости подрежьте и разведите звук на " +
               "таймлайне; 3) нажмите «Экспорт». Файл пишется в " +
               "папку библиотеки exports/<id>.mp4. После записи " +
               "откроется окно с полным путём. Без клипов кнопка " +
               "серая. Звук в файле берётся с дорожки A1."
            onClicked: header.exportRequested()
         }
         HoverHandler {
            id: exportHover
         }
         HintTip {
            visible: !exportButton.enabled && exportHover.hovered
            text: exportButton.hint
         }
      }

      ToolButton {
         id: settingsBtn
         objectName: "settingsButton"
         Layout.alignment: Qt.AlignVCenter
         Layout.preferredWidth: Theme.buttonHeight
         Layout.preferredHeight: Theme.buttonHeight
         padding: 0
         hoverEnabled: true
         background: Rectangle {
            radius: Theme.buttonRadius
            color: Theme.faceTonal(settingsBtn.hovered, settingsBtn.down)
         }
         contentItem: Glyph {
            glyphName: "settings"
            strokeColor: Theme.text
         }
         onClicked: header.settingsRequested()
         HoverHandler {
            id: settingsHover
         }
         HintTip {
            visible: settingsHover.hovered
            text: "Ключ и модели чата и голоса. Хранятся в защищённом " +
               "хранилище Windows, не в библиотеке."
         }
      }

      ToolButton {
         id: channelBtn
         objectName: "channelMenuButton"
         Layout.alignment: Qt.AlignVCenter
         Layout.preferredWidth: Theme.buttonHeight
         Layout.preferredHeight: Theme.buttonHeight
         padding: 0
         hoverEnabled: true
         property string glyphSignature: channelGlyph.signature
         background: Rectangle {
            radius: Theme.buttonRadius
            color: Theme.faceTonal(channelBtn.hovered, channelBtn.down)
         }
         contentItem: Glyph {
            id: channelGlyph
            glyphName: "channelMenu"
            strokeColor: Theme.text
         }
         onClicked: channelMenu.popup()
         HoverHandler {
            id: channelHover
         }
         HintTip {
            objectName: "channelHint"
            visible: channelHover.hovered
            text: "Каналы YouTube. Подключите канал через вход Google. " +
               "Нужен client id в настройках. Публикация на этом " +
               "этапе не запускается."
         }
         Menu {
            id: channelMenu
            objectName: "channelMenu"
            padding: 8
            background: Rectangle {
               objectName: "channelMenuSurface"
               color: Theme.menu
               radius: 12
               implicitWidth: 280
               implicitHeight: 80
            }
            ChannelMenuItem {
               objectName: "connectChannelItem"
               text: "Подключить канал"
               onTriggered: header.connectChannelRequested()
            }
            Instantiator {
               model: header.channelCount
               delegate: QtObject {
                  required property int index
                  property string cid: header.channelIdAt(index)
                  property string ctitle: header.channelTitleAt(index)
                  property ChannelMenuItem titleItem: ChannelMenuItem {
                     objectName: "channelItem-" + cid
                     text: ctitle
                  }
                  property ChannelMenuItem offItem: ChannelMenuItem {
                     objectName: "disconnectChannel-" + cid
                     text: "Отключить · " + ctitle
                     onTriggered:
                        header.disconnectChannelRequested(cid)
                  }
               }
               onObjectAdded: function(index, object) {
                  channelMenu.insertItem(index * 2 + 1,
                     object.titleItem)
                  channelMenu.insertItem(index * 2 + 2, object.offItem)
               }
               onObjectRemoved: function(index, object) {
                  channelMenu.removeItem(object.titleItem)
                  channelMenu.removeItem(object.offItem)
               }
            }
         }
      }
   }
}
