import QtQuick
import QtTest
import Creator
import CreatorTests 1.0

TestCase {
   id: testCase
   name: "Pipeline"
   when: windowShown

   TempDirectory { id: paths }

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
      return "{\"choices\":[{\"message\":{\"content\":\"" +
         text + "\"}}]}"
   }

   function waitStopped(pipeline) {
      tryVerify(function() { return !pipeline.running }, 5000)
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
}
