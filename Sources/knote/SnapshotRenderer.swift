import AppKit
import SwiftUI
import KnoteCore
import KnoteEmbeddings
import KnoteVector

/// Renders the UI to PNGs offscreen (via `ImageRenderer`) for visual review and
/// snapshot testing — no screen-recording permission needed. Invoke with
/// `knote --snapshot <outputDir>`.
@MainActor
enum SnapshotRenderer {
    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = makeSampleState()

        // Scenario 1: recents (empty query).
        state.query = ""
        state.results = state.recentsForSnapshot()
        state.phase = .editing
        state.selection = nil
        render(state, to: dir.appendingPathComponent("01-recents.png"))

        // Scenario 2: search results.
        state.query = "budget planning"
        state.results = state.searchForSnapshot("budget planning")
        state.phase = .editing
        state.selection = nil
        render(state, to: dir.appendingPathComponent("02-search.png"))

        // Scenario 3: navigating + confirm-delete on the selected row.
        state.selection = 1
        state.phase = .confirmingDelete
        render(state, to: dir.appendingPathComponent("03-confirm-delete.png"))

        // Scenario 4: compose mode.
        state.query = "/n Draft the launch post — emphasize local-first + privacy"
        state.results = []
        state.phase = .editing
        state.selection = nil
        state.statusMessage = nil
        render(state, to: dir.appendingPathComponent("04-compose.png"))

        FileHandle.standardError.write(Data("snapshots written to \(dir.path)\n".utf8))
    }

    private static func makeSampleState() -> AppState {
        // In-memory store + lexical encoder (deterministic, no model load).
        let store = try! NoteStore(inMemory: true)
        let samples = [
            "Quarterly budget meeting — cut cloud spend, revisit headcount in Q3",
            "Budget planning notes for next year: infra, tooling, offsite",
            "Groceries: oat milk, sourdough, spinach, coffee beans",
            "Book from Sam: The Design of Everyday Things",
            "Fix the flaky login test before the release cut",
        ]
        for body in samples { _ = try? store.create(body: body) }

        let encoder = LexicalOnlyEncoder()
        let index = InMemoryVectorIndex()
        let indexer = Indexer(store: store, encoder: encoder, index: index)
        let search = SearchService(store: store, encoder: encoder, index: index)
        return AppState(store: store, search: search, indexer: indexer)
    }

    private static func render(_ state: AppState, to url: URL) {
        let content = ZStack {
            Color(nsColor: .windowBackgroundColor)
            RootView(state: state).padding(24)
        }
        .frame(width: 688)
        .fixedSize(horizontal: false, vertical: true)

        // Real AppKit rasterization (cacheDisplay) renders the live TextField and
        // ScrollView faithfully, unlike ImageRenderer. Host in an offscreen window
        // so materials/effects composite correctly.
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 688, height: 10)
        let height = max(120, hosting.fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: 688, height: height)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            FileHandle.standardError.write(Data("failed to render \(url.lastPathComponent)\n".utf8))
            return
        }
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
