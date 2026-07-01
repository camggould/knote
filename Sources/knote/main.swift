import AppKit

// Accessory app: no dock icon, lives in the menu bar (ARCHITECTURE.md §3).
// Top-level executable code runs on the main thread, so assuming main-actor
// isolation here is safe and lets us touch @MainActor types.
MainActor.assumeIsolated {
    // Offscreen snapshot mode: `knote --snapshot <dir>` renders UI states to PNGs.
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot") {
        let dir = i + 1 < args.count ? args[i + 1] : "snapshots"
        SnapshotRenderer.run(outputDir: dir)
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
