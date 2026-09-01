import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        environment.model.start()
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        environment.deckCoordinator.start()
        environment.undoToast.start()
        HotKeyManager.shared.onNewNote = { [weak self] in self?.newNote() }
        HotKeyManager.shared.onAllNotes = { [weak self] in self?.openAllNotes() }
        HotKeyManager.shared.onArchive = { [weak self] in self?.openArchive() }
        HotKeyManager.shared.registerDefaults()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        HotKeyManager.shared.unregisterAll()
        environment.deckCoordinator.stop()
        environment.undoToast.stop()
        Task { await environment.dictation.cancel() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func newNote() { environment.deckCoordinator.createAndExpand() }
    @objc func openAllNotes() { environment.libraryWindow.show(archive: false) }
    @objc func openArchive() { environment.libraryWindow.show(archive: true) }
    @objc func openSettings() {
        NotificationCenter.default.post(name: .pocketStackOpenSettings, object: nil)
    }
    @objc func importNotes() { NoteTransfer.importFiles(into: environment.model) }
    @objc func exportMarkdown() { NoteTransfer.export(.markdownFolder, notes: environment.model.notes) }
    @objc func exportText() { NoteTransfer.export(.textFolder, notes: environment.model.notes) }
    @objc func exportDocument() { NoteTransfer.export(.singleDocument, notes: environment.model.notes) }
    @objc func exportArchive() { NoteTransfer.export(.archive, notes: environment.model.notes) }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Pocket Stack")
        add("New Note", #selector(newNote), "n", [.command, .option], to: appMenu)
        add("All Notes", #selector(openAllNotes), "a", [.command, .option], to: appMenu)
        add("Archive", #selector(openArchive), "l", [.command, .option], to: appMenu)
        appMenu.addItem(.separator())
        add("Settings…", #selector(openSettings), ",", [.command], to: appMenu)
        add("Import…", #selector(importNotes), "i", [.command], to: appMenu)
        let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu()
        add("Markdown Folder…", #selector(exportMarkdown), "", [], to: exportMenu)
        add("Text Folder…", #selector(exportText), "", [], to: exportMenu)
        add("Single Document…", #selector(exportDocument), "", [], to: exportMenu)
        add("Pocket Stack Archive…", #selector(exportArchive), "", [], to: exportMenu)
        export.submenu = exportMenu; appMenu.addItem(export)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Pocket Stack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)

        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }

    private func add(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers; item.target = self
    }
}
