import Foundation

/// A subagent spawned by a session. Claude keeps these as their own transcripts
/// under `<session>/subagents/`, so each one has its own branch, prompt and
/// last-write time.
struct SubAgent: Identifiable, Equatable {
    let id: String
    var task: String?
    var branch: String?
    var lastWrite: Date?

    var isWorking: Bool {
        guard let lastWrite else { return false }
        return Date().timeIntervalSince(lastWrite) <= workingWindow
    }

    var label: String {
        task?.shortenedToWords(6, maxChars: 40) ?? String(id.prefix(10))
    }
}

/// Reads the extra detail a row shows when expanded: which branch a session is
/// on and what its subagents are doing.
enum SessionDetail {
    /// Subagents of a Claude session, newest first. Bounded reads: only the
    /// first user message and the last branch are needed, so each file is read
    /// until both are found rather than to the end.
    static func subAgents(sessionID: String, root: URL) -> [SubAgent] {
        guard let dir = locateSessionDirectory(sessionID: sessionID, root: root) else { return [] }
        let subagentDir = dir.appendingPathComponent("subagents", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: subagentDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .map { url in
                let meta = summarize(url)
                return SubAgent(
                    id: url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "agent-", with: ""),
                    task: meta.task,
                    branch: meta.branch,
                    lastWrite: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate
                )
            }
            .sorted { ($0.lastWrite ?? .distantPast) > ($1.lastWrite ?? .distantPast) }
    }

    /// The branch a session is on, taken from the newest record that names one.
    static func branch(sessionID: String, root: URL) -> String? {
        guard let dir = locateSessionDirectory(sessionID: sessionID, root: root) else { return nil }
        let transcript = dir.deletingLastPathComponent()
            .appendingPathComponent("\(sessionID).jsonl")
        for line in TailReader.lines(of: transcript, bytes: 96 * 1024) {
            guard line.contains("\"gitBranch\""),
                  let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(BranchRecord.self, from: data),
                  let branch = record.gitBranch, !branch.isEmpty
            else { continue }
            return branch
        }
        return nil
    }

    private struct BranchRecord: Decodable { let gitBranch: String? }

    private struct Summary { var task: String?; var branch: String? }

    private static func summarize(_ url: URL) -> Summary {
        var summary = Summary()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return summary }
        defer { try? handle.close() }

        // The opening prompt is near the top; stop as soon as it is found.
        var scanned = 0
        while scanned < 512 * 1024, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            scanned += chunk.count
            for line in chunk.split(separator: UInt8(ascii: "\n")) {
                guard let record = try? JSONDecoder().decode(PromptRecord.self, from: Data(line))
                else { continue }
                if summary.branch == nil, let branch = record.gitBranch, !branch.isEmpty {
                    summary.branch = branch
                }
                if summary.task == nil, record.type == "user", let text = record.message?.text {
                    summary.task = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if summary.task != nil, summary.branch != nil { return summary }
            }
        }
        return summary
    }

    private struct PromptRecord: Decodable {
        struct Message: Decodable {
            let content: Content?
            var text: String? {
                switch content {
                case .text(let value): return value
                case .blocks(let blocks): return blocks.first { $0.type == "text" }?.text
                case .none: return nil
                }
            }
            enum Content: Decodable {
                case text(String)
                case blocks([Block])
                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let value = try? container.decode(String.self) { self = .text(value) }
                    else { self = .blocks((try? container.decode([Block].self)) ?? []) }
                }
            }
            struct Block: Decodable { let type: String?; let text: String? }
        }
        let type: String?
        let gitBranch: String?
        let message: Message?
    }

    /// `~/.claude/projects/<encoded-cwd>/<sessionId>/`
    private static func locateSessionDirectory(sessionID: String, root: URL) -> URL? {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return nil }
        for project in projects {
            let candidate = project.appendingPathComponent(sessionID, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
