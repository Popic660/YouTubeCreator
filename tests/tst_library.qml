import QtQuick
import QtTest
import Creator
import CreatorTests 1.0

TestCase {
   id: testCase
   name: "Library"
   when: windowShown

   TempDirectory { id: paths }

   Component {
      id: storeComponent
      CLibraryStore {}
   }
   Component {
      id: projectComponent
      CProjectDocument {}
   }
   Component {
      id: modelComponent
      CLibraryModel {}
   }
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

   function itemPos(item, shell) {
      return item.mapToItem(shell.contentItem, 0, 0)
   }

   function assertDialogCentered(shell, name) {
      const dialog = requireChild(shell, name)
      const host = shell.contentItem
      tryVerify(function() {
         if (!dialog.visible || dialog.width < 100) {
            return false
         }
         const centerX = dialog.x + dialog.width / 2
         const centerY = dialog.y + dialog.height / 2
         return Math.abs(centerX - host.width / 2) < 40
            && Math.abs(centerY - host.height / 2) < 40
            && dialog.x >= -1 && dialog.y >= -1
            && dialog.x + dialog.width <= host.width + 2
            && dialog.y + dialog.height <= host.height + 2
      })
      dialog.close()
   }

   function createStore() {
      const store = createTemporaryObject(storeComponent, testCase)
      verify(store !== null)
      return store
   }

   function createModel(store) {
      const model = createTemporaryObject(modelComponent, testCase)
      verify(model !== null)
      model.store = store
      return model
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

   function test_openAndReopen() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      verify(store.schema_contains("folders"))
      verify(store.schema_contains("shorts"))
      verify(store.schema_contains("bins"))
      verify(store.schema_contains("assets"))
      verify(store.schema_contains("tasks"))
      verify(store.schema_contains("channels"))
      verify(store.schema_contains("publications"))
      verify(store.schema_contains("stats_snapshots"))
      verify(store.schema_contains("quota_usage"))
      compare(store.publication_count(), 0)
      verify(store.schema_contains("folders_name"))
      verify(store.schema_contains("shorts_name"))
      verify(store.schema_contains("shorts_folder"))
      verify(store.rootBinId.length > 0)
      const id = store.create_folder("", "Clips")
      verify(id.length > 0)
      store.close()

      const again = createStore()
      verify(again.open(dir))
      compare(again.folder_name(id), "Clips")
      again.close()

      const missing = createStore()
      verify(!missing.open(dir + "/missing"))
      verify(!missing.opened)
      paths.remove_tree(dir)
   }

   function test_migrateFromV1() {
      const dir = paths.make()
      verify(paths.seed_schema_v1(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      verify(store.schema_contains("bins"))
      verify(store.schema_contains("channels"))
      verify(store.rootBinId.length > 0)
      const clip = store.create_short("f1", "Draft")
      compare(store.short_duration_ms(clip), 0)
      verify(!store.short_has_poster(clip))
      store.close()
      paths.remove_tree(dir)
   }

   function test_migrateFromV2RegistersAssets() {
      const dir = paths.make()
      verify(paths.seed_schema_v2(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      compare(store.short_name("s1"), "Clip")
      compare(store.asset_name("a1"), "vertical-short")
      compare(store.asset_relpath("a1"),
         "media/a1/vertical-short.mp4")
      compare(store.asset_kind("a1"), "video")
      verify(store.rootBinId.length > 0)
      compare(store.asset_bin("a1"), store.rootBinId)
      store.close()
      paths.remove_tree(dir)
   }

   function test_nestedBinsRenameReparentAndEmptyName() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const before = store.bin_count()
      const parent = store.create_bin("", "Parent")
      verify(parent.length > 0)
      compare(store.bin_parent(parent), store.rootBinId)
      const child = store.create_bin(parent, "Child")
      compare(store.bin_parent(child), parent)
      verify(store.rename_bin(child, "Renamed"))
      compare(store.bin_name(child), "Renamed")
      verify(!store.rename_bin(child, "  "))
      compare(store.bin_name(child), "Renamed")
      verify(store.create_bin("", "").length === 0)
      compare(store.bin_count(), before + 2)
      const other = store.create_bin("", "Other")
      verify(store.reparent_bin(child, other))
      compare(store.bin_parent(child), other)
      verify(!store.reparent_bin(other, child))
      compare(store.bin_parent(other), store.rootBinId)
      store.close()
      paths.remove_tree(dir)
   }

   function test_importMediaDoesNotCreateShort() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const shortsBefore = store.short_count()
      const filesBefore = store.media_file_count()
      const asset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      verify(asset.length > 0)
      compare(store.asset_kind(asset), "video")
      verify(store.asset_relpath(asset).indexOf("media/") === 0)
      verify(store.asset_duration_ms(asset) > 0)
      compare(store.short_count(), shortsBefore)
      compare(store.media_file_count(), filesBefore + 1)
      store.close()
      paths.remove_tree(dir)
   }

   function test_importKindsAndFingerprintReuse() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const image = store.import_media("", paths.make_image(dir))
      verify(image.length > 0)
      compare(store.asset_kind(image), "image")
      const wav = store.import_media("", paths.make_wav(dir))
      verify(wav.length > 0)
      compare(store.asset_kind(wav), "audio")
      verify(store.import_media("", "").length === 0)
      const fixture = paths.fixture_path("vertical-short.mp4")
      const first = store.import_media("", fixture)
      const files = store.media_file_count()
      const second = store.import_media("", fixture)
      compare(second, first)
      compare(store.media_file_count(), files)
      const otherBin = store.create_bin("", "Broll")
      const moved = store.import_media(otherBin, fixture)
      verify(moved.length > 0)
      verify(moved !== first)
      compare(store.asset_relpath(moved), store.asset_relpath(first))
      compare(store.media_file_count(), files)
      store.close()
      paths.remove_tree(dir)
   }

   function test_importFolderMirrorsBins() {
      const dir = paths.make()
      const disk = paths.make()
      const inner = disk + "/Shoot/Inner"
      verify(paths.mkpath(inner))
      verify(paths.copy_file(
         paths.fixture_path("vertical-short.mp4"),
         inner + "/clip.mp4"))
      const store = createStore()
      verify(store.open(dir))
      const shortsBefore = store.short_count()
      const bin = store.import_folder("", disk + "/Shoot")
      verify(bin.length > 0)
      compare(store.bin_name(bin), "Shoot")
      const innerId = store.bin_by_name("Inner")
      verify(innerId.length > 0)
      compare(store.bin_parent(innerId), bin)
      const assetId = store.asset_by_name("clip")
      verify(assetId.length > 0)
      compare(store.asset_bin(assetId), innerId)
      verify(store.bin_count() >= 3)
      compare(store.short_count(), shortsBefore)
      store.close()
      paths.remove_tree(dir)
      paths.remove_tree(disk)
   }

   function test_deleteAssetBusyAndFree() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const freeAsset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      verify(freeAsset.length > 0)
      verify(!store.delete_asset(freeAsset, false))
      compare(store.asset_name(freeAsset), "vertical-short")
      verify(store.delete_asset(freeAsset, true))
      compare(store.asset_name(freeAsset), "")
      compare(store.media_file_count(), 0)

      const busyAsset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      const folder = store.create_folder("", "Film")
      const draft = store.create_short(folder, "Draft")
      const project = createTemporaryObject(
         projectComponent, testCase)
      verify(project !== null)
      project.store = store
      verify(project.open_short(draft))
      const clip = project.place_asset(busyAsset, "v1", 0, false)
      verify(clip.length > 0)
      verify(store.asset_is_busy(busyAsset))
      verify(!store.delete_asset(busyAsset, true))
      compare(store.lastError, "busy")
      compare(store.asset_name(busyAsset), "vertical-short")
      verify(store.media_file_count() >= 1)
      project.close()
      store.close()
      paths.remove_tree(dir)
   }

   function test_nestedRenameAndEmptyName() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      const child = store.create_folder(parent, "Child")
      compare(store.folder_parent(child), parent)
      verify(store.rename_folder(child, "Renamed"))
      compare(store.folder_name(child), "Renamed")
      verify(!store.rename_folder(child, "  "))
      compare(store.folder_name(child), "Renamed")
      verify(store.create_folder("", "").length === 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_effectivePrompt() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const root = store.create_folder("", "Root")
      verify(store.set_folder_prompt(root, "Hello"))
      compare(store.effective_prompt(root), "Hello")
      const child = store.create_folder(root, "Child")
      verify(store.set_folder_prompt(child, "World"))
      compare(store.effective_prompt(child), "Hello\n\nWorld")
      const emptyChild = store.create_folder(root, "Empty")
      compare(store.effective_prompt(emptyChild), "Hello")
      verify(store.set_folder_prompt(root, "Next"))
      compare(store.effective_prompt(child), "Next\n\nWorld")
      store.close()
      paths.remove_tree(dir)
   }

   function test_deleteFolder() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      const nested = store.create_folder(parent, "Nested")
      const clip = store.create_short(nested, "Clip")
      verify(!store.delete_folder(parent, false))
      compare(store.folder_name(parent), "Parent")
      compare(store.short_name(clip), "Clip")
      verify(store.delete_folder(parent, true))
      compare(store.folder_name(parent), "")
      compare(store.folder_name(nested), "")
      compare(store.short_name(clip), "")

      const empty = store.create_folder("", "Empty")
      const inner = store.create_folder(empty, "Inner")
      verify(store.delete_folder(empty, false))
      compare(store.folder_name(empty), "")
      compare(store.folder_name(inner), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_shortDraftMoveAndDelete() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const source = store.create_folder("", "Source")
      const target = store.create_folder("", "Target")
      verify(store.create_short(source, " ").length === 0)
      const clip = store.create_short(source, "Voice")
      compare(store.short_status(clip), "draft")
      verify(!store.short_has_poster(clip))
      verify(store.rename_short(clip, "Voice 2"))
      compare(store.short_name(clip), "Voice 2")
      verify(store.move_short(clip, target))
      compare(store.short_folder(clip), target)
      verify(!store.delete_short(clip, false))
      compare(store.short_name(clip), "Voice 2")
      verify(store.delete_short(clip, true))
      compare(store.short_name(clip), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_reparentRejectsDescendant() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      const child = store.create_folder(parent, "Child")
      verify(store.reparent_folder(parent, child) === false)
      compare(store.folder_parent(parent), "")
      verify(store.reparent_folder(child, ""))
      compare(store.folder_parent(child), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_modelExpansionAndOrder() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      store.create_folder("", "b")
      const parent = store.create_folder("", "A")
      store.create_folder(parent, "Child")
      store.create_short(parent, "Clip")
      const model = createModel(store)
      compare(model.row_name(0), "A")
      compare(model.row_name(1), "b")
      compare(model.count, 2)
      model.toggle_row(0)
      compare(model.count, 4)
      compare(model.row_name(1), "Child")
      compare(model.row_kind(1), "folder")
      compare(model.row_depth(1), 1)
      compare(model.row_name(2), "Clip")
      compare(model.row_kind(2), "short")
      model.toggle_row(0)
      compare(model.count, 2)
      compare(model.row_kind(0), "folder")
      store.close()
      paths.remove_tree(dir)
   }

   function test_modelFilter() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      store.set_folder_prompt(parent, "secret-style")
      store.create_short(parent, "Clip one")
      store.create_folder("", "Other")
      const model = createModel(store)
      model.filter = "clip"
      compare(model.count, 2)
      compare(model.row_name(0), "Parent")
      compare(model.row_name(1), "Clip one")
      model.filter = "CLIP"
      compare(model.count, 2)
      model.filter = "secret-style"
      compare(model.count, 0)
      model.filter = ""
      compare(model.count, 2)
      compare(model.row_name(0), "Other")
      compare(model.row_name(1), "Parent")
      store.close()
      paths.remove_tree(dir)
   }

   function test_closedPaneOffersChoice() {
      const shell = createShell()
      const pane = requireChild(shell, "libraryPane")
      compare(pane.rowCount, 0)
      verify(requireChild(shell, "chooseLibraryButton").visible)
      requireChild(shell, "searchText").text = "query"
      verify(findChild(shell, "notFoundMessage") === null)
      compare(pane.rowCount, 0)
   }

   function test_placeholderCard() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      store.create_short(parent, "Card title")
      const model = requireChild(shell, "libraryModel")
      model.toggle_id(parent)
      compare(model.count, 2)
      const pane = requireChild(shell, "libraryPane")
      let card = null
      tryVerify(function() {
         card = findChild(pane, "shortPlaceholder")
         return card !== null
      })
      compare(card.radius, 12)
      const title = findChild(card.parent, "shortTitle")
      verify(title !== null)
      compare(title.maximumLineCount, 2)
      verify(findChild(pane, "durationBadge") === null)
      store.close()
      paths.remove_tree(dir)
   }

   function test_folderMenu() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const id = store.create_folder("", "Box")
      requireChild(shell, "libraryPane").open_menu(id)
      compare(requireChild(shell, "folderMenuSurface").color, "#282828")
      verify(findChild(shell, "menuCreateFolder") !== null)
      verify(findChild(shell, "menuCreateShort") !== null)
      verify(findChild(shell, "menuRename") !== null)
      verify(findChild(shell, "menuDelete") !== null)
      verify(findChild(shell, "menuPrompt") !== null)
      store.close()
      paths.remove_tree(dir)
   }

   function test_dialogsRenamePromptAndCancelDelete() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      requireChild(shell, "createRootButton").clicked()
      const nameField = requireChild(shell, "nameField")
      compare(nameField.background.radius, 4)
      nameField.text = "Parent"
      requireChild(shell, "nameAccept").clicked()
      const model = requireChild(shell, "libraryModel")
      compare(model.row_name(0), "Parent")
      const parentId = model.row_id(0)

      pane.open_menu(parentId)
      requireChild(shell, "menuPrompt").triggered()
      compare(requireChild(shell, "promptFieldFrame").radius, 4)
      requireChild(shell, "promptField").text = "Parent style"
      requireChild(shell, "promptAccept").clicked()
      compare(store.folder_prompt(parentId), "Parent style")

      pane.open_menu(parentId)
      requireChild(shell, "menuCreateFolder").triggered()
      requireChild(shell, "nameField").text = "Child"
      requireChild(shell, "nameAccept").clicked()
      model.toggle_id(parentId)
      let childId = ""
      for (let i = 0; i < model.count; ++i) {
         if (model.row_name(i) === "Child") {
            childId = model.row_id(i)
         }
      }
      verify(childId.length > 0)
      pane.open_menu(childId)
      requireChild(shell, "menuPrompt").triggered()
      const inherited = requireChild(shell, "inheritedPrompt")
      compare(inherited.text, "Parent style")
      requireChild(shell, "promptField").text = "Child style"
      requireChild(shell, "promptAccept").clicked()
      compare(store.effective_prompt(childId),
         "Parent style\n\nChild style")

      pane.open_menu(parentId)
      requireChild(shell, "menuCreateShort").triggered()
      requireChild(shell, "nameField").text = "Clip"
      requireChild(shell, "nameAccept").clicked()
      pane.open_menu(parentId)
      requireChild(shell, "menuDelete").triggered()
      const accept = requireChild(shell, "confirmAccept")
      const cancel = requireChild(shell, "confirmCancel")
      compare(accept.background.color, "#f1f1f1")
      compare(cancel.background.color, Qt.rgba(1, 1, 1, 0.1))
      cancel.clicked()
      let clipRemains = false
      for (let j = 0; j < model.count; ++j) {
         if (model.row_name(j) === "Clip") {
            clipRemains = true
         }
      }
      verify(clipRemains)
      store.close()
      paths.remove_tree(dir)
   }

   function test_dropHandler() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      const child = store.create_folder(parent, "Child")
      const other = store.create_folder("", "Other")
      const clip = store.create_short(parent, "Clip")
      verify(pane.handle_drop(clip, "short", other))
      compare(store.short_folder(clip), other)
      verify(!pane.handle_drop(parent, "folder", child))
      compare(store.folder_parent(parent), "")
      store.close()
      paths.remove_tree(dir)
   }

   function test_searchInHeader() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      store.set_folder_prompt(parent, "secret-style")
      store.create_short(parent, "Clip one")
      store.create_folder("", "Other")
      const model = requireChild(shell, "libraryModel")
      requireChild(shell, "searchText").text = "clip"
      compare(model.count, 2)
      compare(model.row_name(0), "Parent")
      compare(model.row_kind(1), "short")
      requireChild(shell, "searchText").text = "secret-style"
      compare(model.count, 0)
      const message = requireChild(shell, "notFoundMessage")
      compare(message.text, "Ничего не найдено")
      compare(message.color, "#aaaaaa")
      requireChild(shell, "searchText").text = ""
      compare(model.count, 2)
      tryVerify(function() {
         return findChild(shell, "notFoundMessage") === null
      })

      const asset = store.import_media("",
         paths.fixture_path("vertical-short.mp4"))
      verify(asset.length > 0)
      const mediaModel = requireChild(shell, "mediaModel")
      requireChild(shell, "searchText").text = "vertical-short"
      compare(model.count, 0)
      verify(requireChild(shell, "notFoundMessage").visible)
      verify(mediaModel.count >= 1)
      verify(findChild(shell, "mediaNotFoundMessage") === null)
      requireChild(shell, "searchText").text = "no-such-name-zz"
      compare(model.count, 0)
      compare(mediaModel.count, 0)
      compare(requireChild(shell, "mediaNotFoundMessage").color,
         "#aaaaaa")
      requireChild(shell, "searchText").text = ""
      store.close()
      paths.remove_tree(dir)
   }

   function test_selectShortKeepsFrameEmpty() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      const clip = store.create_short(parent, "Clip")
      pane.select_entry(clip, "short")
      const frame = requireChild(shell, "frameView")
      compare(frame.centerMode, "empty")
      compare(frame.hasFrameImage, false)
      compare(requireChild(shell, "timelineHost").clipCount, 0)
      compare(requireChild(shell, "toolSelect").enabled, false)
      compare(requireChild(shell, "opDelete").enabled, false)
      store.close()
      paths.remove_tree(dir)
   }

   function test_savedPathRestoresTree() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const id = store.create_folder("", "Kept")
      verify(store.set_folder_prompt(id, "Style"))
      store.close()
      paths.save_library_path(dir)

      const shell = createShell()
      const pane = requireChild(shell, "libraryPane")
      compare(pane.rowCount, 1)
      const live = requireChild(shell, "libraryStore")
      compare(live.folder_name(id), "Kept")
      compare(live.effective_prompt(id), "Style")
      live.close()

      paths.save_library_path(dir + "/missing")
      const second = createShell()
      compare(requireChild(second, "libraryPane").rowCount, 0)
      verify(requireChild(second, "chooseLibraryButton").visible)
      paths.clear_library_path()
      paths.remove_tree(dir)
   }

   function test_changeLibraryFolder() {
      const first = paths.make()
      const second = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(first))
      const alpha = store.create_folder("", "Alpha")
      verify(requireChild(shell, "changeLibraryButton").visible)
      pane.decline_library_folder()
      compare(store.folder_name(alpha), "Alpha")
      pane.apply_library_folder(second)
      compare(store.folder_name(alpha), "")
      const beta = store.create_folder("", "Beta")
      compare(store.folder_name(beta), "Beta")
      store.close()
      paths.remove_tree(first)
      paths.remove_tree(second)
   }

   function test_mediaChromeGridAndScrub() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      compare(requireChild(shell, "libraryChromeTitle").text, "Папки")
      compare(requireChild(shell, "mediaChromeTitle").text, "Медиа")
      const media = requireChild(shell, "mediaPane")
      const asset = store.import_media(
         "", paths.fixture_path("vertical-short.mp4"))
      verify(asset.length > 0)
      media.gridMode = true
      let preview = null
      tryVerify(function() {
         preview = findChild(media, "mediaPreview")
         return preview !== null
      })
      compare(preview.radius, 12)
      const badge = findChild(media, "mediaDurationBadge")
      verify(badge !== null)
      compare(media.hover_scrub(25, 100, 1000), 250)
      compare(media.lastScrubMs, 250)
      store.close()
      paths.remove_tree(dir)
   }

   function test_dockChipsSelectedText() {
      const shell = createShell()
      shell.place_panel("library", "left")
      const tab = requireChild(shell, "tabLibrary")
      compare(tab.radius, 8)
      compare(tab.height, 32)
      compare(tab.color, "#f1f1f1")
      const label = tab.children[0]
      compare(label.color, "#0f0f0f")
      DockState.reset_layout()
   }

   function test_searchGlyph() {
      const shell = createShell()
      const glyph = requireChild(shell, "searchGlyph")
      verify(glyph.signature.length > 0)
      compare(glyph.strokeColor, "#f1f1f1")
      verify(glyph.signature !== "")
   }

   function test_dialogsAreCentered() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      const id = store.create_folder("", "Box")
      pane.open_name_dialog("createRoot", "")
      assertDialogCentered(shell, "nameDialog")
      pane.open_menu(id)
      pane.open_prompt_dialog()
      assertDialogCentered(shell, "promptDialog")
      store.close()
      paths.remove_tree(dir)
   }

   function test_folderGlyphAndNestLine() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const parent = store.create_folder("", "Parent")
      store.create_folder(parent, "Child")
      store.create_short(parent, "Clip")
      requireChild(shell, "libraryModel").toggle_id(parent)
      const pane = requireChild(shell, "libraryPane")
      const glyph = requireChild(pane, "folderGlyph")
      verify(glyph.signature.length > 0)
      compare(glyph.glyphName, "folder")
      const line = requireChild(pane, "nestLine")
      compare(line.width, 1)
      compare(line.color, "#717171")
      compare(glyph.height, 24)
      const parentRow = glyph.parent
      compare(parentRow.height, 40)
      const shortGlyph = requireChild(pane, "shortGlyph")
      compare(shortGlyph.glyphName, "short")
      verify(shortGlyph.signature !== glyph.signature)
      store.close()
      paths.remove_tree(dir)
   }

   function test_dockSizesPersist() {
      DockState.rightWidth = 300
      DockState.bottomHeight = 180
      const shell = createShell()
      verify(requireChild(shell, "splitterRight").visible)
      verify(requireChild(shell, "splitterBottom").visible)
      const library = requireChild(shell, "libraryPane")
      const timeline = requireChild(shell, "timelineHost")
      const frame = requireChild(shell, "frameView")
      tryVerify(function() { return Math.abs(library.width - 300) < 12 })
      tryVerify(function() { return Math.abs(timeline.height - 180) < 16 })
      verify(frame.width > 80)
      const again = createShell()
      tryVerify(function() {
         return Math.abs(requireChild(again, "libraryPane").width - 300) < 12
      })
      tryVerify(function() {
         return Math.abs(requireChild(again, "timelineHost").height - 180) < 16
      })
   }

   function test_panelDragStartsAfterMoveNotPress() {
      DockState.reset_layout()
      const shell = createShell()
      const handle = requireChild(shell, "libraryChromeDrag")
      tryVerify(function() {
         return handle.width > 20 && handle.height > 10
      })
      compare(shell.panelDragging, false)
      mousePress(handle, 12, 16)
      compare(shell.panelDragging, false)
      mouseMove(handle, -48, 16, 1, Qt.LeftButton)
      tryVerify(function() { return shell.panelDragging === true })
      mouseRelease(handle, -48, 16)
      tryVerify(function() { return shell.panelDragging === false })
      DockState.reset_layout()
   }

   function test_acceptPanelDropMovesLibrary() {
      DockState.reset_layout()
      const shell = createShell()
      compare(DockState.libraryDock, "right")
      const source = { panelId: "library" }
      const drop = {
         source: source,
         acceptProposedAction: function() {}
      }
      shell.accept_panel_drop(drop, "left")
      compare(DockState.libraryDock, "left")
      const empty = { source: {}, acceptProposedAction: function() {} }
      shell.accept_panel_drop(empty, "bottom")
      compare(DockState.libraryDock, "left")
      DockState.reset_layout()
   }

   function test_dragLibraryChromeToLeftDock() {
      DockState.reset_layout()
      const shell = createShell()
      compare(DockState.libraryDock, "right")
      const handle = requireChild(shell, "libraryChromeDrag")
      const left = requireChild(shell, "dockLeft")
      tryVerify(function() {
         return handle.width > 20 && handle.height > 10 && left.width > 80
      })
      mousePress(handle, 12, 16)
      mouseMove(handle, -80, 16, 1, Qt.LeftButton)
      tryVerify(function() { return shell.panelDragging === true })
      const dest = left.mapToItem(shell.contentItem,
         left.width / 2, left.height / 2)
      mouseMove(shell.contentItem, dest.x, dest.y, 1, Qt.LeftButton)
      mouseRelease(shell.contentItem, dest.x, dest.y)
      tryVerify(function() { return DockState.libraryDock === "left" })
      DockState.reset_layout()
   }

   function test_moveDocksAndRemember() {
      const shell = createShell()
      shell.place_panel("library", "left")
      shell.place_panel("timeline", "right")
      const library = requireChild(shell, "libraryPane")
      const timeline = requireChild(shell, "timelineHost")
      const frame = requireChild(shell, "frameView")
      const tools = requireChild(shell, "toolColumn")
      tryVerify(function() {
         return itemPos(library, shell).x + 4 < itemPos(frame, shell).x
      })
      verify(itemPos(timeline, shell).x > itemPos(frame, shell).x)
      verify(itemPos(tools, shell).x + tools.width <= itemPos(frame, shell).x + 8)
      shell.show_drop_target("bottom")
      verify(requireChild(shell, "dockBottom").highlighted)
      shell.clear_drop_target()
      shell.place_panel("timeline", "left")
      verify(requireChild(shell, "dockTabs").visible)
      verify(findChild(shell, "tabLibrary") !== null)
      verify(findChild(shell, "tabTimeline") !== null)
      const again = createShell()
      const libraryAgain = requireChild(again, "libraryPane")
      const frameAgain = requireChild(again, "frameView")
      const timelineAgain = requireChild(again, "timelineHost")
      verify(itemPos(libraryAgain, again).x < itemPos(frameAgain, again).x)
      verify(itemPos(timelineAgain, again).x < itemPos(frameAgain, again).x)
      DockState.reset_layout()
      const resetShell = createShell()
      compare(DockState.mediaDock, "left")
      compare(DockState.libraryDock, "right")
      compare(DockState.timelineDock, "bottom")
      const mediaReset = requireChild(resetShell, "mediaPane")
      const frameReset = requireChild(resetShell, "frameView")
      verify(itemPos(mediaReset, resetShell).x + 4
         < itemPos(frameReset, resetShell).x)
      const fresh = createShell()
      const freshLibrary = requireChild(fresh, "libraryPane")
      const freshFrame = requireChild(fresh, "frameView")
      const freshTimeline = requireChild(fresh, "timelineHost")
      verify(itemPos(freshLibrary, fresh).x > itemPos(freshFrame, fresh).x)
      verify(itemPos(freshTimeline, fresh).y + 1
         >= itemPos(freshFrame, fresh).y + freshFrame.height)
   }

   function test_migrateFromV3AddsTopicScriptTasks() {
      const dir = paths.make()
      verify(paths.seed_schema_v3(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      compare(store.short_name("s1"), "Clip")
      compare(store.short_status("s1"), "draft")
      compare(store.short_topic("s1"), "")
      compare(store.short_script("s1"), "")
      verify(store.schema_contains("tasks"))
      verify(store.schema_contains("channels"))
      store.close()
      paths.remove_tree(dir)
   }

   function test_migrateFromV4AddsCoverRelpath() {
      const dir = paths.make()
      verify(paths.seed_schema_v4(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      compare(store.short_name("s1"), "Clip")
      compare(store.short_status("s1"), "draft")
      compare(store.short_topic("s1"), "Old topic")
      compare(store.short_script("s1"), "Old script")
      compare(store.short_cover_relpath("s1"), "")
      verify(store.schema_contains("channels"))
      store.close()
      paths.remove_tree(dir)
   }

   function test_coverRelpathPersistsAndIsNotSearched() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      const rel = "shorts/" + id + "/youtube_cover.jpg"
      verify(store.set_cover_relpath(id, rel))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.short_cover_relpath(id), rel)
      again.close()
      verify(store.open(dir))
      requireChild(shell, "searchText").text = "youtube_cover.jpg"
      compare(requireChild(shell, "libraryModel").count, 0)
      compare(requireChild(shell, "notFoundMessage").text,
         "Ничего не найдено")
      store.close()
      paths.remove_tree(dir)
   }

   function test_topicPersistsAndIsNotSearched() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_topic(id, "unique-topic-zz"))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.short_topic(id), "unique-topic-zz")
      again.close()
      verify(store.open(dir))
      requireChild(shell, "searchText").text = "unique-topic-zz"
      compare(requireChild(shell, "libraryModel").count, 0)
      compare(requireChild(shell, "notFoundMessage").text,
         "Ничего не найдено")
      store.close()
      paths.remove_tree(dir)
   }

   function test_scriptPersistsAndIsNotSearched() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      verify(store.set_script(id, "unique-script-yy"))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.short_script(id), "unique-script-yy")
      again.close()
      verify(store.open(dir))
      requireChild(shell, "searchText").text = "unique-script-yy"
      compare(requireChild(shell, "libraryModel").count, 0)
      compare(requireChild(shell, "notFoundMessage").text,
         "Ничего не найдено")
      store.close()
      paths.remove_tree(dir)
   }

   function test_topicDialogSavesAndEmptyDoesNotRun() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      verify(store.open(dir))
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")
      const pane = requireChild(shell, "libraryPane")
      pane.open_short_menu(id)
      const menu = requireChild(shell, "menuTopicVoice")
      compare(menu.text, "Тема и голос")
      pane.open_topic_dialog()
      const field = requireChild(shell, "topicField")
      tryVerify(function() { return field.visible })
      compare(requireChild(shell, "topicFieldFrame").radius, 4)
      assertDialogCentered(shell, "topicDialog")
      pane.open_topic_dialog()
      field.text = "A topic"
      requireChild(shell, "topicGenerate").clicked()
      compare(store.short_topic(id), "A topic")
      pane.open_topic_dialog()
      field.text = ""
      const status = store.short_status(id)
      requireChild(shell, "topicGenerate").clicked()
      compare(store.short_status(id), status)
      store.close()
      paths.remove_tree(dir)
   }

   function test_promptAndTopicDialogsShowTitleCountAndScroll() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      const folder = store.create_folder("", "Film")
      const id = store.create_short(folder, "Clip")

      pane.open_menu(folder)
      pane.open_prompt_dialog()
      const promptTitle = requireChild(shell, "promptDialogTitle")
      compare(promptTitle.text, "Введите промт для папки")
      const promptField = requireChild(shell, "promptField")
      const promptFrame = requireChild(shell, "promptFieldFrame")
      const promptCount = requireChild(shell, "promptCharCount")
      const promptScroll = requireChild(shell, "promptScroll")
      tryVerify(function() {
         return promptFrame.height >= 160 &&
            requireChild(shell, "promptDialog").width >= 480
      })
      compare(promptField.wrapMode, TextEdit.Wrap)
      compare(promptCount.text, "0 символов")
      promptField.text = "abc"
      compare(promptCount.text, "3 символа")
      let chunk = ""
      for (let i = 0; i < 80; ++i) {
         chunk += "строка текста для прокрутки\n"
      }
      promptField.text = chunk
      tryVerify(function() {
         return promptScroll.contentHeight > promptScroll.height + 20
      })
      promptField.text = "Line1\nLine2"
      requireChild(shell, "promptAccept").clicked()
      compare(store.folder_prompt(folder), "Line1\nLine2")

      pane.open_short_menu(id)
      pane.open_topic_dialog()
      const topicTitle = requireChild(shell, "topicDialogTitle")
      compare(topicTitle.text, "Введите тему и голос для видео")
      const topicField = requireChild(shell, "topicField")
      const topicFrame = requireChild(shell, "topicFieldFrame")
      const topicCount = requireChild(shell, "topicCharCount")
      const topicScroll = requireChild(shell, "topicScroll")
      tryVerify(function() {
         return topicFrame.height >= 160 &&
            requireChild(shell, "topicDialog").width >= 480
      })
      compare(topicField.wrapMode, TextEdit.Wrap)
      compare(requireChild(shell, "topicFieldFrame").radius, 4)
      topicField.text = ""
      compare(topicCount.text, "0 символов")
      topicField.text = "abc"
      compare(topicCount.text, "3 символа")
      topicField.text = chunk
      tryVerify(function() {
         return topicScroll.contentHeight > topicScroll.height + 20
      })
      requireChild(shell, "topicDialog").close()
      store.close()
      paths.remove_tree(dir)
   }

   function test_migrateFromV5AddsChannels() {
      const dir = paths.make()
      verify(paths.seed_schema_v5(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      compare(store.short_name("s1"), "Clip")
      compare(store.channel_count(), 0)
      verify(store.schema_contains("channels"))
      store.close()
      paths.remove_tree(dir)
   }

   function test_upsertChannelUpdatesSameId() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      verify(store.upsert_channel("UC1", "First"))
      verify(store.upsert_channel("UC1", "Renamed"))
      compare(store.channel_count(), 1)
      compare(store.channel_title("UC1"), "Renamed")
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.channel_count(), 1)
      compare(again.channel_title("UC1"), "Renamed")
      again.close()
      paths.remove_tree(dir)
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
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      secrets.googleClientId = "google-client-id"
      secrets.googleClientSecret = "google-client-secret"
      verify(secrets.save())
   }

   function test_twoChannelsPersistAndAreNotSearched() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      verify(store.upsert_channel("UC1", "Alpha Channel Unique"))
      verify(store.upsert_channel("UC2", "Beta Channel Unique"))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.channel_count(), 2)
      compare(again.channel_title("UC1"), "Alpha Channel Unique")
      compare(again.channel_title("UC2"), "Beta Channel Unique")
      again.close()
      verify(store.open(dir))
      requireChild(shell, "searchText").text = "Alpha Channel Unique"
      compare(requireChild(shell, "libraryModel").count, 0)
      compare(requireChild(shell, "notFoundMessage").text,
         "Ничего не найдено")
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("refresh-token-secret") < 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_startWithoutLibraryOrClientSkipsTransport() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const auth = requireChild(shell, "channelAuth")
      transport.use_stub()
      transport.clear()
      auth.use_stub()
      secrets.use_memory(true)
      secrets.clear_memory()
      secrets.load()
      auth.start()
      compare(transport.googleCount, 0)
      compare(auth.browserOpenCount, 0)
      verify(store.open(dir))
      transport.clear()
      auth.start()
      compare(transport.googleCount, 0)
      compare(auth.browserOpenCount, 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_secondChannelAndUpsertSameId() {
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
      enqueueConnect(transport, "UC1", "First", "1//r1")
      verify(auth.complete_with_code("c1"))
      enqueueConnect(transport, "UC2", "Second", "1//r2")
      verify(auth.complete_with_code("c2"))
      compare(store.channel_count(), 2)
      enqueueConnect(transport, "UC1", "First Renamed", "1//r1b")
      verify(auth.complete_with_code("c1b"))
      compare(store.channel_count(), 2)
      compare(store.channel_title("UC1"), "First Renamed")
      compare(store.channel_title("UC2"), "Second")
      store.close()
      paths.remove_tree(dir)
   }

   function test_disconnectRemovesRowAndToken() {
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
      enqueueConnect(transport, "UC1", "First", "1//r1")
      verify(auth.complete_with_code("c1"))
      enqueueConnect(transport, "UC2", "Second", "1//r2")
      verify(auth.complete_with_code("c2"))
      const before = transport.googleCount
      verify(auth.disconnect_channel("UC1"))
      compare(store.channel_count(), 1)
      compare(store.channel_title("UC2"), "Second")
      verify(!secrets.has_channel_refresh("UC1"))
      verify(secrets.has_channel_refresh("UC2"))
      compare(transport.googleCount, before)
      store.close()
      paths.remove_tree(dir)
   }

   function test_menuDisconnectClearsLastChannel() {
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
      enqueueConnect(transport, "UC1", "Only", "1//r1")
      verify(auth.complete_with_code("c1"))
      verify(shell.channelConnected)
      requireChild(shell, "channelMenuButton").clicked()
      tryVerify(function() {
         return findChild(shell, "channelItem-UC1") !== null
      })
      compare(requireChild(shell, "channelItem-UC1").text, "Only")
      verify(requireChild(shell, "channelHint").text.indexOf(
         "заглушка") < 0)
      const item = requireChild(shell, "disconnectChannel-UC1")
      item.clicked()
      compare(store.channel_count(), 0)
      compare(shell.channelConnected, false)
      store.close()
      paths.remove_tree(dir)
   }

   function test_migrateFromV6AddsPublications() {
      const dir = paths.make()
      verify(paths.seed_schema_v6(dir))
      const store = createStore()
      verify(store.open(dir))
      compare(store.user_version(), 7)
      compare(store.folder_name("f1"), "Old")
      compare(store.short_name("s1"), "Clip")
      compare(store.channel_title("UC1"), "Old Channel")
      verify(store.schema_contains("publications"))
      compare(store.publication_count(), 0)
      store.close()
      paths.remove_tree(dir)
   }

   function test_upsertPublicationUpdatesSamePair() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      const folder = store.create_folder("", "Clips")
      const clip = store.create_short(folder, "Draft")
      verify(store.upsert_publication(clip, "UC1", "vid-old",
         "private", "uploaded", "", ""))
      verify(store.upsert_publication(clip, "UC1", "vid-new",
         "public", "uploaded", "set", ""))
      compare(store.publication_count(clip), 1)
      const pub = store.publication_id_at(clip, 0)
      compare(store.publication_video_id(pub), "vid-new")
      compare(store.publication_privacy(pub), "public")
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.publication_count(clip), 1)
      const againPub = again.publication_id_at(clip, 0)
      compare(again.publication_video_id(againPub), "vid-new")
      const db = paths.read_text(dir + "/library.db")
      verify(db.indexOf("refresh-token-secret") < 0)
      again.close()
      paths.remove_tree(dir)
   }

   function test_publicationsSurviveDisconnect() {
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
      enqueueConnect(transport, "UC1", "First", "1//r1")
      verify(auth.complete_with_code("c1"))
      const folder = store.create_folder("", "Clips")
      const clip = store.create_short(folder, "Draft")
      verify(store.upsert_publication(clip, "UC1", "vid-keep",
         "private", "uploaded", "", ""))
      verify(store.upsert_publication(clip, "UC2", "vid-two",
         "unlisted", "uploaded", "", ""))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.publication_count(clip), 2)
      again.close()
      verify(store.open(dir))
      const before = transport.googleCount
      verify(auth.disconnect_channel("UC1"))
      compare(store.channel_count(), 0)
      compare(store.publication_count(clip), 2)
      verify(store.short_has_video(clip))
      compare(transport.googleCount, before)
      store.close()
      paths.remove_tree(dir)
   }

   function test_statsSnapshotPersistsAndIsNotSearched() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      verify(store.open(dir))
      const payload = JSON.stringify({
         views: 12,
         uniqueMarker: "stats-payload-zz"
      })
      verify(store.upsert_stats("video", "vid-1", payload))
      store.close()
      const again = createStore()
      verify(again.open(dir))
      compare(again.stats_payload("video", "vid-1"), payload)
      verify(again.stats_synced_ms("video", "vid-1") > 0)
      again.close()
      verify(store.open(dir))
      requireChild(shell, "searchText").text = "stats-payload-zz"
      compare(requireChild(shell, "libraryModel").count, 0)
      compare(requireChild(shell, "notFoundMessage").text,
         "Ничего не найдено")
      store.close()
      paths.remove_tree(dir)
   }

   function test_quotaRemainingHitsZeroWithoutGoogle() {
      const dir = paths.make()
      const store = createStore()
      verify(store.open(dir))
      compare(store.quota_remaining(), 100)
      for (let i = 0; i < 100; ++i) {
         verify(store.increment_quota())
      }
      compare(store.quota_remaining(), 0)
      store.close()
      paths.remove_tree(dir)
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

   function test_publishDialogFieldsAndQuota() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      const id = seedReadyShort(store, dir, "Clip Name")
      pane.select_entry(id, "short")
      const publish = requireChild(shell, "publishButton")
      compare(publish.enabled, true)
      publish.clicked()
      const dialog = requireChild(shell, "publishDialog")
      tryVerify(function() { return dialog.visible })
      compare(requireChild(shell, "publishDialogSurface").color,
         "#282828")
      compare(requireChild(shell, "publishTitleField").text,
         "Clip Name")
      compare(requireChild(shell, "publishDescriptionField").text,
         "Scene text")
      compare(requireChild(shell, "publishTitleField")
         .background.radius, 4)
      compare(requireChild(shell, "publishConfirm").filled, true)
      verify(requireChild(shell, "publishQuotaLabel").text.indexOf(
         "100") >= 0)
      tryVerify(function() {
         return findChild(shell, "publishChannelList") !== null &&
            findChild(shell, "publishChannelCheck-UC1") !== null
      })
      requireChild(shell, "publishChannelCheck-UC1")
      requireChild(shell, "publishPrivacy-private")
      requireChild(shell, "publishPrivacy-unlisted")
      requireChild(shell, "publishPrivacy-public")
      store.close()
      paths.remove_tree(dir)
   }

   function test_publishDialogNeedsChannelThenShowsVideoId() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const transport = requireChild(shell, "httpTransport")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      const id = seedReadyShort(store, dir, "Clip")
      pane.select_entry(id, "short")
      requireChild(shell, "publishButton").clicked()
      tryVerify(function() {
         return requireChild(shell, "publishDialog").visible
      })
      tryVerify(function() {
         return findChild(shell, "publishChannelList") !== null &&
            findChild(shell, "publishChannelCheck-UC1") !== null
      })
      transport.use_stub()
      transport.clear()
      requireChild(shell, "publishConfirm").clicked()
      compare(transport.googleCount, 0)
      requireChild(shell, "publishChannelCheck-UC1").checked = true
      enqueueAccess(transport, "ya29.ui")
      enqueueInsert(transport, "vid-ui")
      requireChild(shell, "publishConfirm").clicked()
      compare(store.publication_count(id), 1)
      tryVerify(function() {
         return requireChild(shell, "publishChannelStatus-UC1")
            .text.indexOf("vid-ui") >= 0
      })
      store.close()
      paths.remove_tree(dir)
   }

   function test_channelMenuOpensAnalyticsAndShortReturns() {
      const dir = paths.make()
      const shell = createShell()
      const store = requireChild(shell, "libraryStore")
      const secrets = requireChild(shell, "secretStore")
      const pane = requireChild(shell, "libraryPane")
      verify(store.open(dir))
      saveGoogleClient(secrets)
      bindChannel(store, secrets, "UC1", "Studio", "1//refresh")
      const id = seedReadyShort(store, dir, "Draft")
      pane.select_entry(id, "short")
      requireChild(shell, "channelMenuButton").clicked()
      tryVerify(function() {
         return findChild(shell, "channelItem-UC1") !== null
      })
      requireChild(shell, "channelItem-UC1").clicked()
      compare(shell.centerMode, "analytics")
      compare(pane.selectedKind, "")
      compare(requireChild(shell, "publishButton").enabled, false)
      compare(requireChild(shell, "timelineHost").visible, false)
      verify(requireChild(shell, "libraryList") !== null)
      shell.close_analytics()
      pane.open_short_menu(id)
      requireChild(shell, "menuStats").clicked()
      verify(shell.centerMode !== "analytics")
      verify(store.upsert_publication(id, "UC1", "vid-1", "unlisted",
         "uploaded", "", ""))
      pane.open_short_menu(id)
      requireChild(shell, "menuStats").clicked()
      compare(shell.centerMode, "analytics")
      pane.select_entry(id, "short")
      verify(shell.centerMode !== "analytics")
      compare(requireChild(shell, "timelineHost").visible, true)
      store.close()
      paths.remove_tree(dir)
   }
}
