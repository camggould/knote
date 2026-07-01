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
        state.query = "/n Draft the launch post — emphasize local-first + privacy #work"
        state.results = []
        state.phase = .editing
        state.selection = nil
        state.statusMessage = nil
        render(state, to: dir.appendingPathComponent("04-compose.png"))

        // Scenario 5: tag search (#work) — chips visible.
        state.query = "#work"
        state.results = state.searchForSnapshot("#work")
        state.phase = .editing
        state.selection = nil
        state.spaceSuggestion = nil
        render(state, to: dir.appendingPathComponent("05-tag-search.png"))

        // Scenario 6: space autocomplete (typing "/ns Wo" → ⇥ Work).
        state.query = "/ns Wo"
        state.results = []
        state.spaceSuggestion = "Work"
        state.phase = .editing
        state.selection = nil
        render(state, to: dir.appendingPathComponent("06-space-autocomplete.png"))

        // Scenario 7: scoped search within the Work space.
        state.query = "/ss Work budget"
        state.results = state.scopedSearchForSnapshot(space: "Work", "budget")
        state.spaceSuggestion = nil
        state.phase = .editing
        state.selection = nil
        render(state, to: dir.appendingPathComponent("07-space-scoped-search.png"))

        // Scenario 8: linking mode (picking the answer for a selected note).
        state.query = ""
        state.phase = .linking
        state.linkSourceID = "src"
        state.linkSourceTitle = "Quarterly budget meeting — cut cloud spend, revisit headcount in Q3"
        state.results = state.recentsForSnapshot()
        state.selection = 0
        render(state, to: dir.appendingPathComponent("08-linking.png"))
        state.linkSourceID = nil
        state.linkSourceTitle = nil

        // Scenario 9: the Settings window (shortcut + MCP integration section).
        let hotkeys = HotkeyController(onTrigger: {})
        rasterize(SettingsView(hotkeys: hotkeys, encoderName: "Apple NLEmbedding"),
                  width: 488, to: dir.appendingPathComponent("09-settings.png"))

        FileHandle.standardError.write(Data("snapshots written to \(dir.path)\n".utf8))
    }

    private static func makeSampleState() -> AppState {
        // In-memory store + lexical encoder (deterministic, no model load).
        let store = try! NoteStore(inMemory: true)
        let samples = [
            "Quarterly budget meeting — cut cloud spend, revisit headcount in Q3 #work #finance",
            "Budget planning notes for next year: infra, tooling, offsite #work",
            "Groceries: oat milk, sourdough, spinach, coffee beans #home",
            "Book from Sam: The Design of Everyday Things #reading",
            "Fix the flaky login test before the release cut #work #bug",
            "https://github.com/camggould/knote/releases/tag/v0.1.0 #reading",
        ]
        var created: [Note] = []
        for body in samples { if let n = try? store.create(body: body) { created.append(n) } }
        // A "Work" space with the two work-related notes, for space snapshots.
        if let work = try? store.createSpace(name: "Work") {
            for n in created.prefix(2) { try? store.setSpace(noteID: n.id, spaceID: work.id) }
        }
        // Link two notes so link indicators appear (answer answers question).
        if created.count >= 2 {
            try? store.link(from: created[1].id, to: created[0].id, kind: .answers)
        }

        let encoder = LexicalOnlyEncoder()
        let index = InMemoryVectorIndex()
        let indexer = Indexer(store: store, encoder: encoder, index: index)
        let search = SearchService(store: store, encoder: encoder, index: index)
        return AppState(store: store, search: search, indexer: indexer)
    }

    private static func render(_ state: AppState, to url: URL) {
        rasterize(RootView(state: state), width: 688, to: url)
    }

    /// Real AppKit rasterization (cacheDisplay) renders live TextField/ScrollView
    /// faithfully, unlike ImageRenderer. Host in an offscreen window so
    /// materials/effects composite correctly.
    private static func rasterize<V: View>(_ view: V, width: CGFloat, to url: URL) {
        let content = ZStack {
            Color(nsColor: .windowBackgroundColor)
            view.padding(24)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let height = max(120, hosting.fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

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
