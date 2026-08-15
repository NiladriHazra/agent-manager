import Foundation

enum AgentID: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case opencode
    case cursor
    case gemini
    case antigravity
    case grok
    case hermes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        case .grok: return "Grok"
        case .hermes: return "Hermes"
        }
    }

    /// Filename of the vendor mark in Resources/Logos.
    var logoName: String {
        switch self {
        case .claude: return "claude-code"
        case .codex: return "codex"
        case .opencode: return "opencode"
        case .cursor: return "cursor"
        case .gemini: return "gemini"
        case .antigravity: return "antigravity"
        case .grok: return "grok"
        case .hermes: return "hermes"
        }
    }

    /// True when the mark is a single flat colour, so it can be re-tinted dark
    /// on a lit chip. Multicolour marks (Gemini) must be left alone.
    var markIsMonochrome: Bool {
        switch self {
        case .gemini: return false
        default: return true
        }
    }

    /// argv[0] basenames that identify a real CLI process for this agent.
    var executableNames: [String] {
        switch self {
        case .claude: return ["claude"]
        case .codex: return ["codex"]
        case .opencode: return ["opencode"]
        case .cursor: return ["cursor-agent"]
        case .gemini: return ["gemini"]
        case .antigravity: return []
        case .grok: return ["grok"]
        case .hermes: return ["hermes"]
        }
    }
}

/// A vendor-reported limit. Only ever built from data the vendor actually
/// wrote to disk, never inferred, so the UI can trust it completely.
struct Quota: Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    var remainingPercent: Double { max(0, 100 - usedPercent) }

    var windowLabel: String {
        switch windowMinutes {
        case 10080: return "weekly"
        case 1440: return "daily"
        case 300: return "5 hours"
        default: return "\(windowMinutes / 60)h window"
        }
    }
}

/// Locally computed consumption. Deliberately separate from `Quota`: this is
/// what the agent spent, not what it has left, and the UI must not conflate them.
struct Usage: Equatable {
    var input = 0
    var output = 0
    var cacheCreate = 0
    var cacheRead = 0
    var cost: Double?

    /// Cache reads run ~100x everything else, so they are excluded from the
    /// headline by default and shown in the breakdown instead.
    func total(includingCacheReads: Bool) -> Int {
        input + output + cacheCreate + (includingCacheReads ? cacheRead : 0)
    }
}

/// Whether an agent is doing anything. A live process is not the same as a
/// working one: a session left open at a prompt stays alive for hours, so
/// activity is judged by how recently its transcript was written.
enum Activity: Equatable {
    case working
    case idle(since: Date?)

    var isWorking: Bool { if case .working = self { return true }; return false }
}

struct RunningSession: Equatable, Identifiable {
    let pid: Int32
    let agent: AgentID
    var activity: Activity = .idle(since: nil)
    /// Taken from `--resume <uuid>` when present. This is an exact map to the
    /// transcript; matching by working directory alone gives every concurrent
    /// session in one repo the same title.
    var sessionID: String?
    var title: String?
    var cwd: String?
    var branch: String?
    var subAgents: [SubAgent] = []

    var id: Int32 { pid }

    /// The short "what is it doing" line. Falls back through progressively
    /// weaker signals rather than showing nothing.
    var activityLine: String {
        if let title, !title.isEmpty { return title.shortenedToWords(5, maxChars: 34) }
        let repo = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unknown"
        if let branch, !branch.isEmpty { return "\(repo) · \(branch)".shortenedToWords(6, maxChars: 34) }
        return repo
    }
}

enum Availability: Equatable {
    case ready
    case loading
    case notInstalled
    case unavailable(String)
}

struct AgentSnapshot: Identifiable, Equatable {
    let agent: AgentID
    var availability: Availability = .loading
    var quota: Quota?
    /// When the quota reading was taken. The vendor only writes it while the
    /// agent is active, so a number can be hours old and must say so.
    var quotaObserved: Date?
    var usage: Usage?
    /// Same measure over the last 24 hours.
    var usageToday: Usage?
    var credits: String?
    var sessions: [RunningSession] = []

    var id: String { agent.rawValue }
    var isRunning: Bool { !sessions.isEmpty }
    var workingSessions: [RunningSession] { sessions.filter { $0.activity.isWorking } }
    var openSessions: [RunningSession] { sessions.filter { !$0.activity.isWorking } }
    var isWorking: Bool { !workingSessions.isEmpty }
}

extension String {
    func shortenedToWords(_ words: Int, maxChars: Int) -> String {
        let parts = split(separator: " ")
        var text = parts.prefix(words).joined(separator: " ")
        if text.count > maxChars {
            text = String(text.prefix(maxChars - 1)).trimmingCharacters(in: .whitespaces) + "…"
        } else if parts.count > words {
            text += "…"
        }
        return text
    }
}
