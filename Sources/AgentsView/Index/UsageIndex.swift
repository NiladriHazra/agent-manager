import Foundation

/// Incremental token accounting over append-only JSONL transcripts.
///
/// A cold pass over the 7-day working set costs about a second, which is fine
/// once but not every minute. State is keyed by (device, inode) so renames do
/// not orphan an entry, and totals live in hourly buckets so the sliding
/// 7-day window never requires a rescan.
actor UsageIndex {
    private struct FileState: Codable {
        var path: String
        var size: Int
        var offset: Int
    }

    private struct Bucket: Codable {
        var input = 0
        var output = 0
        var cacheCreate = 0
        var cacheRead = 0
    }

    private struct Store: Codable {
        var version = 3
        var files: [String: FileState] = [:]
        var buckets: [String: [String: Bucket]] = [:]
        var titles: [String: SessionMeta] = [:]
    }

    struct SessionMeta: Codable {
        var title: String?
        var cwd: String?
        var branch: String?
        var updated: Double
    }

    /// Only the fields we need; decoding the full record would be far slower.
    private struct Record: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let usage: Usage?
        }
        let timestamp: String?
        let message: Message?
        let sessionId: String?
        let cwd: String?
        let gitBranch: String?
        let aiTitle: String?
    }

    private let storeURL: URL
    private var store = Store()
    private var loaded = false
    private let decoder = JSONDecoder()
    private let isoFormatter = ISO8601DateFormatter()

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentsView", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storeURL = base.appendingPathComponent("usage-index.json")
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Rescans whatever changed and returns the rolling window total.
    func refresh(agent: AgentID, roots: [URL], windowDays: Int = 7) -> Usage {
        load()
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 86_400)

        for file in Self.transcripts(in: roots, modifiedAfter: cutoff) {
            ingest(file: file, agent: agent)
        }

        prune(before: Date().addingTimeInterval(-14 * 86_400))
        save()
        return total(agent: agent, since: cutoff)
    }

    func sessionMeta(id: String) -> SessionMeta? {
        load()
        return store.titles[id]
    }

    /// Newest session whose cwd matches, used when a process carries no
    /// `--resume` flag and must be matched by working directory instead.
    func newestSession(cwd: String, excluding: Set<String> = []) -> (id: String, meta: SessionMeta)? {
        load()
        return store.titles
            .filter { $0.value.cwd == cwd && !excluding.contains($0.key) }
            .max { $0.value.updated < $1.value.updated }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Scanning

    private func ingest(file: URL, agent: AgentID) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? Int,
              let inode = attrs[.systemFileNumber] as? Int,
              let device = attrs[.systemNumber] as? Int
        else { return }

        let key = "\(device):\(inode)"
        var state = store.files[key] ?? FileState(path: file.path, size: 0, offset: 0)

        // Unchanged since last pass: skip without opening the file at all.
        if state.offset > 0, size == state.size { return }

        // Shrunk means truncation or replacement; buckets are additive and
        // cannot be un-added, so the safest correct move is a clean rebuild.
        if size < state.offset {
            rebuild()
            state = FileState(path: file.path, size: 0, offset: 0)
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(state.offset))

        // Chunked so one enormous delta cannot stall the queue.
        var consumed = state.offset
        var carry = Data()
        while let chunk = try? handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            var data = carry
            data.append(chunk)
            let lastBreak = data.lastIndex(of: UInt8(ascii: "\n"))
            guard let lastBreak else { carry = data; continue }

            let complete = data[..<lastBreak]
            carry = Data(data[data.index(after: lastBreak)...])
            consumed += complete.count + 1

            for line in complete.split(separator: UInt8(ascii: "\n")) {
                apply(line: Data(line), agent: agent)
            }
        }

        state.path = file.path
        state.offset = consumed
        state.size = size
        store.files[key] = state
    }

    private func apply(line: Data, agent: AgentID) {
        // Cheap byte prefilter: most lines are tool traffic with no usage block.
        guard line.count > 24 else { return }
        let hasUsage = line.range(of: Data("\"usage\"".utf8)) != nil
        let hasTitle = line.range(of: Data("\"aiTitle\"".utf8)) != nil
        guard hasUsage || hasTitle else { return }

        guard let record = try? decoder.decode(Record.self, from: line) else { return }
        let stamp = record.timestamp.flatMap { parseDate($0) } ?? Date()

        if let usage = record.message?.usage, hasUsage {
            let hour = String(Int(stamp.timeIntervalSince1970) / 3600)
            var bucket = store.buckets[agent.rawValue]?[hour] ?? Bucket()
            bucket.input += usage.input_tokens ?? 0
            bucket.output += usage.output_tokens ?? 0
            bucket.cacheCreate += usage.cache_creation_input_tokens ?? 0
            bucket.cacheRead += usage.cache_read_input_tokens ?? 0
            store.buckets[agent.rawValue, default: [:]][hour] = bucket
        }

        if let session = record.sessionId {
            var meta = store.titles[session] ?? SessionMeta(updated: 0)
            if let title = record.aiTitle, !title.isEmpty { meta.title = title }
            if let cwd = record.cwd { meta.cwd = cwd }
            if let branch = record.gitBranch { meta.branch = branch }
            meta.updated = max(meta.updated, stamp.timeIntervalSince1970)
            store.titles[session] = meta
        }
    }

    private func parseDate(_ raw: String) -> Date? {
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: raw) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: raw)
    }

    private func total(agent: AgentID, since: Date) -> Usage {
        let firstHour = Int(since.timeIntervalSince1970) / 3600
        var usage = Usage()
        for (hour, bucket) in store.buckets[agent.rawValue] ?? [:] {
            guard let value = Int(hour), value >= firstHour else { continue }
            usage.input += bucket.input
            usage.output += bucket.output
            usage.cacheCreate += bucket.cacheCreate
            usage.cacheRead += bucket.cacheRead
        }
        return usage
    }

    private func prune(before date: Date) {
        let floor = Int(date.timeIntervalSince1970) / 3600
        for agent in store.buckets.keys {
            store.buckets[agent] = store.buckets[agent]?.filter { Int($0.key) ?? 0 >= floor }
        }
        store.titles = store.titles.filter { $0.value.updated >= date.timeIntervalSince1970 }
    }

    private func rebuild() {
        store = Store()
    }

    /// Every `.jsonl` under the roots, including nested subagent transcripts,
    /// which hold a large share of the real token spend.
    static func transcripts(in roots: [URL], modifiedAfter: Date) -> [URL] {
        var found: [URL] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in walker {
                guard url.pathExtension == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let modified = values?.contentModificationDate, modified > modifiedAfter else { continue }
                found.append(url)
            }
        }
        return found
    }

    // MARK: - Persistence

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(Store.self, from: data),
              decoded.version == Store().version
        else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
