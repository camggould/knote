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

    // MARK: - Mode / compose parsing

    var mode: Mode { isCompose ? .compose : .search }

    var isCompose: Bool {
        let q = query.lowercased()
        return q == "/n" || q.hasPrefix("/n ") || q.hasPrefix("/n\n")
    }

    var composeBody: String {
        guard isCompose else { return "" }
        var b = String(query.dropFirst(2))
        if b.hasPrefix(" ") || b.hasPrefix("\n") { b.removeFirst() }
        return b.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Lifecycle from the panel

    /// Reset to a clean editing state and show recents. Called on each show.
    func activate() {
        query = ""
        statusMessage = nil
        phase = .editing
        selection = nil
        results = search.recents()
        focusTick += 1
    }

    func queryChanged() {
        statusMessage = nil
        selection = nil
        phase = .editing
        searchTask?.cancel()

        if isCompose { results = []; return }

        let q = query
        let svc = search
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            if Task.isCancelled { return }
            let r = await Task.detached { svc.search(q) }.value
            if Task.isCancelled { return }
            self?.results = r
        }
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

        if mode == .compose {
            saveNote()
            return false
        }
        // search: open the selected (or top) result
        let idx = selection ?? (results.isEmpty ? nil : 0)
        guard let i = idx, results.indices.contains(i) else { return false }
        open(results[i])
        return true
    }

    private func saveNote() {
        let body = composeBody
        guard !body.isEmpty else { return }
        if let note = try? store.create(body: body) {
            indexer.indexNote(note)
            query = ""
            selection = nil
            phase = .editing
            statusMessage = "Saved “\(note.title)”"
            results = search.recents()
            focusTick += 1
        }
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
        statusMessage = "Deleted “\(note.title)”"
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
}
