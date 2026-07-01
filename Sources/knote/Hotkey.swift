import AppKit
import Carbon.HIToolbox

/// A global shortcut: a virtual key code plus a Carbon modifier mask, with a
/// human-readable label (e.g. "⌥Space"). Persisted in UserDefaults.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String

    static let `default` = Hotkey(
        keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey), label: "⌥Space")

    // MARK: - Build from a recorded event

    /// Returns nil if the combo isn't a usable global shortcut (a bare key with
    /// no Cmd/Opt/Ctrl and not a function key).
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        let hasHardModifier = flags.contains(.command) || flags.contains(.option)
            || flags.contains(.control)
        let isFunctionKey = Hotkey.functionKeys.contains(Int(event.keyCode))
        guard hasHardModifier || isFunctionKey else { return nil }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = Hotkey.carbonModifiers(from: flags)
        label = Hotkey.label(keyCode: Int(event.keyCode), flags: flags, event: event)
    }

    private init(keyCode: UInt32, carbonModifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.label = label
    }

    // MARK: - Persistence

    private static let defaultsKey = "knote.hotkey"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Hotkey.defaultsKey)
        }
    }

    static func load() -> Hotkey? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Hotkey.self, from: data)
    }

    // MARK: - Conversions & display

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func label(keyCode: Int, flags: NSEvent.ModifierFlags, event: NSEvent?) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyName(keyCode, event: event)
        return s
    }

    private static func keyName(_ code: Int, event: NSEvent?) -> String {
        if let name = specialKeys[code] { return name }
        if let chars = event?.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key\(code)"
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]
}
