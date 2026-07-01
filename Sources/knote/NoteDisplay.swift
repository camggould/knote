import Foundation

/// Presentation helpers for note titles. A note whose title is a URL renders as
/// its domain (e.g. `github.com`) instead of the full link, and any title is
/// truncated so it never crams the UI.
enum NoteDisplay {
    /// A compact, display-friendly title: domain for URLs, else the raw title,
    /// truncated to `maxLength` with an ellipsis.
    static func title(_ raw: String, maxLength: Int = 56) -> String {
        truncate(host(of: raw) ?? raw, maxLength)
    }

    /// The host of an http(s) URL with a leading `www.` stripped, or nil if the
    /// string isn't a web URL.
    static func host(of string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func truncate(_ s: String, _ maxLength: Int) -> String {
        guard s.count > maxLength else { return s }
        return String(s.prefix(max(1, maxLength - 1))) + "\u{2026}"
    }
}
