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
    /// Only agents that publish a price do this: OpenCode and Grok.
    var cost: Double?

    /// Resolved from the largest context ever observed for this model, which
    /// the index tracks across every session. Nothing can exceed its own
    /// window, so one session that reached 397K proves the whole model is on
    /// the 1M tier — including sessions currently sitting at 115K.
    var windowTokens: Int?

    /// The transcript records a model family but never the context tier, so
    /// this is the only signal available. Falling back to a per-session guess
    /// made the figure flip between 96% and 61% as different sessions became
    /// the fullest, which is why the tier is resolved per model instead.
    var contextWindow: Int {
        windowTokens ?? (contextTokens > 200_000 ? 1_000_000 : 200_000)
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
            .replacingOccurrences(of: "-preview", with: "")
    }
}
