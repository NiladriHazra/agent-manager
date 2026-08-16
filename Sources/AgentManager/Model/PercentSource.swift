import Foundation

/// What an agent's menu bar percentage measures.
///
/// These are not interchangeable. A vendor quota is the agent's own published
/// number; a budget percentage is measured against a figure you set, because
/// no limit exists on disk to measure against; context is a live reading of one
/// session. The menu bar shows one number, so it has to be said which it is.
enum PercentSource: String, CaseIterable, Identifiable {
    case quota
    case weeklyBudget
    case dailyBudget
    case context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quota: return "Vendor quota"
        case .weeklyBudget: return "Weekly budget"
        case .dailyBudget: return "Daily budget"
        case .context: return "Live context"
        }
    }

    var needsBudget: Bool { self == .weeklyBudget || self == .dailyBudget }

    /// Only offer what the agent can actually produce.
    static func available(for agent: AgentID) -> [PercentSource] {
        let metrics = Metric.supported(by: agent)
        var sources: [PercentSource] = []
        if metrics.contains(.quota) { sources.append(.quota) }
        if metrics.contains(.windows) { sources += [.weeklyBudget, .dailyBudget] }
        if metrics.contains(.context) { sources.append(.context) }
        return sources
    }
}
