import Foundation

/// Per-agent token accounting.
///
/// Every CLI records usage its own way, so each has its own reader rather than
/// one shape forced onto all of them:
///
/// - Codex writes a cumulative `total_token_usage` per session
/// - Grok writes a per-turn `usage` block with its own camelCase keys and a
///   cost expressed in ticks
/// - Claude writes per-message `message.usage` (handled by UsageIndex)
/// - OpenCode aggregates in SQLite (handled by its provider)
/// - Cursor, Gemini, Antigravity and Hermes record nothing usable
enum TokenSources {
    /// Codex totals are cumulative per session, so the newest record in each
    /// session touched inside the window is summed. Tail-read only: a single
    /// session file reaches 295 MB.
    static func codex(root: URL, since: Date) -> Usage? {
        let files = UsageIndex.transcripts(in: [root], modifiedAfter: since)
        guard !files.isEmpty else { return nil }

        var usage = Usage()
        var found = false
        let decoder = JSONDecoder()

        for file in files {
            guard let totals = TailReader.newestLine(
                in: file,
                containing: "\"total_token_usage\"",
                budgets: [128 * 1024, 512 * 1024],
                decode: { data -> CodexTotals? in
                    (try? decoder.decode(CodexEnvelope.self, from: data))?
                        .payload?.info?.total_token_usage
                }
            ) else { continue }

            found = true
            usage.input += totals.input_tokens ?? 0
            usage.output += totals.output_tokens ?? 0
            usage.cacheRead += totals.cached_input_tokens ?? 0
            usage.cacheCreate += totals.cache_write_input_tokens ?? 0
        }
        return found ? usage : nil
    }

    private struct CodexEnvelope: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable { let total_token_usage: CodexTotals? }
            let info: Info?
        }
        let payload: Payload?
    }

    private struct CodexTotals: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cached_input_tokens: Int?
        let cache_write_input_tokens: Int?
    }

    /// Grok logs one `usage` block per turn under
    /// `~/.grok/sessions/<encoded-cwd>/updates.jsonl`, with camelCase keys and
    /// a cost in ticks (1e9 ticks = 1 USD).
    static func grok(root: URL, since: Date) -> Usage? {
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var usage = Usage()
        var ticks = 0.0
        var found = false
        let decoder = JSONDecoder()

        for case let url as URL in walker {
            guard url.lastPathComponent == "updates.jsonl" else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified > since else { continue }

            // Turns are appended, so the tail covers recent activity without
            // reading a long-lived session end to end.
            for line in TailReader.lines(of: url, bytes: 2 * 1024 * 1024) {
                guard line.contains("\"usage\""),
                      let record = try? decoder.decode(GrokEnvelope.self, from: Data(line.utf8)),
                      let block = record.params?.update?.usage
                else { continue }
                found = true
                usage.input += block.inputTokens ?? 0
                usage.output += block.outputTokens ?? 0
                usage.cacheRead += block.cachedReadTokens ?? 0
                usage.cacheCreate += block.cacheCreationTokens ?? 0
                ticks += Double(block.costUsdTicks ?? 0)
            }
        }
        if ticks > 0 { usage.cost = ticks / 1_000_000_000 }
        return found ? usage : nil
    }

    private struct GrokEnvelope: Decodable {
        struct Params: Decodable {
            struct Update: Decodable { let usage: GrokUsage? }
            let update: Update?
        }
        let params: Params?
    }

    private struct GrokUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedReadTokens: Int?
        let cacheCreationTokens: Int?
        let costUsdTicks: Int?
    }
}
