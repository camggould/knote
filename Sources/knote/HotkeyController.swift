import AppKit

/// Owns global-hotkey registration and lets it be rebound at runtime. Persists
/// the choice and reverts if a new combo can't be registered (e.g. already taken).
@MainActor
final class HotkeyController: ObservableObject {
    @Published private(set) var hotkey: Hotkey
    @Published var errorMessage: String?

    private var globalHotKey: GlobalHotKey?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        self.hotkey = Hotkey.load() ?? .default
        register(hotkey)
    }

    @discardableResult
    private func register(_ hk: Hotkey) -> Bool {
        globalHotKey = nil // releases + unregisters any previous binding
        globalHotKey = GlobalHotKey(
            keyCode: hk.keyCode, modifiers: hk.carbonModifiers, callback: onTrigger)
        return globalHotKey != nil
    }

    /// Rebind to `new`, reverting to the current binding if registration fails.
    func update(to new: Hotkey) {
        guard new != hotkey else { return }
        let previous = hotkey
        if register(new) {
            hotkey = new
            hotkey.save()
            errorMessage = nil
        } else {
            _ = register(previous) // restore the working binding
            errorMessage = "\(new.label) is unavailable — it may be used by another app. Kept \(previous.label)."
        }
    }

    func resetToDefault() { update(to: .default) }

    /// Temporarily unregister the global hotkey (used while recording a new one,
    /// so pressing the current shortcut doesn't fire it).
    func suspend() { globalHotKey = nil }

    /// Re-register the current hotkey after `suspend()`.
    func resume() { register(hotkey) }
}
