import QtQuick
import QtTest
import Creator

TestCase {
   name: "ShellTheme"
   when: windowShown

   Component {
      id: shellComponent
      Main {}
   }

   function createShell() {
      const shell = createTemporaryObject(shellComponent, null)
      verify(shell !== null)
      return shell
   }

   function test_canvasAndTextColors() {
      const shell = createShell()
      compare(shell.color, "#0f0f0f")
      compare(shell.textColor, "#f1f1f1")
      compare(shell.textSecondaryColor, "#aaaaaa")
      compare(shell.linkColor, "#3ea6ff")
   }

   function test_fontFamily() {
      const shell = createShell()
      tryVerify(function() { return shell.fontsReady })
      compare(shell.font.family, "Roboto")
   }

   function requireChild(root, name) {
      const item = findChild(root, name)
      verify(item !== null, name)
      return item
   }

   function test_emptyLayout() {
      const shell = createShell()
      const header = requireChild(shell, "headerBar")
      const frame = requireChild(shell, "frameView")
      const surface = requireChild(shell, "frameSurface")
      const timeline = requireChild(shell, "timelineHost")
      const library = requireChild(shell, "libraryPane")
      requireChild(shell, "toolColumn")
      requireChild(shell, "operationColumn")
      compare(header.height, 56)
      compare(frame.centerMode, "empty")
      compare(frame.hasFrameImage, false)
      compare(timeline.clipCount, 0)
      compare(library.rowCount, 0)
      tryVerify(function() { return surface.width > 0 && surface.height > 0 })
      verify(Math.abs(surface.width / surface.height - 9 / 16) < 0.02)
      const framePos = frame.mapToItem(shell.contentItem, 0, 0)
      const timePos = timeline.mapToItem(shell.contentItem, 0, 0)
      const libraryPos = library.mapToItem(shell.contentItem, 0, 0)
      verify(timePos.y >= framePos.y + frame.height - 1)
      verify(timePos.x + timeline.width <= libraryPos.x + 1)
      verify(Math.abs(library.height - shell.contentItem.height) < 2)
   }

   function test_toolsStayDisabled() {
      const shell = createShell()
      const names = [
         "toolSelect", "toolRazor", "toolHand", "toolText", "toolZoom",
         "opSplit", "opCrop", "opTransform", "opVolume", "opDelete"
      ]
      for (let i = 0; i < names.length; ++i) {
         const name = names[i]
         tryVerify(function() { return findChild(shell, name) !== null })
         const button = requireChild(shell, name)
         compare(button.enabled, false)
         compare(button.iconColor, "#717171")
         compare(button.height, 40)
         compare(button.radius, 20)
         verify(button.hint.length > 40)
         button.clicked()
      }
      compare(requireChild(shell, "frameView").centerMode, "empty")
      compare(requireChild(shell, "frameView").hasFrameImage, false)
      const exportButton = requireChild(shell, "exportButton")
      compare(exportButton.enabled, false)
      verify(exportButton.hint.indexOf("Экспорт") >= 0
         || exportButton.hint.indexOf("MP4") >= 0)
      verify(findChild(shell, "timelineHelp") !== null)
   }

   function test_searchDoesNotFillLibrary() {
      const shell = createShell()
      const field = requireChild(shell, "searchInput")
      const button = requireChild(shell, "searchButton")
      compare(requireChild(shell, "searchField").height, 40)
      compare(field.color, "#121212")
      compare(field.border.color, "#303030")
      compare(field.topLeftRadius, 40)
      compare(field.topRightRadius, 0)
      compare(field.bottomRightRadius, 0)
      compare(field.bottomLeftRadius, 40)
      compare(button.width, 64)
      compare(button.topLeftRadius, 0)
      compare(button.topRightRadius, 40)
      compare(button.bottomRightRadius, 40)
      compare(button.bottomLeftRadius, 0)
      requireChild(shell, "searchText").text = "query"
      compare(requireChild(shell, "libraryPane").rowCount, 0)
      verify(findChild(shell, "notFoundMessage") === null)
   }

   function test_settingsDialogSavesHasKey() {
      const shell = createShell()
      const button = requireChild(shell, "settingsButton")
      compare(button.height, 40)
      button.clicked()
      const dialog = requireChild(shell, "settingsDialog")
      tryVerify(function() { return dialog.visible })
      compare(requireChild(shell, "settingsDialogSurface").color,
         "#282828")
      compare(requireChild(shell, "settingsKeyField").background.radius, 4)
      const secrets = requireChild(shell, "secretStore")
      secrets.use_memory(true)
      secrets.clear_memory()
      requireChild(shell, "settingsKeyField").text = "sk-from-ui"
      requireChild(shell, "settingsSave").clicked()
      verify(secrets.hasKey)
      compare(requireChild(shell, "settingsKeyField").text, "")
      compare(secrets.apiKey, "")
      button.clicked()
      tryVerify(function() { return dialog.visible })
      const keyField = requireChild(shell, "settingsKeyField")
      compare(keyField.placeholderText,
         "Вставьте новый ключ, чтобы заменить")
      const hint = requireChild(shell, "settingsKeyHint")
      verify(hint.text.indexOf("Пустое поле") >= 0)
      keyField.text = "gsk-from-ui"
      requireChild(shell, "settingsSave").clicked()
      verify(secrets.hasKey)
      compare(keyField.text, "")
   }

   function test_settingsDialogWarnsGroqKeyOnOpenaiHost() {
      const shell = createShell()
      const secrets = requireChild(shell, "secretStore")
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.baseUrl = "https://api.openai.com"
      secrets.apiKey = "gsk_4EOLxxxxxxxxxxxxxxxxxwoPm"
      const button = requireChild(shell, "settingsButton")
      button.clicked()
      const dialog = requireChild(shell, "settingsDialog")
      tryVerify(function() { return dialog.visible })
      const hint = requireChild(shell, "settingsKeyHint")
      verify(hint.text.indexOf("gsk_4EOL") >= 0)
      verify(hint.text.indexOf("Пустое поле") >= 0)
      const urlHint = requireChild(shell, "settingsChatUrlHint")
      verify(urlHint.text.indexOf("api.groq.com") >= 0)
      requireChild(shell, "settingsBaseField").text =
         "https://api.openai.com"
      verify(hint.text.indexOf("нельзя слать на OpenAI") >= 0)
      compare(hint.color, "#ff5577")
   }

   function test_settingsDialogSavesHasKlingKey() {
      const shell = createShell()
      const button = requireChild(shell, "settingsButton")
      button.clicked()
      const dialog = requireChild(shell, "settingsDialog")
      tryVerify(function() { return dialog.visible })
      compare(requireChild(shell, "settingsDialogSurface").color,
         "#282828")
      compare(requireChild(shell, "settingsKlingKeyField")
         .background.radius, 4)
      compare(requireChild(shell, "settingsSave").height, 40)
      const secrets = requireChild(shell, "secretStore")
      secrets.use_memory(true)
      secrets.clear_memory()
      requireChild(shell, "settingsKlingBaseField").text =
         "https://api-singapore.klingai.com"
      requireChild(shell, "settingsKlingModelField").text =
         "kling-4.0-flash"
      requireChild(shell, "settingsKlingKeyField").text = "kling-from-ui"
      requireChild(shell, "settingsSave").clicked()
      verify(secrets.hasKlingKey)
      compare(requireChild(shell, "settingsKlingKeyField").text, "")
      compare(secrets.klingApiKey, "")
      compare(requireChild(shell, "settingsKlingKeyField")
         .placeholderText, "Ключ Kling задан")
   }

   function test_brandAndChannels() {
      const shell = createShell()
      const mark = requireChild(shell, "brandMark")
      compare(shell.title, "YouTube Creator")
      tryVerify(function() { return shell.windowIconReady })
      compare(mark.color, "#ff0033")
      compare(mark.isPlayIcon, false)
      compare(shell.channelConnected, false)
      verify(requireChild(shell, "channelHint").text.indexOf(
         "заглушка") < 0)
      requireChild(shell, "channelMenuButton").clicked()
      compare(shell.channelConnected, false)
      const menu = requireChild(shell, "channelMenu")
      tryVerify(function() { return menu.visible })
      compare(requireChild(shell, "channelMenuSurface").color,
         "#282828")
      verify(requireChild(shell, "connectChannelItem").visible)
      verify(findChild(shell, "channelLinkField") === null)
   }

   function test_settingsDialogSavesGoogleClient() {
      const shell = createShell()
      requireChild(shell, "settingsButton").clicked()
      const dialog = requireChild(shell, "settingsDialog")
      tryVerify(function() { return dialog.visible })
      compare(requireChild(shell, "settingsDialogSurface").color,
         "#282828")
      compare(requireChild(shell, "settingsGoogleSecretField")
         .background.radius, 4)
      compare(requireChild(shell, "settingsSave").height, 40)
      const secrets = requireChild(shell, "secretStore")
      secrets.use_memory(true)
      secrets.clear_memory()
      requireChild(shell, "settingsGoogleIdField").text =
         "google-from-ui"
      requireChild(shell, "settingsGoogleSecretField").text =
         "google-secret-from-ui"
      requireChild(shell, "settingsSave").clicked()
      verify(secrets.hasGoogleClient)
      compare(requireChild(shell, "settingsGoogleSecretField").text, "")
      compare(secrets.googleClientSecret, "")
      compare(requireChild(shell, "settingsGoogleSecretField")
         .placeholderText, "Секрет Google задан")
   }

   function test_geometryRestored() {
      const first = createShell()
      first.x = 30
      first.y = 40
      first.width = 1000
      first.height = 640
      first.close()
      const second = createShell()
      compare(second.x, 30)
      compare(second.y, 40)
      compare(second.width, 1000)
      compare(second.height, 640)
   }

   function test_geometryOffScreen() {
      const first = createShell()
      first.x = -40000
      first.y = -40000
      first.width = 500
      first.height = 400
      first.close()
      const again = createShell()
      const area = again.screen ? again.screen.availableGeometry : null
      verify(again.x !== -40000)
      verify(again.y !== -40000)
      if (area) {
         verify(again.x + again.width > area.x)
         verify(again.x < area.x + area.width)
         verify(again.y + again.height > area.y)
         verify(again.y < area.y + area.height)
      }
   }

   function test_defaultDocksAndChrome() {
      DockState.reset_layout()
      const shell = createShell()
      compare(DockState.mediaDock, "left")
      compare(DockState.libraryDock, "right")
      compare(DockState.timelineDock, "bottom")
      compare(requireChild(shell, "libraryChromeTitle").text, "Папки")
      compare(requireChild(shell, "mediaChromeTitle").text, "Медиа")
      compare(requireChild(shell, "frameView").centerMode, "empty")
      verify(findChild(shell, "mediaPane") !== null)
      verify(findChild(shell, "libraryPane") !== null)
      verify(findChild(shell, "timelineHost") !== null)
      verify(findChild(shell, "toolColumn") !== null)
   }

   function test_distinctGlyphs() {
      const shell = createShell()
      const names = [
         "toolSelect", "toolRazor", "toolHand", "toolText", "toolZoom",
         "opSplit", "opCrop", "opTransform", "opVolume", "opDelete"
      ]
      const seen = []
      for (let i = 0; i < names.length; ++i) {
         const button = requireChild(shell, names[i])
         verify(button.glyphSignature.length > 8)
         verify(seen.indexOf(button.glyphSignature) === -1)
         seen.push(button.glyphSignature)
         compare(button.iconColor, "#717171")
      }
      const channel = requireChild(shell, "channelMenuButton")
      verify(channel.glyphSignature.length > 8)
      verify(seen.indexOf(channel.glyphSignature) === -1)
   }

   function test_publishButtonFilledExportTonal() {
      const shell = createShell()
      const publish = requireChild(shell, "publishButton")
      const exportButton = requireChild(shell, "exportButton")
      compare(publish.filled, true)
      compare(exportButton.filled, false)
      compare(publish.enabled, false)
      compare(publish.height, 40)
      verify(requireChild(shell, "channelHint").text.indexOf(
         "публикация не запускается") < 0)
   }

   function test_analyticsViewHidesTimeline() {
      const shell = createShell()
      shell.open_channel_stats("UC1")
      compare(shell.centerMode, "analytics")
      const analytics = requireChild(shell, "analyticsView")
      verify(analytics.visible)
      compare(requireChild(shell, "plotSurface").color, "#3f3f3f")
      compare(requireChild(shell, "timelineHost").visible, false)
      verify(requireChild(shell, "libraryList") !== null)
      tryVerify(function() {
         return findChild(shell, "chip7") !== null
      })
      requireChild(shell, "chip7")
      requireChild(shell, "chip28")
      requireChild(shell, "chip90")
      verify(requireChild(shell, "analyticsDelay").text.indexOf(
         "двух суток") >= 0)
      requireChild(shell, "analyticsRefresh")
   }
}
