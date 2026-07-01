import Foundation
import Combine
import AppKit
import KnoteCore

/// Keyboard interaction phases (ARCHITECTURE.md §8).
enum Phase {
    case editing          // caret in the field; typing filters/searches
    case navigating       // a result is selected via arrow keys
    case confirmingDelete // inline "Delete? ↩ / esc" on the selected row
}

enum Mode { case search, compose }

/// Observable UI state + the query→results→delete state machine. All mutation
/// happens on the main actor; heavy search runs off-main.
@MainActor
final class AppState: ObservableObject {
    @Published var query = "" { didSet { onContentChange?() } }
    @Published var results: [SearchResult] = [] { didSet { onContentChange?() } }
    @Published var selection: Int? = nil
    @Published var phase: Phase = .editing { didSet { onContentChange?() } }
    @Published var statusMessage: String? = nil { didSet { onContentChange?() } }
    /// Non-nil when Tab can complete the space-name token being typed.
    @Published var spaceSuggestion: String? = nil
    /// Bumped on each panel show so the view can re-focus the field.
    @Published var focusTick = 0

    /// PanelController hooks these to resize/dismiss.
    var onContentChange: (() -> Void)?
    var onRequestHide: (() -> Void)?

    private let store: NoteStore
    private let search: SearchService
    private let indexer: Indexer
    private var searchTask: Task<Void, Never>?

    init(store: NoteStore, search: SearchService, indexer: Indexer) {
        self.store = store
        self.search = search
        self.indexer = indexer
    }

    // MARK: - Command / mode

    var currentCommand: Command { CommandParser.parse(query) }

    var mode: Mode {
        switch currentCommand {
        case .compose:
            return .compose
        case .composeInSpace(let space, _):
            return space.isEmpty ? .search : .compose
        default:
            return .search
        }
    }

    /// The body text to save (works for both /n and /ns).
    var composeBody: String {
        switch currentCommand {
        case .compose(let body): return body
        case .composeInSpace(_, let body): return body
        default: return ""
        }
    }

    /// The active space name when in a scoped mode, nil otherwise.
    var currentSpaceName: String? {
        switch currentCommand {
        case .composeInSpace(let space, _): return space.isEmpty ? nil : space
        case .searchInSpace(let space, _): return space.isEmpty ? nil : space
        default: return nil
        }
    }

    // MARK: - Lifecycle from the panel

    /// Reset to a clean editing state and show recents. Called on each show.
    func activate() {
        query = ""
        statusMessage = nil
        phase = .editing
        selection = nil
        spaceSuggestion = nil
        results = search.recents()
        focusTick += 1
    }

    func queryChanged() {
        // NOTE: do not touch `phase`/`selection` here. This runs via SwiftUI's
        // `.onChange(of: query)`, which is delivered asynchronously on a later
        // run-loop tick — so it can land *after* a synchronous arrow-key press
        // and clobber `.navigating` back to `.editing`, which would misroute the
        // next Backspace to text editing instead of delete. Transitions into
        // editing are made synchronously in the key monitor (see returnToEditing).
        statusMessage = nil
        searchTask?.cancel()
        updateSpaceSuggestion()

        switch currentCommand {
        case .compose, .createSpace, .composeInSpace:
            results = []

        case .search(let q):
            let svc = search
            searchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                let r = await Task.detached { svc.search(q) }.value
                if Task.isCancelled { return }
                self?.results = r
            }

        case .searchInSpace(let spaceName, let q):
            let svc = search
            let storeRef = store
            searchTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                let r = await Task.detached {
                    guard let spaceID = (try? storeRef.space(named: spaceName))?.id else {
                        return [SearchResult]()
                    }
                    return svc.search(q, spaceID: spaceID)
                }.value
                if Task.isCancelled { return }
                self?.results = r
            }
        }
    }

    // MARK: - Space autocomplete

    private func updateSpaceSuggestion() {
        guard let partial = CommandParser.spacePrefixBeingTyped(query) else {
            spaceSuggestion = nil
            return
        }
        let matches = (try? store.spacesMatching(prefix: partial)) ?? []
        if let first = matches.first, first.name.lowercased() != partial.lowercased() {
            spaceSuggestion = first.name
        } else {
            spaceSuggestion = nil
        }
    }

    /// Accept the current Tab suggestion: rewrites the query so the partial space
    /// token becomes the full suggested name followed by a space.
    func acceptSpaceSuggestion() {
        guard let suggestion = spaceSuggestion else { return }
        let lower = query.lowercased()
        if lower.hasPrefix("/ns ") {
            query = "/ns \(suggestion) "
        } else if lower.hasPrefix("/ss ") {
            query = "/ss \(suggestion) "
        }
        // spaceSuggestion will be cleared by the queryChanged() that fires on query change
    }

    // MARK: - Navigation

    func moveDown() {
        if phase == .confirmingDelete { phase = .navigating }
        guard !results.isEmpty else { return }
        switch selection {
        case nil: selection = 0
        case let i?: selection = min(i + 1, results.count - 1)
        }
        phase = .navigating
    }

    func moveUp() {
        if phase == .confirmingDelete { phase = .navigating }
        guard let i = selection else { return }
        if i == 0 { selection = nil; phase = .editing }
        else { selection = i - 1 }
    }

    // MARK: - Actions

    /// Returns true if the panel should hide afterward.
    func submit() -> Bool {
        if phase == .confirmingDelete { confirmDelete(); return false }

        switch currentCommand {
        case .compose:
            saveNote()
            return false

        case .createSpace(let name):
            guard !name.isEmpty else { return false }
            if let space = try? store.createSpace(name: name) {
                statusMessage = "Space \"\(space.name)\" created"
                query = ""
                selection = nil
                phase = .editing
                results = search.recents()
                focusTick += 1
            }
            return false

        case .composeInSpace(let spaceName, let body):
            guard !body.isEmpty else { return false }
            saveNoteInSpace(spaceName: spaceName, body: body)
            return false

        case .search, .searchInSpace:
            let idx = selection ?? (results.isEmpty ? nil : 0)
            guard let i = idx, results.indices.contains(i) else { return false }
            open(results[i])
            return true
        }
    }

    private func saveNote() {
        let body = composeBody
        guard !body.isEmpty else { return }
        if let note = try? store.create(body: body) {
            indexer.indexNote(note)
            query = ""
            selection = nil
            phase = .editing
            statusMessage = "Saved \"\(note.title)\""
            results = search.recents()
            focusTick += 1
        }
    }

    private func saveNoteInSpace(spaceName: String, body: String) {
        guard !body.isEmpty else { return }
        guard let note = try? store.create(body: body) else { return }
        indexer.indexNote(note)
        // createSpace is idempotent — returns existing space if name already taken.
        if let space = try? store.createSpace(name: spaceName) {
            try? store.setSpace(noteID: note.id, spaceID: space.id)
        }
        query = ""
        selection = nil
        phase = .editing
        statusMessage = "Saved to \"\(spaceName)\""
        results = search.recents()
        focusTick += 1
    }

    /// v1 open action: copy the note to the clipboard (a genuinely useful quick
    /// action for a notes launcher). Editing-in-place is future work.
    private func open(_ result: SearchResult) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(result.note.body, forType: .string)
    }

    func requestDelete() {
        guard selection != nil else { return }
        phase = .confirmingDelete
    }

    func cancelConfirm() {
        if phase == .confirmingDelete { phase = .navigating }
    }

    func confirmDelete() {
        guard let i = selection, results.indices.contains(i) else { return }
        let note = results[i].note
        try? store.delete(id: note.id)
        indexer.removeNote(id: note.id)
        results.remove(at: i)
        statusMessage = "Deleted \"\(note.title)\""
        if results.isEmpty {
            selection = nil; phase = .editing
        } else {
            selection = min(i, results.count - 1); phase = .navigating
        }
    }

    /// Handle Esc. Returns true if the panel should hide.
    func handleEscape() -> Bool {
        switch phase {
        case .confirmingDelete:
            phase = .navigating; return false
        case .navigating:
            phase = .editing; selection = nil; return false
        case .editing:
            if query.isEmpty { return true }
            query = ""; queryChanged(); return false
        }
    }

    /// A printable key was pressed while navigating: fall back to editing so the
    /// keystroke reaches the text field.
    func returnToEditing() {
        if phase != .editing { phase = .editing; selection = nil }
    }

    // MARK: - Snapshot support (used by SnapshotRenderer for offscreen rendering)

    func recentsForSnapshot() -> [SearchResult] { search.recents() }
    func searchForSnapshot(_ query: String) -> [SearchResult] { search.search(query) }
    func scopedSearchForSnapshot(space: String, _ query: String) -> [SearchResult] {
        guard let id = (try? store.space(named: space))?.id else { return [] }
        return search.search(query, spaceID: id)
    }
}
