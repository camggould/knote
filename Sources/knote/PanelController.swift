import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Borderless floating panel that can become key so its text field accepts input.
final class KnotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the Spotlight-style panel: builds it lazily, shows/hides it over any
/// Space, routes keyboard events through the AppState state machine, and resizes
/// to fit content (ARCHITECTURE.md §3, §8).
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var panel: KnotePanel?
    private var keyMonitor: Any?
    private let width: CGFloat = 640

    init(appState: AppState) {
        self.appState = appState
        super.init()
        appState.onContentChange = { [weak self] in self?.resizeToFit() }
        appState.onRequestHide = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let panel = ensurePanel()
        appState.activate()
        position(panel)
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        resizeToFit()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Building

    private func ensurePanel() -> KnotePanel {
        if let panel { return panel }
        // Plain borderless panel (NOT .nonactivatingPanel): we *want* it to
        // become key so the text field receives input. canBecomeKey is
        // overridden on KnotePanel; NSApp.activate brings the accessory app
        // forward on show.
        let p = KnotePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        p.level = .modalPanel
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: RootView(state: appState))
        panel = p
        return p
    }

    // MARK: - Layout

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.minY + vf.height * 0.62 - size.height / 2 // upper third, launcher-style
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Deterministic height from current state (avoids fitting-size timing races).
    private func resizeToFit() {
        guard let panel else { return }
        let header: CGFloat = 60
        let status: CGFloat = appState.statusMessage == nil ? 0 : 30
        let body: CGFloat
        if appState.mode == .compose {
            body = 44
        } else if appState.results.isEmpty {
            body = 46
        } else {
            body = CGFloat(min(appState.results.count, 8)) * 58 + 8
        }
        let height = min(560, header + status + body)
        let old = panel.frame
        let newFrame = NSRect(x: old.minX, y: old.maxY - height, width: width, height: height)
        panel.setFrame(newFrame, display: true)
    }

    // MARK: - Keyboard routing (state machine, §8)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Return nil to consume the event, or the event to let the text field see it.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let cmd = event.modifierFlags.contains(.command)

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            appState.moveDown(); return nil
        case kVK_UpArrow:
            appState.moveUp(); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if appState.submit() { hide() }
            return nil
        case kVK_Delete:
            if cmd || appState.phase == .navigating { appState.requestDelete(); return nil }
            if appState.phase == .confirmingDelete { return nil }
            return event // editing → let the field delete text
        case kVK_Escape:
            if appState.handleEscape() { hide() }
            return nil
        default:
            // Printable key while navigating: drop back to editing, pass through.
            if appState.phase != .editing, !cmd, let s = event.characters, !s.isEmpty {
                appState.returnToEditing()
            }
            return event
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hide() // click-away dismiss
    }
}
