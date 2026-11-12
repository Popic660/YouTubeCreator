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
      compare(store.user_version(), 2)
      verify(store.schema_contains("folders"))
      verify(store.schema_contains("shorts"))
      verify(store.schema_contains("folders_name"))
      verify(store.schema_contains("shorts_name"))
      verify(store.schema_contains("shorts_folder"))
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
      compare(store.user_version(), 2)
      compare(store.folder_name("f1"), "Old")
      const clip = store.create_short("f1", "Draft")
      compare(store.short_duration_ms(clip), 0)
      verify(!store.short_has_poster(clip))
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
      compare(requireChild(shell, "promptField").background.radius, 4)
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
      requireChild(shell, "libraryModel").toggle_id(parent)
      const pane = requireChild(shell, "libraryPane")
      const glyph = requireChild(pane, "folderGlyph")
      verify(glyph.signature.length > 0)
      compare(glyph.glyphName, "folder")
      const line = requireChild(pane, "nestLine")
      compare(line.width, 1)
      compare(line.color, Qt.rgba(1, 1, 1, 0.2))
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
      const fresh = createShell()
      const freshLibrary = requireChild(fresh, "libraryPane")
      const freshFrame = requireChild(fresh, "frameView")
      const freshTimeline = requireChild(fresh, "timelineHost")
      verify(itemPos(freshLibrary, fresh).x > itemPos(freshFrame, fresh).x)
      verify(itemPos(freshTimeline, fresh).y + 1
         >= itemPos(freshFrame, fresh).y + freshFrame.height)
   }
}
