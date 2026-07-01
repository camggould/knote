import Foundation

/// A semantic version number parsed from strings like "1.2.3", "v1.2.3", or "1.2.3-beta".
///
/// Ordering rules:
/// - Compare major, then minor, then patch numerically.
/// - A version WITH a prerelease sorts BEFORE the same version without one
///   (e.g. `1.2.3-beta < 1.2.3`), following the SemVer 2.0 spec.
/// - If both have prereleases, compare them lexicographically.
public struct SemVer: Comparable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// The prerelease identifier (everything after the first "-"), or nil.
    public let prerelease: String?

    /// Parse a version string. Returns nil if the string is not parseable.
    /// Accepts an optional leading "v" and an optional prerelease suffix.
    public init?(_ string: String) {
        var s = string
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s = String(s.dropFirst())
        }
        // Split off prerelease
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let versionPart = String(parts[0])
        let prereleasePart: String? = parts.count > 1 ? String(parts[1]) : nil

        let nums = versionPart.split(separator: ".", omittingEmptySubsequences: false)
        guard nums.count == 3,
              let maj = Int(nums[0]),
              let min = Int(nums[1]),
              let pat = Int(nums[2]) else { return nil }

        self.major = maj
        self.minor = min
        self.patch = pat
        self.prerelease = prereleasePart?.isEmpty == true ? nil : prereleasePart
    }

    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // Same major.minor.patch — prerelease ordering.
        // A version with a prerelease < same version without one.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):       return false
        case (nil, _):         return false  // no-prerelease > prerelease
        case (_, nil):         return true   // prerelease < no-prerelease
        case let (l?, r?):     return l < r  // both have prereleases: lexicographic
        }
    }

    /// True if this version carries a prerelease identifier (e.g. `-beta`).
    public var isPrerelease: Bool { prerelease != nil }

    /// Returns true iff both strings parse as valid SemVer versions and
    /// `candidate` is strictly newer than `current`.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let c = SemVer(candidate), let cur = SemVer(current) else { return false }
        return c > cur
    }

    /// From `versions`, pick the highest one that is strictly newer than
    /// `current`. When `allowPrerelease` is false, prerelease versions are
    /// excluded. Unparseable strings are ignored. Returns the original string
    /// of the winner, or nil if none qualify.
    public static func pickNewest(from versions: [String],
                                  allowPrerelease: Bool,
                                  newerThan current: String) -> String? {
        let candidates = versions.compactMap { raw -> (raw: String, ver: SemVer)? in
            guard let ver = SemVer(raw) else { return nil }
            if !allowPrerelease && ver.isPrerelease { return nil }
            return (raw, ver)
        }
        let eligible: [(raw: String, ver: SemVer)]
        if let cur = SemVer(current) {
            eligible = candidates.filter { $0.ver > cur }
        } else {
            eligible = candidates  // unparseable current → any candidate is "newer"
        }
        return eligible.max { $0.ver < $1.ver }?.raw
    }
}
