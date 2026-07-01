import AppKit

// Accessory app: no dock icon, lives in the menu bar (ARCHITECTURE.md §3).
// Top-level executable code runs on the main thread, so assuming main-actor
// isolation here is safe and lets us touch @MainActor types.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
