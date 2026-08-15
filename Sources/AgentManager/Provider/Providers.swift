import Foundation

protocol AgentProvider {
    var agent: AgentID { get }
    func probe(sessions: [RunningSession]) async -> AgentSnapshot
}

private let home = FileManager.default.homeDirectoryForCurrentUser

/// The one provider list. Diagnostics used to keep its own copy, which meant a
/// provider could be wired into the app and still report nothing when checked.
func allProviders(index: UsageIndex) -> [AgentProvider] {
    [
        CodexProvider(),
        ClaudeProvider(index: index),
        OpenCodeProvider(),
        GrokProvider(),
        PresenceProvider(agent: .cursor, installedPaths: [
            home.appendingPathComponent(".cursor").path,
            "/Applications/Cursor.app",
        ]),
        PresenceProvider(agent: .gemini, installedPaths: [
            home.appendingPathComponent(".gemini").path,
        ]),
        PresenceProvider(agent: .antigravity, installedPaths: [
            home.appendingPathComponent("Library/Application Support/Antigravity").path,
        ]),
        PresenceProvider(agent: .hermes, installedPaths: [
            home.appendingPathComponent(".hermes").path,
        ]),
    ]
}

/// A transcript written within this window means the agent is mid-task. Chosen
/// from measurement: an active session writes every few seconds, while sessions
/// parked at a prompt sat untouched for 17 to 58 minutes.
let workingWindow: TimeInterval = 180

func activity(lastWrite: Date?) -> Activity {
    guard let lastWrite else { return .idle(since: nil) }
    return Date().timeIntervalSince(lastWrite) <= workingWindow ? .working : .idle(since: lastWrite)
}

/// Activity refined by what the transcript's last record actually says.
///
/// A session that wrote recently is not necessarily busy: finishing a turn is
/// also a write. Only the transcript distinguishes the two.
func activity(lastWrite: Date?, transcript: URL?, agent: AgentID) -> Activity {
    guard let transcript,
          TurnState.read(transcript: transcript, agent: agent) == .awaitingUser
    else { return activity(lastWrite: lastWrite) }
    // An ended turn is an ended turn whether it closed ten seconds or an hour
    // ago: either way the next move is yours.
    return .waiting(since: lastWrite)
}

// MARK: - Codex

/// The only agent that writes its real limit to disk. Each session logs
/// `token_count` events carrying `rate_limits.primary`, so the newest record in
/// the newest session is the live quota. Session files reach 295 MB, so this
/// only ever tail-reads.
struct CodexProvider: AgentProvider {
    let agent = AgentID.codex
    private let root = home.appendingPathComponent(".codex/sessions")

    private struct Envelope: Decodable {
        struct Payload: Decodable {
            struct RateLimits: Decodable {
                struct Primary: Decodable {
                    let used_percent: Double
                    let window_minutes: Int
                    let resets_at: Double
                }
                struct Credits: Decodable {
                    let balance: String?
                    let unlimited: Bool?
                }
                let primary: Primary?
                let credits: Credits?
            }
            let rate_limits: RateLimits?
        }
        let payload: Payload?
    }

    func probe(sessions: [RunningSession]) async -> AgentSnapshot {
        var snapshot = AgentSnapshot(agent: agent, sessions: sessions)
        guard FileManager.default.fileExists(atPath: root.path) else {
            snapshot.availability = .notInstalled
            return snapshot
        }

        guard let newest = newestSessionFile() else {
            snapshot.availability = .unavailable("no sessions yet")
            return snapshot
        }

        let decoder = JSONDecoder()
        let found = TailReader.newestLine(in: newest, containing: "\"rate_limits\"") { data -> Envelope.Payload.RateLimits? in
            (try? decoder.decode(Envelope.self, from: data))?.payload?.rate_limits
        }

        guard let limits = found, let primary = limits.primary else {
            snapshot.availability = .unavailable("no quota record")
            return snapshot
        }

        snapshot.quota = Quota(
            usedPercent: primary.used_percent,
            windowMinutes: primary.window_minutes,
            resetsAt: Date(timeIntervalSince1970: primary.resets_at)
        )
        // The vendor only writes this while Codex runs, so the reading is only
        // as fresh as the session that produced it.
        snapshot.quotaObserved = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        snapshot.usage = TokenSources.codex(root: root, since: Date().addingTimeInterval(-7 * 86_400))
        snapshot.usageToday = TokenSources.codex(root: root, since: Date().addingTimeInterval(-86_400))

        let codexTranscript = UsageIndex.newestTranscript(in: [root])
        snapshot.sessions = sessions.map {
            var copy = $0
            copy.activity = activity(
                lastWrite: codexTranscript?.written,
                transcript: codexTranscript?.url,
                agent: agent
            )
            return copy
        }
        if let credits = limits.credits, credits.unlimited != true, let balance = credits.balance {
            snapshot.credits = balance
        }
        snapshot.availability = .ready
        return snapshot
    }

    private func newestSessionFile() -> URL? {
        UsageIndex.transcripts(in: [root], modifiedAfter: Date(timeIntervalSince1970: 0))
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }
    }
}

// MARK: - Claude Code

/// No limit is ever written to disk, so this reports locally computed usage
/// only, and the UI labels it as such. Transcripts nest one level deeper than
/// they appear: subagent runs live in `<session>/subagents/` and carry a large
/// share of the tokens.
struct ClaudeProvider: AgentProvider {
    let agent = AgentID.claude
    let index: UsageIndex
    private let root = home.appendingPathComponent(".claude/projects")

    func probe(sessions: [RunningSession]) async -> AgentSnapshot {
        var snapshot = AgentSnapshot(agent: agent, sessions: sessions)
        guard FileManager.default.fileExists(atPath: root.path) else {
            snapshot.availability = .notInstalled
            return snapshot
        }

        let windows = await index.windows(agent: agent, roots: [root])
        snapshot.usage = windows.week
        snapshot.usageToday = windows.day
        snapshot.sessions = await enrich(sessions)
        snapshot.availability = .ready
        return snapshot
    }

    /// Adds the "what is it working on" line: exact when the process carries
    /// `--resume <uuid>`, otherwise the newest session sharing its cwd.
    private func enrich(_ sessions: [RunningSession]) async -> [RunningSession] {
        var result: [RunningSession] = []
        var claimed = Set<String>()

        for var session in sessions {
            if let id = session.sessionID, let meta = await index.sessionMeta(id: id) {
                claimed.insert(id)
                session.title = meta.title
                session.cwd = meta.cwd ?? session.cwd
                session.branch = meta.branch
            } else if let cwd = session.cwd,
                      let match = await index.newestSession(cwd: cwd, excluding: claimed) {
                // Without a resume flag the best available signal is the newest
                // transcript in the same directory. Claiming it stops several
                // concurrent sessions all reporting the same title.
                claimed.insert(match.id)
                session.title = match.meta.title
                session.branch = match.meta.branch
            } else {
                session.title = nil
            }
            let transcript = UsageIndex.newestTranscript(in: [root], matching: session.sessionID)
                ?? UsageIndex.newestTranscript(in: [root])
            session.activity = activity(
                lastWrite: transcript?.written,
                transcript: transcript?.url,
                agent: agent
            )
            if let id = session.sessionID {
                session.subAgents = SessionDetail.subAgents(sessionID: id, root: root)
                session.branch = SessionDetail.branch(sessionID: id, root: root) ?? session.branch
            }
            result.append(session)
        }
        return result
    }
}

// MARK: - OpenCode

/// Token totals are already aggregated per session in SQLite, so a single
/// read-only query covers the whole window. The database belongs to another
/// process and is never written to.
struct OpenCodeProvider: AgentProvider {
    let agent = AgentID.opencode
    private let dbPath = home.appendingPathComponent(".local/share/opencode/opencode.db").path

    func probe(sessions: [RunningSession]) async -> AgentSnapshot {
        var snapshot = AgentSnapshot(agent: agent, sessions: sessions)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            snapshot.availability = .notInstalled
            return snapshot
        }

        let since = Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970 * 1000
        let sql = """
        SELECT COALESCE(SUM(tokens_input),0), COALESCE(SUM(tokens_output),0), \
        COALESCE(SUM(tokens_cache_write),0), COALESCE(SUM(tokens_cache_read),0), \
        COALESCE(SUM(cost),0) FROM session WHERE time_updated > \(Int(since));
        """

        guard let row = SQLiteReader.queryRow(path: dbPath, sql: sql), row.count >= 5 else {
            snapshot.availability = .unavailable("database busy")
            return snapshot
        }

        var usage = Usage()
        usage.input = Int(row[0]) ?? 0
        usage.output = Int(row[1]) ?? 0
        usage.cacheCreate = Int(row[2]) ?? 0
        usage.cacheRead = Int(row[3]) ?? 0
        usage.cost = Double(row[4])
        snapshot.usage = usage

        let sinceDay = Date().addingTimeInterval(-86_400).timeIntervalSince1970 * 1000
        if let dayRow = SQLiteReader.queryRow(
            path: dbPath,
            sql: """
            SELECT COALESCE(SUM(tokens_input),0), COALESCE(SUM(tokens_output),0), \
            COALESCE(SUM(tokens_cache_write),0), COALESCE(SUM(tokens_cache_read),0), \
            COALESCE(SUM(cost),0) FROM session WHERE time_updated > \(Int(sinceDay));
            """
        ), dayRow.count >= 5 {
            var today = Usage()
            today.input = Int(dayRow[0]) ?? 0
            today.output = Int(dayRow[1]) ?? 0
            today.cacheCreate = Int(dayRow[2]) ?? 0
            today.cacheRead = Int(dayRow[3]) ?? 0
            today.cost = Double(dayRow[4])
            snapshot.usageToday = today
        }

        let openCodeWrite = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.modificationDate] as? Date) ?? nil
        snapshot.sessions = sessions.map {
            var copy = $0
            copy.activity = activity(lastWrite: openCodeWrite)
            return copy
        }
        if !sessions.isEmpty,
           let title = SQLiteReader.queryRow(
               path: dbPath,
               sql: "SELECT title FROM session ORDER BY time_updated DESC LIMIT 1;"
           )?.first {
            snapshot.sessions = snapshot.sessions.map {
                var copy = $0
                copy.title = title
                return copy
            }
        }
        snapshot.availability = .ready
        return snapshot
    }
}

// MARK: - Grok

/// Grok logs one `usage` block per turn, per working directory, and is the only
/// agent besides OpenCode that records what a turn cost.
struct GrokProvider: AgentProvider {
    let agent = AgentID.grok
    private let root = home.appendingPathComponent(".grok/sessions")

    func probe(sessions: [RunningSession]) async -> AgentSnapshot {
        var snapshot = AgentSnapshot(agent: agent, sessions: sessions)
        guard FileManager.default.fileExists(atPath: root.path) else {
            snapshot.availability = installedElsewhere || !sessions.isEmpty ? .ready : .notInstalled
            return snapshot
        }

        snapshot.usage = TokenSources.grok(root: root, since: Date().addingTimeInterval(-7 * 86_400))
        snapshot.usageToday = TokenSources.grok(root: root, since: Date().addingTimeInterval(-86_400))

        let lastWrite = UsageIndex.lastWrite(in: [root])
        snapshot.sessions = sessions.map {
            var copy = $0
            copy.activity = activity(lastWrite: lastWrite)
            return copy
        }
        snapshot.availability = .ready
        return snapshot
    }

    private var installedElsewhere: Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(".grok").path)
    }
}

// MARK: - Presence only

/// Cursor, Gemini, Antigravity and Hermes keep nothing useful on disk. They are
/// shown as running or idle and nothing is invented for them.
struct PresenceProvider: AgentProvider {
    let agent: AgentID
    let installedPaths: [String]

    func probe(sessions: [RunningSession]) async -> AgentSnapshot {
        var snapshot = AgentSnapshot(agent: agent, sessions: sessions)
        let installed = installedPaths.contains { FileManager.default.fileExists(atPath: $0) }
        snapshot.availability = installed || !sessions.isEmpty ? .ready : .notInstalled
        return snapshot
    }
}
