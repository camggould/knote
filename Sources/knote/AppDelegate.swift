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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
