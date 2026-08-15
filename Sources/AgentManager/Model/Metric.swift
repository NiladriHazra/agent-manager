import Foundation

/// A reading a row can draw.
///
/// Which of these an agent can actually supply differs enormously — only Codex
/// publishes a quota, only Claude exposes context pressure, only OpenCode and
/// Grok publish a price — so settings offer each agent exactly the ones it can
/// produce rather than a uniform list of mostly-dead switches.
enum Metric: String, CaseIterable, Identifiable {
    case quota
    case windows
    case context
    case chatTokens
    case cost
    case model
    case subAgents
    case branch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quota: return "Quota bar"
        case .windows: return "Daily and weekly tokens"
        case .context: return "Context until compact"
        case .chatTokens: return "Per-chat input and output"
        case .cost: return "Spend"
        case .model: return "Model name"
        case .subAgents: return "Sub-agents"
        case .branch: return "Branch and folder"
        }
    }

    /// What each agent actually writes to disk, verified by reading it.
    static func supported(by agent: AgentID) -> [Metric] {
        switch agent {
        case .codex: return [.quota, .windows, .subAgents, .branch]
        case .claude: return [.windows, .context, .chatTokens, .model, .subAgents, .branch]
        case .opencode: return [.windows, .chatTokens, .cost, .model, .branch]
        case .grok: return [.windows, .cost, .branch]
        case .cursor, .gemini, .antigravity, .hermes: return [.branch]
        }
    }
}
