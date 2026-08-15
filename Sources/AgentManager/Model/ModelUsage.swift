import Foundation

/// One model's share of an agent's usage.
///
/// An agent is not one thing: a week of Claude may be mostly Opus with a little
/// Fable, and a single combined figure hides which one actually cost you the
/// window. Ordered by last use, so the model you are on right now leads.
struct ModelUsage: Equatable, Identifiable {
    let model: String
    let day: Usage
    let week: Usage
    let lastUsed: Date

    var id: String { model }

    /// `claude-opus-5` reads as `opus-5`; provider prefixes carry no meaning
    /// once the row already shows whose agent it is.
    var label: String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gpt-", with: "")
            .replacingOccurrences(of: "-preview", with: "")
    }
}
