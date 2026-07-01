import SwiftUI
import KnoteCore

/// The panel's contents: a query/compose field on top, results below, an inline
/// delete confirmation, and a status line.
struct RootView: View {
    @ObservedObject var state: AppState
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state.mode == .compose {
                composeHint
            } else {
                results
            }
            if let status = state.statusMessage {
                statusLine(status)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(width: 640)
        .onAppear { fieldFocused = true }
        .onChange(of: state.focusTick) { fieldFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.mode == .compose ? "square.and.pencil" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            if let spaceName = state.currentSpaceName {
                spaceChip(spaceName)
            }
            TextField(text: $state.query, prompt: Text("Search notes, or type /n to add one")) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .regular))
            .focused($fieldFocused)
            .onChange(of: state.query) { state.queryChanged() }
            if let suggestion = state.spaceSuggestion {
                Text("⇥ \(suggestion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }

    private func spaceChip(_ name: String) -> some View {
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.2))
            )
            .foregroundStyle(Color.accentColor)
    }

    private var composeHint: some View {
        HStack {
            Text(state.composeBody.isEmpty ? "Type your note…" : "Press ↩ to save")
                .foregroundStyle(.secondary)
            Spacer()
            if !state.composeBody.isEmpty {
                Text("↩ save").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .overlay(Divider(), alignment: .top)
    }

    @ViewBuilder
    private var results: some View {
        if state.results.isEmpty {
            HStack {
                Text(state.query.isEmpty ? "No notes yet — type /n to add one" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 46)
            .overlay(Divider(), alignment: .top)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(state.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(
                            result: result,
                            selected: state.selection == index,
                            confirming: state.selection == index && state.phase == .confirmingDelete
                        )
                    }
                }
            }
            .frame(maxHeight: 8 * 58)
            .overlay(Divider(), alignment: .top)
        }
    }

    private func statusLine(_ text: String) -> some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .overlay(Divider(), alignment: .top)
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let confirming: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.note.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if confirming {
                    Text("Delete this note?  ↩ confirm · esc cancel")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !result.tags.isEmpty {
                        tagsRow
                    }
                }
            }
            Spacer()
            Text(Self.relative(result.note.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: confirming || result.tags.isEmpty ? 58 : 74)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(confirming ? Color.red.opacity(0.15)
                      : selected ? Color.accentColor.opacity(0.20) : Color.clear)
                .padding(.horizontal, 6)
        )
    }

    private var snippet: String {
        let body = result.note.body.replacingOccurrences(of: "\n", with: " ")
        return String(body.prefix(120))
    }

    private var tagsRow: some View {
        HStack(spacing: 6) {
            ForEach(result.tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }
            Spacer()
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relative(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
