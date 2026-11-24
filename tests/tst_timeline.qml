import QtQuick
import QtTest
import Creator
import CreatorTests 1.0

TestCase {
   id: testCase
   name: "Timeline"
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

   function openImported(shell, fixtureName) {
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const fixture = paths.fixture_path(fixtureName)
      const shortsBefore = store.short_count()
      const asset = store.import_media("", fixture)
      verify(asset.length > 0)
      compare(store.short_count(), shortsBefore)
      const id = store.create_short(folder, "Clip")
      const project = requireChild(shell, "projectDocument")
      verify(project.open_short(id))
      const placed = project.place_asset(asset, "", 0, false)
      verify(placed.length > 0)
      pane.select_entry(id, "short")
      const frame = requireChild(shell, "frameView")
      tryVerify(function() {
         return frame.centerMode === "preview" && frame.hasFrameImage
      })
      return {
         dir: dir,
         store: store,
         pane: pane,
         id: id,
         folder: folder,
         fixture: fixture,
         asset: asset,
         frame: frame,
         project: project
      }
   }

   function test_importCopiesAndWritesProject() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const jsonPath = ctx.dir + "/shorts/" + ctx.id + "/project.json"
      verify(paths.file_exists(jsonPath))
      const json = paths.read_text(jsonPath)
      verify(json.indexOf("\"track\": \"v1\"") >= 0 ||
             json.indexOf("\"track\":\"v1\"") >= 0)
      verify(json.indexOf("media/") >= 0)
      verify(json.indexOf(ctx.fixture) < 0)
      verify(ctx.store.short_duration_ms(ctx.id) > 0)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_importIntoDraftKeepsName() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const draft = store.create_short(folder, "Kept Name")
      const before = store.shorts ? 1 : 1
      verify(!store.import_into_short(draft, ""))
      compare(store.short_name(draft), "Kept Name")
      verify(store.import_into_short(
         draft, paths.fixture_path("vertical-short.mp4")))
      compare(store.short_name(draft), "Kept Name")
      verify(store.short_duration_ms(draft) > 0)
      store.close()
      paths.remove_tree(dir)
      compare(before, 1)
   }

   function test_selectImportedFillsFrame() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      compare(ctx.frame.centerMode, "preview")
      compare(ctx.frame.hasFrameImage, true)
      compare(requireChild(shell, "timelineHost").clipCount, 1)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_deselectAndDraftStayEmpty() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      ctx.pane.select_entry("", "")
      compare(ctx.frame.centerMode, "empty")
      compare(ctx.frame.hasFrameImage, false)
      compare(requireChild(shell, "timelineHost").clipCount, 0)
      const draft = ctx.store.create_short(ctx.folder, "Empty")
      ctx.pane.select_entry(draft, "short")
      compare(ctx.frame.centerMode, "empty")
      compare(ctx.frame.hasFrameImage, false)
      compare(requireChild(shell, "toolSelect").enabled, false)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_seekUsesSourceInOut() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const out = ctx.project.clip_out(video)
      const inPoint = Math.floor(out / 4)
      const outPoint = Math.floor(out * 3 / 4)
      verify(ctx.project.trim_clip(video, inPoint, outPoint))
      const mid = Math.floor((outPoint - inPoint) / 2)
      ctx.project.playheadMs = mid
      tryVerify(function() {
         return ctx.frame.lastSourceMs >= inPoint &&
            ctx.frame.lastSourceMs < outPoint
      })
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_playAdvancesPlayhead() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      ctx.project.playheadMs = 0
      ctx.project.play()
      tryVerify(function() {
         return ctx.project.playheadMs > 0 && ctx.frame.hasFrameImage
      })
      const at = ctx.project.playheadMs
      ctx.project.pause()
      wait(80)
      compare(ctx.project.playheadMs, at)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_cardPreviewAndDraftPlaceholder() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      ctx.store.create_short(ctx.folder, "Draft")
      const pane = requireChild(shell, "libraryPane")
      pane.libraryModel.toggle_id(ctx.folder)
      tryVerify(function() { return pane.rowCount >= 3 })
      verify(ctx.store.short_has_poster(ctx.id))
      const preview = findChild(pane, "shortPreview")
      verify(preview !== null)
      const badge = findChild(pane, "durationBadge")
      verify(badge !== null)
      compare(badge.visible, true)
      verify(findChild(pane, "shortPlaceholder") !== null)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_tracksVisible() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      verify(findChild(shell, "trackV1") !== null)
      verify(findChild(shell, "trackV2") !== null)
      verify(findChild(shell, "trackA1") !== null)
      verify(requireChild(shell, "timelineHost").clipCount >= 1)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_splitAtPlayhead() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      ctx.project.selectedClipId = video
      ctx.project.playheadMs = Math.floor(
         ctx.project.clip_out(video) / 2)
      verify(ctx.project.split_at_playhead())
      compare(ctx.project.clipCount, 2)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_independentAudioVideoTrim() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const audio = ctx.project.first_clip_on("a1")
      verify(audio.length > 0)
      const videoOut = ctx.project.clip_out(video)
      const audioOut = ctx.project.clip_out(audio)
      verify(ctx.project.trim_clip(video, 0, Math.floor(videoOut / 2)))
      compare(ctx.project.clip_out(audio), audioOut)
      verify(ctx.project.trim_clip(audio, 0, Math.floor(audioOut / 3)))
      verify(ctx.project.clip_out(audio) < ctx.project.clip_out(video) ||
             ctx.project.clip_out(audio) < audioOut)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_addAudioWaveform() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const added = ctx.project.add_audio(
         paths.fixture_path("vertical-short.mp4"))
      verify(added.length > 0)
      compare(ctx.project.clip_track(added), "a1")
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_volumeStored() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const audio = ctx.project.first_clip_on("a1")
      verify(ctx.project.set_volume(audio, 0.35))
      compare(ctx.project.clip_volume(audio), 0.35)
      compare(ctx.project.export_volume(audio), 0.35)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_undoTrim() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const original = ctx.project.clip_out(video)
      verify(ctx.project.trim_clip(video, 0, Math.floor(original / 2)))
      verify(ctx.project.undo())
      compare(ctx.project.clip_out(video), original)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_trimSurvivesRestart() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const original = ctx.project.clip_out(video)
      const trimmed = Math.floor(original / 2)
      verify(ctx.project.trim_clip(video, 0, trimmed))
      paths.save_library_path(ctx.dir)
      const again = createShell()
      const store = requireChild(again, "libraryStore")
      verify(store.open_saved())
      const pane = requireChild(again, "libraryPane")
      pane.select_entry(ctx.id, "short")
      const project = requireChild(again, "projectDocument")
      tryVerify(function() { return project.clipCount >= 1 })
      const opened = project.first_clip_on("v1")
      compare(project.clip_out(opened), trimmed)
      store.close()
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_deleteShortRemovesFiles() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const jsonPath = ctx.dir + "/shorts/" + ctx.id + "/project.json"
      verify(paths.file_exists(jsonPath))
      verify(!ctx.store.delete_short(ctx.id, false))
      verify(paths.file_exists(jsonPath))
      verify(ctx.store.delete_short(ctx.id, true))
      verify(!paths.file_exists(jsonPath))
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_toolsEnableWithMedia() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      compare(requireChild(shell, "toolSelect").enabled, true)
      compare(requireChild(shell, "opDelete").enabled, true)
      ctx.pane.select_entry("", "")
      compare(requireChild(shell, "toolSelect").enabled, false)
      compare(requireChild(shell, "toolSelect").iconColor, "#717171")
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_coverFillsNineSixteen() {
      const shell = createShell()
      const ctx = openImported(shell, "horizontal-short.mp4")
      ctx.project.apply_cover()
      tryVerify(function() {
         return ctx.frame.previewWidth * 16 ===
            ctx.frame.previewHeight * 9 && ctx.frame.leftEdgeOpaque
      })
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_transformPersists() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      verify(ctx.project.set_transform(video, 1.4, 6, 9))
      paths.save_library_path(ctx.dir)
      const again = createShell()
      requireChild(again, "libraryStore").open_saved()
      requireChild(again, "libraryPane").select_entry(ctx.id, "short")
      const project = requireChild(again, "projectDocument")
      tryVerify(function() { return project.clipCount >= 1 })
      const opened = project.first_clip_on("v1")
      compare(project.clip_scale(opened), 1.4)
      compare(project.clip_offset_x(opened), 6)
      compare(project.clip_offset_y(opened), 9)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_addTextOnV2() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const textId = ctx.project.add_text("Hello")
      verify(textId.length > 0)
      compare(ctx.project.clip_track(textId), "v2")
      compare(ctx.frame.hasFrameImage, true)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_deleteClipKeepsAsset() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const file = ctx.project.clip_abs_path(video)
      ctx.project.selectedClipId = video
      const before = ctx.project.clipCount
      verify(ctx.project.delete_selected_clip())
      compare(ctx.project.clipCount, before - 1)
      verify(paths.file_exists(file))
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_exportMp4() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const exporter = requireChild(shell, "exporter")
      exporter.compositor = ctx.frame.compositor
      const path = exporter.export_current()
      verify(path.length > 0)
      verify(paths.file_exists(path))
      compare(exporter.lastWidth, 1080)
      compare(exporter.lastHeight, 1920)
      compare(paths.video_width(path), 1080)
      compare(paths.video_height(path), 1920)
      const draft = ctx.store.create_short(ctx.folder, "Empty")
      ctx.pane.select_entry(draft, "short")
      compare(exporter.export_current(), "")
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_toolHintsAndExportButton() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const select = requireChild(shell, "toolSelect")
      compare(select.enabled, true)
      verify(select.hint.indexOf("Выбор") >= 0)
      const exportButton = requireChild(shell, "exportButton")
      compare(exportButton.enabled, true)
      exportButton.clicked()
      const dialog = requireChild(shell, "exportDialog")
      tryVerify(function() { return dialog.visible === true })
      const text = requireChild(shell, "exportDialogText").text
      verify(text.indexOf("exports") >= 0 || text.indexOf("Файл") >= 0)
      requireChild(shell, "exportDialogClose").clicked()
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_seekAlignsPlayheadAndClipBlock() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const host = requireChild(shell, "timelineHost")
      verify(host.itemCount >= 1)
      verify(host.clipCount >= 1)
      const slider = requireChild(shell, "playheadSlider")
      tryVerify(function() { return slider.width > 40 })
      slider.seekTo(slider.width / 2)
      const mid = ctx.project.durationMs / 2
      verify(Math.abs(ctx.project.playheadMs - mid) < 120)
      const clock = requireChild(shell, "timelineClock")
      verify(clock.text.indexOf("/") >= 0)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_deleteShortButtonCancelKeepsFiles() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const jsonPath = ctx.dir + "/shorts/" + ctx.id + "/project.json"
      const button = requireChild(shell, "deleteShortButton")
      compare(button.visible, true)
      button.clicked()
      const message = requireChild(shell, "confirmMessage")
      verify(message.text.indexOf("ролик") >= 0)
      requireChild(shell, "confirmCancel").clicked()
      verify(paths.file_exists(jsonPath))
      compare(ctx.store.short_name(ctx.id).length > 0, true)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_deleteShortButtonAcceptRemovesFiles() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const jsonPath = ctx.dir + "/shorts/" + ctx.id + "/project.json"
      requireChild(shell, "deleteShortButton").clicked()
      requireChild(shell, "confirmAccept").clicked()
      verify(!paths.file_exists(jsonPath))
      compare(ctx.store.short_name(ctx.id), "")
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_twoShortsShareAsset() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const files = ctx.store.media_file_count()
      const second = ctx.store.create_short(ctx.folder, "Other")
      verify(ctx.project.open_short(second))
      const placed = ctx.project.place_asset(ctx.asset, "v1", 0, false)
      verify(placed.length > 0)
      compare(ctx.project.clip_asset_id(placed), ctx.asset)
      compare(ctx.store.media_file_count(), files)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_assetMarksCopyOnce() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const first = ctx.project.first_clip_on("v1")
      const original = ctx.project.clip_out(first)
      const marked = Math.floor(original / 4)
      verify(ctx.store.set_asset_marks(ctx.asset, 0, marked))
      compare(ctx.project.clip_out(first), original)
      const again = ctx.project.place_asset(ctx.asset, "v1", original, false)
      verify(again.length > 0)
      compare(ctx.project.clip_out(again) - ctx.project.clip_in(again),
         marked)
      compare(ctx.project.clip_out(first), original)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_insertAndOverwrite() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const first = ctx.project.first_clip_on("v1")
      const length = ctx.project.clip_out(first) - ctx.project.clip_in(first)
      const second = ctx.project.place_asset(
         ctx.asset, "v1", length, false)
      verify(second.length > 0)
      compare(ctx.project.clipCount, 2)
      const inserted = ctx.project.place_asset(
         ctx.asset, "v1", length, true)
      verify(inserted.length > 0)
      compare(ctx.project.clipCount, 3)
      compare(ctx.project.clip_start(second), length * 2)
      const duration = ctx.project.durationMs
      const slice = Math.floor(length / 4)
      verify(ctx.store.set_asset_marks(ctx.asset, 0, slice))
      ctx.project.place_asset(ctx.asset, "v1", slice, false)
      verify(ctx.project.durationMs <= duration + 40)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_snapToPlayhead() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      ctx.project.playheadMs = 1000
      DockState.snapEnabled = true
      compare(ctx.project.snap_ms(1005, 1), 1000)
      DockState.snapEnabled = false
      compare(ctx.project.snap_ms(1005, 1), 1005)
      DockState.snapEnabled = true
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_closeGapKeepsAsset() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      const length = ctx.project.clip_out(video)
         - ctx.project.clip_in(video)
      ctx.project.selectedClipId = video
      ctx.project.playheadMs = Math.floor(length / 3)
      verify(ctx.project.split_at_playhead())
      compare(ctx.project.clipCount, 2)
      let midId = ""
      for (let i = 0; i < ctx.project.itemCount; ++i) {
         const id = ctx.project.clip_id_at(i)
         if (ctx.project.clip_track(id) === "v1"
               && ctx.project.clip_start(id) > 0) {
            midId = id
         }
      }
      verify(midId.length > 0)
      ctx.project.selectedClipId = midId
      ctx.project.playheadMs = Math.floor(length * 2 / 3)
      verify(ctx.project.split_at_playhead())
      compare(ctx.project.clipCount, 3)
      const v1 = []
      for (let j = 0; j < ctx.project.itemCount; ++j) {
         const id = ctx.project.clip_id_at(j)
         if (ctx.project.clip_track(id) === "v1") {
            v1.push({
               id: id,
               start: ctx.project.clip_start(id)
            })
         }
      }
      v1.sort(function(a, b) { return a.start - b.start })
      const leftId = v1[0].id
      const rightId = v1[2].id
      ctx.project.selectedClipId = v1[1].id
      verify(ctx.project.delete_selected_clip())
      verify(ctx.project.close_gap())
      const leftEnd = ctx.project.clip_start(leftId)
         + (ctx.project.clip_out(leftId)
            - ctx.project.clip_in(leftId))
      compare(ctx.project.clip_start(rightId), leftEnd)
      compare(ctx.store.asset_name(ctx.asset), "vertical-short")
      verify(ctx.store.media_file_count() >= 1)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_atomicSaveAndRecovery() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const jsonPath = ctx.dir + "/shorts/" + ctx.id + "/project.json"
      verify(paths.file_exists(jsonPath))
      verify(!paths.file_exists(jsonPath + ".tmp"))
      const video = ctx.project.first_clip_on("v1")
      const original = ctx.project.clip_out(video)
      const trimmed = Math.floor(original / 2)
      verify(ctx.project.trim_clip(video, 0, trimmed))
      ctx.project.flush_recovery()
      const recovery = ctx.dir + "/shorts/" + ctx.id + "/recovery.json"
      verify(paths.file_exists(recovery))
      ctx.project.close()
      verify(!paths.file_exists(recovery))
      verify(paths.write_text(recovery,
         "{\"playhead_ms\":0,\"clips\":[{\"id\":\"r1\",\"track\":\"v1\"," +
         "\"kind\":\"video\",\"asset_id\":\"" + ctx.asset +
         "\",\"file\":\"x\",\"in_ms\":0,\"out_ms\":123," +
         "\"start_ms\":0}]}"))
      verify(ctx.project.open_short(ctx.id, "restore"))
      compare(ctx.project.clip_out(ctx.project.first_clip_on("v1")), 123)
      verify(ctx.project.open_short(ctx.id, "discard"))
      compare(ctx.project.clip_out(ctx.project.first_clip_on("v1")),
         trimmed)
      verify(!paths.file_exists(recovery))
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function chatJson(text) {
      return JSON.stringify({
         choices: [{ message: { content: text } }]
      })
   }

   function waitStopped(pipeline) {
      tryVerify(function() { return !pipeline.running }, 15000)
   }

   function test_pipelinePlacesVoiceWithoutNewShort() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Voice over"))
      transport.enqueue_file(paths.make_wav(ctx.dir))
      const shortsBefore = ctx.store.short_count()
      const v1Before = ctx.project.first_clip_on("v1")
      verify(ctx.store.set_topic(ctx.id, "Topic"))
      verify(pipeline.run(ctx.id))
      waitStopped(pipeline)
      compare(ctx.store.short_count(), shortsBefore)
      compare(ctx.project.first_clip_on("v1"), v1Before)
      const voice = ctx.project.first_clip_on("a1")
      verify(voice.length > 0)
      const rel = ctx.store.asset_relpath(
         ctx.project.clip_asset_id(voice))
      verify(rel.indexOf("media/") === 0)
      verify(paths.file_exists(ctx.dir + "/" + rel))
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_pipelineVoiceTrimIndependent() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pipeline = requireChild(shell, "pipeline")
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      secrets.apiKey = "sk-test"
      verify(secrets.save())
      transport.use_stub()
      transport.clear()
      transport.enqueue_json(chatJson("Voice over"))
      transport.enqueue_file(paths.make_wav(ctx.dir))
      verify(ctx.store.set_topic(ctx.id, "Topic"))
      verify(pipeline.run(ctx.id))
      waitStopped(pipeline)
      const video = ctx.project.first_clip_on("v1")
      const voice = ctx.project.first_clip_on("a1")
      const videoOut = ctx.project.clip_out(video)
      const voiceOut = ctx.project.clip_out(voice)
      const trimmed = Math.max(1, Math.floor(voiceOut / 2))
      verify(ctx.project.trim_clip(voice, 0, trimmed))
      compare(ctx.project.clip_out(video), videoOut)
      verify(ctx.project.clip_out(voice) < voiceOut)
      paths.save_library_path(ctx.dir)
      const again = createShell()
      const store = requireChild(again, "libraryStore")
      verify(store.open_saved())
      requireChild(again, "libraryPane").select_entry(ctx.id, "short")
      const project = requireChild(again, "projectDocument")
      tryVerify(function() { return project.clipCount >= 1 })
      const openedVoice = project.first_clip_on("a1")
      compare(project.clip_out(openedVoice), trimmed)
      compare(project.clip_in(openedVoice), 0)
      store.close()
      ctx.store.close()
      paths.remove_tree(ctx.dir)
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

   function saveBothKeys(secrets) {
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      secrets.apiKey = "sk-test"
      secrets.klingApiKey = "kling-secret-key"
      verify(secrets.save())
   }

   function test_placeAssetCopyAudioFalseKeepsVoice() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(project.open_short(id))
      const audio = store.import_media("", paths.make_wav(dir))
      verify(project.place_asset(audio, "a1", 0, false).length > 0)
      const video = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      verify(project.place_asset(video, "v1", 0, false, false)
         .length > 0)
      compare(project.clip_count_on("a1"), 1)
      compare(project.clip_asset_id(project.first_clip_on("a1")), audio)
      compare(project.clip_count_on("v1"), 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_posterUsesFirstClipNotLast() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const project = requireChild(shell, "projectDocument")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(project.open_short(id))
      const fixture = paths.fixture_path("vertical-short.mp4")
      const first = store.import_media("", fixture)
      const second = store.import_media("", fixture)
      verify(project.place_asset(first, "v1", 0, false, false)
         .length > 0)
      const length = project.clip_out(project.first_clip_on("v1")) -
         project.clip_in(project.first_clip_on("v1"))
      verify(project.place_asset(second, "v1", length, false, false)
         .length > 0)
      verify(store.short_has_poster(id))
      verify(paths.file_exists(dir + "/shorts/" + id + "/poster.png"))
      verify(store.short_duration_ms(id) > 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_pipelinePlacesSceneClipsWithoutNewShort() {
      const shell = createShell()
      const dir = paths.make()
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
            { prompt: "B", duration_s: 8 }
         ]
      })
      transport.enqueue_json(chatJson(script))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "t1")
      enqueueScene(transport, "t2")
      enqueueCover(transport, dir)
      const folder = store.create_folder("", "Film")
      const shortsBefore = store.short_count()
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(store.short_count(), shortsBefore + 1)
      compare(project.clip_count_on("v1"), 2)
      verify(project.first_clip_on("a1").length > 0)
      const rel = store.asset_relpath(project.clip_asset_id(
         project.first_clip_on("v1")))
      verify(rel.indexOf("media/") === 0)
      verify(paths.file_exists(dir + "/" + rel))
      store.close()
      paths.remove_tree(dir)
   }

   function test_twoSceneClipsAreBackToBack() {
      const shell = createShell()
      const dir = paths.make()
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
            { prompt: "B", duration_s: 8 }
         ]
      })
      transport.enqueue_json(chatJson(script))
      transport.enqueue_file(paths.make_wav(dir))
      enqueueScene(transport, "t1")
      enqueueScene(transport, "t2")
      enqueueCover(transport, dir)
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "Topic"))
      verify(project.open_short(id))
      verify(pipeline.run(id))
      waitStopped(pipeline)
      compare(project.clip_count_on("v1"), 2)
      const first = project.clip_on_at("v1", 0)
      const second = project.clip_on_at("v1", 1)
      const firstEnd = project.clip_start(first) +
         (project.clip_out(first) - project.clip_in(first))
      compare(project.clip_start(second), firstEnd)
      store.close()
      paths.remove_tree(dir)
   }

   function test_exportUsesSameDocument() {
      const shell = createShell()
      const ctx = openImported(shell, "vertical-short.mp4")
      const video = ctx.project.first_clip_on("v1")
      ctx.project.selectedClipId = video
      ctx.project.playheadMs = Math.floor(
         ctx.project.clip_out(video) / 2)
      ctx.project.split_at_playhead()
      const audio = ctx.project.first_clip_on("a1")
      ctx.project.set_volume(audio, 0.2)
      compare(ctx.project.clipCount, 2)
      compare(ctx.project.export_volume(audio), 0.2)
      ctx.store.close()
      paths.remove_tree(ctx.dir)
   }

   function test_dropAssetFromMediaPlacesClip() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      const project = requireChild(shell, "projectDocument")
      const host = requireChild(shell, "timelineHost")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const asset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      verify(asset.length > 0)
      compare(project.clipCount, 0)
      verify(host.drop_asset_on(asset, "video", "v1", 0).length === 0)
      const id = store.create_short(folder, "Clip")
      pane.select_entry(id, "short")
      tryVerify(function() {
         return project.shortId === id &&
            requireChild(shell, "trackV1").visible
      })
      verify(findChild(shell, "timelineAssetDrop") !== null)
      verify(findChild(shell, "mediaAssetRow") !== null)
      const placed = host.drop_asset_on(asset, "video", "v1", 0)
      verify(placed.length > 0)
      compare(project.clip_track(placed), "v1")
      compare(project.clip_asset_id(placed), asset)
      compare(project.clipCount, 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_dropAudioAndImageUseDefaultTracks() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      const project = requireChild(shell, "projectDocument")
      const host = requireChild(shell, "timelineHost")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      pane.select_entry(id, "short")
      tryVerify(function() { return project.shortId === id })
      const wav = store.import_media("", paths.make_wav(dir))
      const image = store.import_media("", paths.make_image(dir))
      const audioClip = host.drop_asset_on(wav, "audio", "v1", 0)
      verify(audioClip.length > 0)
      compare(project.clip_track(audioClip), "a1")
      const imageClip = host.drop_asset_on(image, "image", "a1", 0)
      verify(imageClip.length > 0)
      compare(project.clip_track(imageClip), "v2")
      store.close()
      paths.remove_tree(dir)
   }

   function test_dropOnJunctionInserts() {
      const shell = createShell()
      const dir = paths.make()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      const project = requireChild(shell, "projectDocument")
      const host = requireChild(shell, "timelineHost")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      pane.select_entry(id, "short")
      tryVerify(function() { return project.shortId === id })
      const asset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      const first = host.drop_asset_on(asset, "video", "v1", 0)
      verify(first.length > 0)
      const length = project.clip_out(first) - project.clip_in(first)
      const second = host.drop_asset_on(asset, "video", "v1", length)
      verify(second.length > 0)
      compare(project.clipCount, 2)
      const inserted = host.drop_asset_on(asset, "video", "v1", length)
      verify(inserted.length > 0)
      compare(project.clipCount, 3)
      compare(project.clip_start(second), length * 2)
      store.close()
      paths.remove_tree(dir)
   }
}
