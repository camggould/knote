import AppKit
import Combine
import ServiceManagement
import KnoteCore
import KnoteEmbeddings
import KnoteVector

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeys: HotkeyController?
    private var panelController: PanelController?
    private var settingsWindow: SettingsWindowController?
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        do {
            let services = try Services.bootstrap()
            let appState = AppState(store: services.store,
                                    search: services.search,
                                    indexer: services.indexer)
            services.indexer.warmUp()
            let panel = PanelController(appState: appState)
            self.panelController = panel

            let hotkeys = HotkeyController { [weak panel] in panel?.toggle() }
            self.hotkeys = hotkeys
            self.settingsWindow = SettingsWindowController(
                hotkeys: hotkeys, encoderName: services.encoderName)

            setupStatusItem(hotkeys: hotkeys)
        } catch {
            NSLog("knote: failed to start: \(error)")
            let alert = NSAlert()
            alert.messageText = "knote failed to start"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu bar

    private var openMenuItem: NSMenuItem?
    private var hotkeyObserver: AnyCancellable?

    private func setupStatusItem(hotkeys: HotkeyController) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "knote")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open knote  (\(hotkeys.hotkey.label))",
                              action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openMenuItem = open

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(checkForUpdatesMenuAction),
                                      keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit knote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item

        // Keep the menu label in sync when the shortcut is rebound in Settings.
        hotkeyObserver = hotkeys.$hotkey.sink { [weak self] hk in
            self?.openMenuItem?.title = "Open knote  (\(hk.label))"
        }
    }

    @objc private func openPanel() { panelController?.show() }

    @objc private func openSettings() { settingsWindow?.show() }

    @objc private func checkForUpdatesMenuAction() {
        Task { @MainActor in await self.checkForUpdates() }
    }

    private func checkForUpdates() async {
        do {
            if let release = try await updater.checkForUpdate() {
                let alert = NSAlert()
                alert.messageText = "knote \(release.version) is available."
                alert.informativeText = "Install now?"
                alert.addButton(withTitle: "Install")
                alert.addButton(withTitle: "Later")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Task {
                    do {
                        try await self.updater.install(release)
                    } catch {
                        await MainActor.run {
                            let errAlert = NSAlert()
                            errAlert.messageText = "Update failed"
                            errAlert.informativeText = error.localizedDescription
                            errAlert.runModal()
                        }
                    }
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "You're up to date."
                alert.informativeText = "knote \(Updater.currentVersion()) is the latest version."
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not check for updates"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// A minimal main menu with a standard Edit menu. As a menu-bar accessory app
    /// we don't show a menu bar, but the Edit menu's key equivalents (⌘X/⌘C/⌘V/
    /// ⌘A/⌘Z) are still what route cut/copy/paste/select-all to the focused text
    /// field. Without it, ⌘V does nothing (issue #8). The nil-target actions
    /// dispatch to the first responder (the field editor).
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSLog("knote: login item toggle failed: \(error)")
        }
    }
}
