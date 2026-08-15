import Foundation

/// Whether a live session has handed the turn back to you.
///
/// This is the difference between an agent that stopped because it finished and
/// one that stopped because nobody has run it in an hour, and it is readable
/// from disk: both Codex and Claude write an explicit end-of-turn record.
///
/// Approval prompts themselves are never written to a transcript (checked: a
/// Codex rollout logs no event when it asks to run a command), so this reports
/// what is actually recorded rather than guessing at a modal on screen.
enum TurnState {
    case awaitingUser
    case busy

    static func read(transcript: URL, agent: AgentID) -> TurnState {
        switch agent {
        case .codex: return codex(transcript)
        case .claude: return claude(transcript)
        default: return .busy
        }
    }

    /// Codex closes a turn with a `task_complete` event. Anything logged after
    /// it means a new turn already started.
    private static func codex(_ url: URL) -> TurnState {
        for line in TailReader.lines(of: url, bytes: 256 * 1024) {
            if line.contains("\"task_complete\"") { return .awaitingUser }
            if line.contains("\"function_call\"") || line.contains("\"custom_tool_call\"") { return .busy }
        }
        return .busy
    }

    /// Claude ends a turn with an assistant message whose `stop_reason` is
    /// `end_turn`; a turn still in flight ends on `tool_use` instead.
    private static func claude(_ url: URL) -> TurnState {
        for line in TailReader.lines(of: url, bytes: 256 * 1024) {
            guard line.contains("\"stop_reason\"") else { continue }
            if line.contains("\"end_turn\"") { return .awaitingUser }
            if line.contains("\"tool_use\"") { return .busy }
        }
        return .busy
    }
}
