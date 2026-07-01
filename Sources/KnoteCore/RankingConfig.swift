import Foundation

/// Tunables for candidate generation and fusion (ARCHITECTURE.md §9).
public struct RankingConfig: Sendable {
    public var semanticK: Int = 50
    public var lexicalK: Int = 50
    public var rrfK: Double = 60
    public var recencyHalfLifeDays: Double = 30
    public var limit: Int = 8

    public init() {}
}
