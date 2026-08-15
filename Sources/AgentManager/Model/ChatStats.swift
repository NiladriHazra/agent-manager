import Foundation

/// What one chat has spent, and how full its context is.
///
/// Accumulated by the index as it already walks each transcript, so nothing is
/// re-read to produce it.
struct ChatStats: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheCreate = 0
    var cacheRead = 0
    /// Tokens the model held on the most recent turn. A compaction shows up
    /// here as a sudden drop.
    var contextTokens = 0
    var model: String?
    var turns = 0
    var thinking = 0

    /// The transcript records a model family but not which context tier the
    /// session was opened with, so the tier is inferred from what the context
    /// has actually reached: nothing can exceed its own window.
    var contextWindow: Int {
        contextTokens > 200_000 ? 1_000_000 : 200_000
    }

    var contextFraction: Double {
        min(Double(contextTokens) / Double(contextWindow), 1)
    }

    /// Short model name for display: `claude-opus-5` reads as `opus-5`.
    var modelLabel: String? {
        guard let model else { return nil }
        return model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20", with: " ")
    }
}
