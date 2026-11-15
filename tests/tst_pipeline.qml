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
}
