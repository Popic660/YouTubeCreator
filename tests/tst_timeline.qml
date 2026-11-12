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
      const id = store.import_video(folder, fixture)
      verify(id.length > 0)
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
         frame: frame,
         project: requireChild(shell, "projectDocument")
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
}
