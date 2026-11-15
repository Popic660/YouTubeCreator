import QtQuick
import QtTest
import Creator
import CreatorTests 1.0

TestCase {
   id: testCase
   name: "Pipeline"
   when: windowShown

   TempDirectory { id: paths }
   CSceneParser { id: scenes }

   Component {
      id: shellComponent
      Main {}
   }

   function init() {
      paths.clear_library_path()
      DockState.reset_layout()
   }

   function cleanup() {
      paths.clear_library_path()
      DockState.reset_layout()
   }

   function createShell() {
      const shell = createTemporaryObject(shellComponent, null)
      verify(shell !== null)
      return shell
   }

   function requireChild(root, name) {
      const item = findChild(root, name)
      verify(item !== null, name)
      return item
   }

   function chatJson(text) {
      return JSON.stringify({
         choices: [{ message: { content: text } }]
      })
   }

   function klingCreate(id) {
      return JSON.stringify({
         code: 0,
         data: { id: id, task_id: id, status: "submitted" }
      })
   }

   function klingVideoDone(id, url) {
      return JSON.stringify({
         code: 0,
         data: [{
            id: id,
            status: "succeeded",
            outputs: [{ type: "video", url: url }]
         }]
      })
   }

   function klingImageCreate(id) {
      return JSON.stringify({
         code: 0,
         data: { task_id: id, task_status: "submitted" }
      })
   }

   function klingImageDone(id, url) {
      return JSON.stringify({
         code: 0,
         data: {
            task_id: id,
            task_status: "succeed",
            task_result: { images: [{ url: url }] }
         }
      })
   }

   function enqueueScene(transport, id) {
      transport.enqueue_json(klingCreate(id))
      transport.enqueue_json(klingVideoDone(
         id, "https://cdn.test/" + id + ".mp4"))
      transport.enqueue_file(paths.fixture_path("vertical-short.mp4"))
   }

   function enqueueCover(transport, dir) {
      transport.enqueue_json(klingImageCreate("img-1"))
      transport.enqueue_json(klingImageDone(
         "img-1", "https://cdn.test/cover.png"))
      transport.enqueue_file(paths.make_image(dir))
   }

   function saveChatKey(secrets) {
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
   }

   function tokenJson(refresh) {
      return JSON.stringify({
         access_token: "ya29.test",
         refresh_token: refresh,
         token_type: "Bearer"
      })
   }

   function channelsListJson(id, title) {
      return JSON.stringify({
         items: [{ id: id, snippet: { title: title } }]
      })
   }

   function enqueueConnect(transport, id, title, refresh) {
      transport.enqueue_json(tokenJson(refresh))
      transport.enqueue_json(channelsListJson(id, title))
   }

   function saveGoogleClient(secrets) {
      resetSecrets(secrets)
      secrets.googleClientId = "google-client-id"
      secrets.googleClientSecret = "google-client-secret"
      verify(secrets.save())
   }

   function saveBothKeys(secrets) {
      saveChatKey(secrets)
      secrets.klingApiKey = "kling-secret-key"
      verify(secrets.save())
   }

   function waitStopped(pipeline) {
      tryVerify(function() { return !pipeline.running }, 15000)
   }

   function resetSecrets(secrets) {
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
   }

   function test_secretStoreMemoryOmitsKeyFromLibrary() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const secrets = requireChild(shell, "secretStore")
      resetSecrets(secrets)
      secrets.baseUrl = "https://example.test"
      secrets.chatModel = "chat-x"
      secrets.ttsModel = "tts-x"
      secrets.voice = "alloy"
      secrets.apiKey = "sk-secret-key"
      verify(secrets.save())
      verify(secrets.hasKey)
      compare(secrets.apiKey, "")
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("sk-secret-key") < 0)
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      const project = requireChild(shell, "projectDocument")
      verify(project.open_short(id))
      project.save()
      const json = paths.read_text(
         dir + "/shorts/" + id + "/project.json")
      verify(json.indexOf("sk-secret-key") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_secretStoreReloadsSettingsWithoutKeyText() {
      const secrets = requireChild(createShell(), "secretStore")
      resetSecrets(secrets)
      secrets.baseUrl = "https://reload.test"
      secrets.chatModel = "chat-reload"
      secrets.ttsModel = "tts-reload"
      secrets.voice = "nova"
      secrets.apiKey = "sk-reload"
      verify(secrets.save())
      const shell = createShell()
      const again = requireChild(shell, "secretStore")
      again.use_memory(true)
      verify(again.load())
      compare(again.baseUrl, "https://reload.test")
      compare(again.chatModel, "chat-reload")
      compare(again.ttsModel, "tts-reload")
      compare(again.voice, "nova")
      verify(again.hasKey)
      compare(again.apiKey, "")
   }

   function test_chatPostRecordsTopicAndPrompt() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Scene one"))
      const folder = store.create_folder("", "Film")
      store.set_folder_prompt(folder, "Warm voice")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "City night"))
      pipeline.pauseAfterText = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return store.short_script(id).length > 0
      })
      verify(transport.lastUrl.indexOf("/v1/chat/completions") >= 0)
      verify(transport.lastBody.indexOf("City night") >= 0)
      verify(transport.lastBody.indexOf("Warm voice") >= 0)
      verify(transport.lastBody.indexOf("scenes") >= 0)
      pipeline.cancel()
      store.close()
      paths.remove_tree(dir)
   }

   function test_chatShowsApiErrorMessage() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(
         "{\"error\":{\"message\":\"Incorrect API key provided\"}}")
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(pipeline.lastError, "Incorrect API key provided")
      compare(store.short_script(id), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_runWithoutKeySkipsTransport() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      verify(store.open(dir))
      resetSecrets(secrets)
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(!pipeline.run(id))
      compare(transport.callCount, 0)
      compare(pipeline.needsSettingsMessage, "Нужны настройки")
      compare(store.short_script(id), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_speechRequestWritesVoiceClip() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Narration text"))
      const wav = paths.make_wav(dir)
      transport.enqueue_file(wav)
      const folder = store.create_folder("", "Film")
      const shortsBefore = store.short_count()
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      compare(store.short_status(id), "draft")
      verify(pipeline.run(id))
      compare(store.short_status(id), "generating")
      compare(pipeline.currentStep, "text")
      waitStopped(pipeline)
      compare(store.short_status(id), "draft")
      compare(store.short_script(id), "Narration text")
      compare(store.short_count(), shortsBefore + 1)
      compare(store.asset_count(), 1)
      verify(project.first_clip_on("a1").length > 0)
      compare(project.first_clip_on("v1"), "")
      verify(transport.lastUrl.indexOf("/v1/audio/speech") >= 0)
      verify(transport.lastBody.indexOf("Narration text") >= 0)
      const rel = store.asset_relpath(project.clip_asset_id(
         project.first_clip_on("a1")))
      verify(paths.file_exists(dir + "/" + rel))
      store.close()
      paths.remove_tree(dir)
   }

   function test_cancelTextLeavesNoScript() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Should not stick"))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(pipeline.run(id))
      pipeline.cancel()
      waitStopped(pipeline)
      compare(store.short_script(id), "")
      compare(store.short_status(id), "draft")
      store.close()
      paths.remove_tree(dir)
   }

   function test_cancelVoiceKeepsScript() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Keep me"))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      pipeline.pauseAfterText = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return store.short_script(id) === "Keep me"
      })
      compare(pipeline.currentStep, "voice")
      pipeline.cancel()
      waitStopped(pipeline)
      compare(store.short_script(id), "Keep me")
      compare(project.first_clip_on("a1"), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_voiceErrorKeepsScriptAndRetrySkipsChat() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Kept script"))
      transport.enqueue_error("tts down")
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(store.short_script(id), "Kept script")
      compare(project.first_clip_on("a1"), "")
      compare(store.task_status(id), "error")
      const chats = transport.chatCount
      const wav = paths.make_wav(dir)
      transport.enqueue_file(wav)
      verify(pipeline.retry(id))
      waitStopped(pipeline)
      compare(transport.chatCount, chats)
      compare(transport.speechCount, 2)
      verify(project.first_clip_on("a1").length > 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_runningTaskInterruptedOnOpen() {
      const dir = paths.make()
      const store = requireChild(createShell(), "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_script(id, "Already there"))
      verify(store.insert_task(id, "voice", "running").length > 0)
      store.set_short_status(id, "generating")
      store.close()
      const again = requireChild(createShell(), "libraryStore")
      verify(again.open(dir))
      compare(again.task_status(id), "interrupted")
      compare(again.short_script(id), "Already there")
      compare(again.short_status(id), "draft")
      again.close()
      paths.remove_tree(dir)
   }

   function test_cardShowsProgressCancelRetryAndError() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const pane = requireChild(shell, "libraryPane")
      const model = requireChild(shell, "libraryModel")
      verify(store.open(dir))
      resetSecrets(secrets)
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Card script"))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      model.toggle_id(folder)
      tryVerify(function() { return model.count >= 2 })
      verify(store.set_topic(id, "Topic"))
      pipeline.pauseAfterText = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return findChild(pane, "pipelineProgress") !== null
      })
      requireChild(pane, "pipelineStep")
      requireChild(pane, "pipelineCancel")
      tryVerify(function() {
         return store.short_script(id).length > 0
      })
      transport.enqueue_error("boom")
      pipeline.resume()
      waitStopped(pipeline)
      tryVerify(function() {
         const error = findChild(pane, "pipelineError")
         return error !== null && error.text.indexOf("boom") >= 0
      })
      requireChild(pane, "pipelineRetry")
      store.close()
      paths.remove_tree(dir)
   }

   function test_stubFormPostCountsGoogle() {
      const transport = requireChild(createShell(), "httpTransport")
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(tokenJson("1//refresh"))
      const result = transport.post(
         "https://oauth2.googleapis.com/token", "",
         "code=abc&grant_type=authorization_code",
         "application/x-www-form-urlencoded")
      compare(result.status, 200)
      compare(transport.lastUrl,
         "https://oauth2.googleapis.com/token")
      verify(transport.lastBody.indexOf("code=abc") >= 0)
      compare(transport.googleCount, 1)
      compare(transport.chatCount, 0)
      compare(transport.klingCount, 0)
   }

   function test_stubGetReadsBodyAndUrl() {
      const transport = requireChild(createShell(), "httpTransport")
      transport.use_stub()
      transport.clear()
      transport.enqueue_json("{\"ok\":true}")
      const result = transport.get(
         "https://example.test/tasks?task_ids=1", "tok")
      compare(result.status, 200)
      verify(result.body.indexOf("ok") >= 0)
      compare(result.error, "")
      compare(transport.lastUrl,
         "https://example.test/tasks?task_ids=1")
      compare(transport.callCount, 1)
      compare(transport.klingCount, 1)
      verify(transport.urls.indexOf(
         "https://example.test/tasks?task_ids=1") >= 0)
   }

   function test_stubGetAbortReturnsCancelled() {
      const transport = requireChild(createShell(), "httpTransport")
      transport.use_stub()
      transport.clear()
      transport.enqueue_json("{\"ok\":true}")
      transport.abort()
      const result = transport.get("https://example.test/tasks", "")
      compare(result.error, "cancelled")
   }

   function test_klingKeyMemoryOmitsKeyFromLibrary() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const secrets = requireChild(shell, "secretStore")
      resetSecrets(secrets)
      secrets.apiKey = "sk-chat-key"
      secrets.klingApiKey = "kling-secret-key"
      verify(secrets.save())
      verify(secrets.hasKlingKey)
      verify(secrets.hasKey)
      compare(secrets.klingApiKey, "")
      compare(secrets.apiKey, "")
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("kling-secret-key") < 0)
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      const project = requireChild(shell, "projectDocument")
      verify(project.open_short(id))
      project.save()
      const json = paths.read_text(
         dir + "/shorts/" + id + "/project.json")
      verify(json.indexOf("kling-secret-key") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_googleClientMemoryOmitsSecretFromLibrary() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const secrets = requireChild(shell, "secretStore")
      resetSecrets(secrets)
      secrets.apiKey = "sk-chat-key"
      secrets.googleClientId = "google-client-id"
      secrets.googleClientSecret = "google-client-secret"
      secrets.set_channel_refresh("UC1", "refresh-token-secret")
      verify(secrets.save())
      verify(secrets.hasGoogleClient)
      verify(secrets.hasKey)
      compare(secrets.googleClientSecret, "")
      compare(secrets.apiKey, "")
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("google-client-secret") < 0)
      verify(db.indexOf("refresh-token-secret") < 0)
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      const project = requireChild(shell, "projectDocument")
      verify(project.open_short(id))
      project.save()
      const json = paths.read_text(
         dir + "/shorts/" + id + "/project.json")
      verify(json.indexOf("google-client-secret") < 0)
      verify(json.indexOf("refresh-token-secret") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_completeWithCodeWritesChannelWithoutBrowser() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      transport.use_stub()
      transport.clear()
      auth.use_stub()
      enqueueConnect(transport, "UC1", "Studio One", "1//r1")
      verify(auth.complete_with_code("auth-code"))
      compare(store.channel_count(), 1)
      compare(store.channel_title("UC1"), "Studio One")
      verify(secrets.has_channel_refresh("UC1"))
      compare(transport.googleCount, 2)
      verify(transport.urls.indexOf(
         "https://oauth2.googleapis.com/token") >= 0)
      verify(transport.urls.join(" ").indexOf(
         "youtube/v3/channels") >= 0)
      compare(auth.browserOpenCount, 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_completeWithoutRefreshDoesNotWriteChannel() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      transport.use_stub()
      transport.clear()
      auth.use_stub()
      transport.enqueue_json(JSON.stringify({
         access_token: "ya29.test",
         token_type: "Bearer"
      }))
      verify(!auth.complete_with_code("auth-code"))
      compare(store.channel_count(), 0)
      verify(!secrets.has_channel_refresh("UC1"))
      store.close()
      paths.remove_tree(dir)
   }

   function test_tokenOrListErrorDoesNotAddChannel() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      transport.use_stub()
      auth.use_stub()
      transport.clear()
      transport.enqueue_error("token boom")
      verify(!auth.complete_with_code("auth-code"))
      compare(store.channel_count(), 0)
      transport.clear()
      transport.enqueue_json(tokenJson("1//r1"))
      transport.enqueue_error("list boom")
      verify(!auth.complete_with_code("auth-code"))
      compare(store.channel_count(), 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_completeWithErrorKeepsExistingChannel() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      transport.use_stub()
      transport.clear()
      auth.use_stub()
      enqueueConnect(transport, "UC1", "Studio One", "1//r1")
      verify(auth.complete_with_code("auth-code"))
      compare(store.channel_count(), 1)
      auth.complete_with_error()
      compare(store.channel_count(), 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_googleClientReloadsWithoutSecretText() {
      const secrets = requireChild(createShell(), "secretStore")
      resetSecrets(secrets)
      secrets.googleClientId = "google-reload-id"
      secrets.googleClientSecret = "google-reload-secret"
      verify(secrets.save())
      const again = requireChild(createShell(), "secretStore")
      again.use_memory(true)
      verify(again.load())
      compare(again.googleClientId, "google-reload-id")
      verify(again.hasGoogleClient)
      compare(again.googleClientSecret, "")
      compare(again.channel_refresh("missing"), "")
      verify(!again.has_channel_refresh("missing"))
      verify(again.hasKey === false)
   }

   function test_klingKeyReloadsAddressAndModel() {
      const secrets = requireChild(createShell(), "secretStore")
      resetSecrets(secrets)
      secrets.klingApiKey = "kling-reload"
      verify(secrets.save())
      const again = requireChild(createShell(), "secretStore")
      again.use_memory(true)
      verify(again.load())
      compare(again.klingBaseUrl, "https://api-singapore.klingai.com")
      compare(again.klingModel, "kling-4.0-flash")
      verify(again.hasKlingKey)
      compare(again.klingApiKey, "")
      verify(again.hasKey === false)
   }

   function test_parseScenesJsonAndClampsDuration() {
      const two = scenes.parse(
         "{\"scenes\":[{\"prompt\":\"A\",\"duration_s\":5}," +
         "{\"prompt\":\"B\",\"duration_s\":8}]}")
      compare(two.length, 2)
      compare(two[0].prompt, "A")
      compare(two[0].duration_s, 5)
      compare(two[1].prompt, "B")
      compare(two[1].duration_s, 8)
      const clamped = scenes.parse(
         "{\"scenes\":[{\"prompt\":\"A\",\"duration_s\":1}," +
         "{\"prompt\":\"B\",\"duration_s\":30}]}")
      compare(clamped[0].duration_s, 3)
      compare(clamped[1].duration_s, 20)
   }

   function test_parseScenesPlainTextIsOneScene() {
      const list = scenes.parse("Narration text")
      compare(list.length, 1)
      compare(list[0].prompt, "Narration text")
      compare(list[0].duration_s, 5)
   }

   function test_videoToolUrlsFromStub() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Narration text"))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "task-1")
      enqueueCover(transport, dir)
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      const urls = transport.urls
      let createUrl = false
      let pollUrl = false
      for (let i = 0; i < urls.length; ++i) {
         if (urls[i].indexOf("/text-to-video/kling-4.0-flash") >= 0) {
            createUrl = true
         }
         if (urls[i].indexOf("/tasks") >= 0) {
            pollUrl = true
         }
      }
      verify(createUrl)
      verify(pollUrl)
      store.close()
      paths.remove_tree(dir)
   }

   function test_voiceWithoutKlingKeyKeepsScript() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveChatKey(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Narration text"))
      transport.enqueue_file(paths.make_wav(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      const speechBefore = transport.speechCount
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(transport.klingCount, 0)
      verify(transport.speechCount > speechBefore)
      compare(pipeline.needsSettingsMessage, "Нужны настройки")
      compare(store.short_script(id), "Narration text")
      verify(project.first_clip_on("a1").length > 0)
      compare(project.first_clip_on("v1"), "")
      compare(store.short_status(id), "draft")
      store.close()
      paths.remove_tree(dir)
   }

   function test_posterWithoutImageApiUntilCover() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      const pane = requireChild(shell, "libraryPane")
      const model = requireChild(shell, "libraryModel")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      const script = JSON.stringify({
         scenes: [
            { prompt: "A", duration_s: 5 },
            { prompt: "B", duration_s: 5 }
         ]
      })
      transport.enqueue_json(chatJson(script))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "task-1")
      const folder = store.create_folder("", "Film")
      model.toggle_id(folder)
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      pipeline.pauseAfterVideoScene = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return project.clip_count_on("v1") === 1
      }, 8000)
      verify(store.short_has_poster(id))
      const preview = requireChild(pane, "shortPreview")
      compare(preview.radius, 12)
      requireChild(pane, "durationBadge")
      verify(store.short_duration_ms(id) > 0)
      const urls = transport.urls
      for (let i = 0; i < urls.length; ++i) {
         verify(urls[i].indexOf("/v1/images/") < 0)
      }
      enqueueScene(transport, "task-2")
      enqueueCover(transport, dir)
      pipeline.resume()
      waitStopped(pipeline)
      store.close()
      paths.remove_tree(dir)
   }

   function test_coverWritesFileAndReadyStatus() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Narration text"))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "task-1")
      enqueueCover(transport, dir)
      const folder = store.create_folder("", "Film")
      const shortsBefore = store.short_count()
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(store.short_status(id), "ready")
      verify(store.short_status(id) !== "draft")
      verify(store.short_status(id) !== "published")
      const rel = store.short_cover_relpath(id)
      compare(rel, "shorts/" + id + "/youtube_cover.jpg")
      const coverPath = dir + "/" + rel
      verify(paths.file_exists(coverPath))
      compare(paths.image_width(coverPath), 1280)
      compare(paths.image_height(coverPath), 720)
      compare(store.short_count(), shortsBefore + 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_cancelVideoBeforeFirstClipKeepsVoice() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Keep me"))
      transport.enqueue_file(paths.make_wav(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      pipeline.pauseAfterVoice = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return project.first_clip_on("a1").length > 0
      })
      pipeline.cancel()
      waitStopped(pipeline)
      compare(store.short_script(id), "Keep me")
      verify(project.first_clip_on("a1").length > 0)
      compare(project.first_clip_on("v1"), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_cancelVideoAfterOneSceneKeepsThatClip() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      const script = JSON.stringify({
         scenes: [
            { prompt: "A", duration_s: 5 },
            { prompt: "B", duration_s: 5 }
         ]
      })
      transport.enqueue_json(chatJson(script))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "task-1")
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      pipeline.pauseAfterVideoScene = true
      verify(pipeline.run(id))
      tryVerify(function() {
         return project.clip_count_on("v1") === 1
      }, 8000)
      pipeline.cancel()
      waitStopped(pipeline)
      compare(store.short_script(id), script)
      verify(project.first_clip_on("a1").length > 0)
      compare(project.clip_count_on("v1"), 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_videoErrorKeepsVoiceAndCoverErrorKeepsClips() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      const pane = requireChild(shell, "libraryPane")
      const model = requireChild(shell, "libraryModel")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Kept script"))
      transport.enqueue_file(paths.make_wav(dir))
      transport.enqueue_error("video down")
      const folder = store.create_folder("", "Film")
      model.toggle_id(folder)
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(store.short_script(id), "Kept script")
      verify(project.first_clip_on("a1").length > 0)
      compare(project.first_clip_on("v1"), "")
      compare(store.short_status(id), "draft")
      tryVerify(function() {
         const error = findChild(pane, "pipelineError")
         return error !== null && error.text.indexOf("video down") >= 0
      })
      transport.enqueue_json(klingCreate("task-1"))
      transport.enqueue_json(klingVideoDone(
         "task-1", "https://cdn.test/v.mp4"))
      transport.enqueue_file(paths.fixture_path("vertical-short.mp4"))
      transport.enqueue_error("cover down")
      const chats = transport.chatCount
      const speech = transport.speechCount
      verify(pipeline.retry(id))
      waitStopped(pipeline)
      compare(transport.chatCount, chats)
      compare(transport.speechCount, speech)
      verify(project.clip_count_on("v1") >= 1)
      verify(store.short_has_poster(id))
      compare(store.short_cover_relpath(id), "")
      compare(store.short_status(id), "draft")
      tryVerify(function() {
         const error = findChild(pane, "pipelineError")
         return error !== null &&
            error.text.indexOf("cover down") >= 0
      })
      store.close()
      paths.remove_tree(dir)
   }

   function test_retryAfterCoverErrorSkipsVideo() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Kept script"))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "task-1")
      transport.enqueue_error("cover down")
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      const clips = project.clip_count_on("v1")
      const urlsBefore = transport.urls.length
      enqueueCover(transport, dir)
      verify(pipeline.retry(id))
      waitStopped(pipeline)
      compare(project.clip_count_on("v1"), clips)
      compare(store.short_status(id), "ready")
      let extraVideo = false
      const urls = transport.urls
      for (let i = urlsBefore; i < urls.length; ++i) {
         if (urls[i].indexOf("/text-to-video/") >= 0) {
            extraVideo = true
         }
      }
      verify(!extraVideo)
      store.close()
      paths.remove_tree(dir)
   }

   function test_retryCompletesRemainingScenes() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveBothKeys(secrets)
      transport.use_stub()
      transport.clear()
      const script = JSON.stringify({
         scenes: [
            { prompt: "A", duration_s: 5 },
            { prompt: "B", duration_s: 5 },
            { prompt: "C", duration_s: 5 },
            { prompt: "D", duration_s: 5 }
         ]
      })
      transport.enqueue_json(chatJson(script))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "t1")
      enqueueScene(transport, "t2")
      transport.enqueue_error("video down")
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(project.clip_count_on("v1"), 2)
      const chats = transport.chatCount
      const speech = transport.speechCount
      enqueueScene(transport, "t3")
      enqueueScene(transport, "t4")
      enqueueCover(transport, dir)
      verify(pipeline.retry(id))
      waitStopped(pipeline)
      compare(transport.chatCount, chats)
      compare(transport.speechCount, speech)
      compare(project.clip_count_on("v1"), 4)
      compare(store.short_status(id), "ready")
      store.close()
      paths.remove_tree(dir)
   }

   function test_runningVideoTaskInterruptedOnOpen() {
      const dir = paths.make()
      const store = requireChild(createShell(), "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_script(id, "Already there"))
      verify(store.insert_task(id, "video", "running").length > 0)
      store.set_short_status(id, "generating")
      store.close()
      const again = requireChild(createShell(), "libraryStore")
      verify(again.open(dir))
      compare(again.task_status(id), "interrupted")
      compare(again.short_script(id), "Already there")
      compare(again.short_status(id), "draft")
      again.close()
      paths.remove_tree(dir)
   }

   function publicationOf(store, shortId, channelId) {
      const n = store.publication_count(shortId)
      for (let i = 0; i < n; ++i) {
         const pid = store.publication_id_at(shortId, i)
         if (store.publication_channel_id(pid) === channelId) {
            return pid
         }
      }
      return ""
   }

   function seedReadyShort(store, dir, name) {
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, name)
      verify(store.set_short_status(id, "ready"))
      verify(store.set_script(id, "Scene text"))
      verify(paths.mkpath(dir + "/exports"))
      verify(paths.copy_file(paths.fixture_path("vertical-short.mp4"),
         store.export_path(id)))
      return id
   }

   function bindChannel(store, secrets, id, title, refresh) {
      verify(store.upsert_channel(id, title))
      secrets.set_channel_refresh(id, refresh)
      verify(secrets.save())
   }

   function enqueueAccess(transport, token) {
      transport.enqueue_json(JSON.stringify({
         access_token: token,
         token_type: "Bearer"
      }))
   }

   function enqueueInsert(transport, videoId) {
      transport.enqueue_header("Location",
         "https://upload.test/" + videoId)
      transport.enqueue_json("{}")
      transport.enqueue_json(JSON.stringify({ id: videoId }))
   }

   function channelStatsJson() {
      return JSON.stringify({
         items: [{
            statistics: {
               subscriberCount: "9",
               viewCount: "100"
            }
         }]
      })
   }

   function videoStatsJson() {
      return JSON.stringify({
         items: [{
            statistics: {
               viewCount: "42",
               likeCount: "3",
               commentCount: "1"
            }
         }]
      })
   }

   function reportJson(withCtr) {
      const headers = [
         { name: "day" },
         { name: "views" },
         { name: "estimatedMinutesWatched" },
         { name: "averageViewDuration" },
         { name: "likes" }
      ]
      const row = ["2026-11-01", 5, 8, 12, 2]
      if (withCtr) {
         headers.push({ name: "impressions" })
         headers.push({ name: "impressionClickThroughRate" })
         row.push(50)
         row.push(0.1)
      }
      return JSON.stringify({
         columnHeaders: headers,
         rows: [row]
      })
   }

   function test_stubPutReadsLocationAndAnalyticsHost() {
      const shell = createShell()
      const transport = requireChild(shell, "httpTransport")
      transport.use_stub()
      transport.clear()
      transport.enqueue_header("Location", "https://upload.test/put")
      transport.enqueue_json("{}")
      const started = transport.post(
         "https://www.googleapis.com/upload/youtube/v3/videos",
         "Bearer x", "{}", "application/json")
      compare(started.location, "https://upload.test/put")
      compare(transport.lastLocation, "https://upload.test/put")
      transport.enqueue_json("{\"id\":\"vid\"}")
      const put = transport.put("https://upload.test/put", "Bearer x",
         "bytes", "video/mp4")
      compare(put.error, "")
      compare(transport.lastUrl, "https://upload.test/put")
      verify(transport.urls.indexOf("https://upload.test/put") >= 0)
      const chat = transport.chatCount
      const kling = transport.klingCount
      const google = transport.googleCount
      transport.enqueue_json("{}")
      transport.get(
         "https://youtubeanalytics.googleapis.com/v2/reports",
         "Bearer x")
      compare(transport.googleCount, google + 1)
      compare(transport.chatCount, chat)
      compare(transport.klingCount, kling)
   }

   function test_accessTokenStaysInMemory() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      enqueueAccess(transport, "ya29.access-mem-only")
      compare(auth.access_token("UC1"), "ya29.access-mem-only")
      compare(auth.access_token("UC1"), "ya29.access-mem-only")
      compare(transport.googleCount, 1)
      verify(transport.lastBody.indexOf("grant_type=refresh_token") >= 0)
      verify(secrets.save())
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(project.open_short(id))
      project.save()
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("ya29.access-mem-only") < 0)
      const json = paths.read_text(
         dir + "/shorts/" + id + "/project.json")
      verify(json.indexOf("ya29.access-mem-only") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_accessTokenMissingRefreshKeepsChannel() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      verify(store.upsert_channel("UC1", "Studio"))
      transport.use_stub()
      transport.clear()
      const before = transport.googleCount
      compare(auth.access_token("UC1"), "")
      compare(store.channel_count(), 1)
      compare(transport.googleCount, before)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.enqueue_error("token boom")
      compare(auth.access_token("UC1"), "")
      compare(store.channel_count(), 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishWithoutExportOrLongDuration() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const publisher = requireChild(shell, "publisher")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      const folder = store.create_folder("", "Film")
      const missing = store.create_short(folder, "No File")
      verify(store.set_short_status(missing, "ready"))
      verify(!publisher.publish(missing, ["UC1"], "T", "D",
         "unlisted"))
      verify(publisher.lastError.indexOf("экспорт") >= 0)
      compare(store.publication_count(missing), 0)
      compare(transport.googleCount, 0)
      const longId = seedReadyShort(store, dir, "Long")
      verify(store.update_short_media(longId, 180001, ""))
      verify(!publisher.publish(longId, ["UC1"], "T", "D",
         "unlisted"))
      verify(publisher.lastError.indexOf("длительн") >= 0)
      compare(store.publication_count(longId), 0)
      compare(transport.googleCount, 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishStubWritesVideoId() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      const publisher = requireChild(shell, "publisher")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      auth.use_stub()
      const id = seedReadyShort(store, dir, "Clip")
      enqueueAccess(transport, "ya29.upload")
      enqueueInsert(transport, "vid-1")
      verify(publisher.publish(id, ["UC1"], "Title", "Desc",
         "unlisted"), publisher.lastError)
      const pub = publicationOf(store, id, "UC1")
      compare(store.publication_video_id(pub), "vid-1")
      compare(store.short_status(id), "published")
      verify(transport.urls.join(" ").indexOf(
         "upload/youtube/v3/videos") >= 0)
      verify(transport.urls.indexOf("https://upload.test/vid-1") >= 0)
      compare(auth.browserOpenCount, 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishSecondChannelAfterFirstError() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const publisher = requireChild(shell, "publisher")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "One", "1//r1")
      bindChannel(store, secrets, "UC2", "Two", "1//r2")
      transport.use_stub()
      transport.clear()
      const id = seedReadyShort(store, dir, "Clip")
      enqueueAccess(transport, "ya29.one")
      transport.enqueue_error("insert boom")
      enqueueAccess(transport, "ya29.two")
      enqueueInsert(transport, "vid-2")
      verify(publisher.publish(id, ["UC1", "UC2"], "Title", "Desc",
         "unlisted"), publisher.lastError)
      const first = publicationOf(store, id, "UC1")
      const second = publicationOf(store, id, "UC2")
      compare(store.publication_status(first), "error")
      verify(store.publication_error(first).length > 0)
      compare(store.publication_video_id(second), "vid-2")
      compare(store.short_status(id), "published")
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishCoverSetAndSkipped() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const publisher = requireChild(shell, "publisher")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      const id = seedReadyShort(store, dir, "Clip")
      const rel = "shorts/" + id + "/youtube_cover.jpg"
      verify(paths.mkpath(dir + "/shorts/" + id))
      verify(paths.copy_file(paths.make_image(dir),
         dir + "/" + rel))
      verify(store.set_cover_relpath(id, rel))
      enqueueAccess(transport, "ya29.cover")
      enqueueInsert(transport, "vid-set")
      transport.enqueue_json("{}")
      verify(publisher.publish(id, ["UC1"], "Title", "Desc",
         "unlisted"), publisher.lastError)
      let pub = publicationOf(store, id, "UC1")
      compare(store.publication_video_id(pub), "vid-set")
      compare(store.publication_cover_status(pub), "set")
      transport.clear()
      enqueueInsert(transport, "vid-skip")
      transport.enqueue_status(403)
      transport.enqueue_json(JSON.stringify({
         error: { message: "custom thumbnail" }
      }))
      verify(publisher.publish(id, ["UC1"], "Title", "Desc",
         "unlisted"))
      pub = publicationOf(store, id, "UC1")
      compare(store.publication_video_id(pub), "vid-skip")
      compare(store.publication_cover_status(pub), "skipped")
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishQuotaBlocksInsert() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const publisher = requireChild(shell, "publisher")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      const id = seedReadyShort(store, dir, "Clip")
      for (let i = 0; i < 100; ++i) {
         verify(store.increment_quota())
      }
      compare(store.quota_remaining(), 0)
      verify(!publisher.publish(id, ["UC1"], "Title", "Desc",
         "unlisted"))
      verify(publisher.lastError.indexOf("квот") >= 0)
      verify(transport.urls.join(" ").indexOf("videos.insert") < 0)
      verify(transport.urls.join(" ").indexOf(
         "upload/youtube/v3/videos") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_statsRefreshWritesSnapshot() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const stats = requireChild(shell, "statsSync")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      transport.use_stub()
      transport.clear()
      const before = transport.googleCount
      compare(store.stats_payload("channel", "UC1"), "")
      enqueueAccess(transport, "ya29.stats")
      transport.enqueue_json(channelStatsJson())
      transport.enqueue_json(reportJson(true))
      verify(stats.refresh("channel", "UC1"))
      verify(store.stats_payload("channel", "UC1").indexOf("100") >= 0)
      verify(store.stats_synced_ms("channel", "UC1") > 0)
      verify(transport.googleCount > before)
      store.close()
      paths.remove_tree(dir)
   }

   function test_statsMissingCtrAndNoRefreshKeepsSnapshot() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const stats = requireChild(shell, "statsSync")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      const id = seedReadyShort(store, dir, "Clip")
      verify(store.upsert_publication(id, "UC1", "vid-1", "unlisted",
         "uploaded", "", ""))
      transport.use_stub()
      transport.clear()
      enqueueAccess(transport, "ya29.stats")
      transport.enqueue_json(videoStatsJson())
      transport.enqueue_json(reportJson(false))
      verify(stats.refresh("video", "vid-1"))
      const payload = store.stats_payload("video", "vid-1")
      verify(payload.indexOf("нет в этом канале") >= 0)
      verify(payload.indexOf("42") >= 0)
      const synced = store.stats_synced_ms("video", "vid-1")
      verify(store.upsert_channel("UC2", "Bare"))
      transport.clear()
      const before = transport.googleCount
      verify(!stats.refresh("channel", "UC2"))
      compare(store.stats_payload("video", "vid-1"), payload)
      compare(store.stats_synced_ms("video", "vid-1"), synced)
      compare(transport.googleCount, before)
      store.close()
      paths.remove_tree(dir)
   }
}
