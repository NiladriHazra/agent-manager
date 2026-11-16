import Foundation

/// A small public summary, and only when an endpoint and token are both set.
/// The clock and coalescing live on the main actor; the request does not.
@MainActor
final class LiveStatusPublisher {
    private var snapshots: [AgentSnapshot] = []
    private var timer: Timer?
    private var configuration: Configuration?
    private var lastSent: Content?
    private var lastSentAt: Date?
    private var lastAttemptAt: Date?
    private var isSending = false
    private var loggedFailures: Set<String> = []
    private let queue = DispatchQueue(label: "com.niladri.agent-manager.live-status", qos: .utility)

    func publish(_ snapshots: [AgentSnapshot]) {
        self.snapshots = snapshots
        publishLatest()
    }

    private func publishLatest() {
        timer?.invalidate()
        timer = nil

        let defaults = UserDefaults.standard
        // Do not even create a URLSession unless both opt-in keys are present.
        guard let address = defaults.string(forKey: "liveStatusURL"),
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let token = defaults.string(forKey: "liveStatusToken"),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            configuration = nil
            lastSent = nil
            lastSentAt = nil
            return
        }
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            logOnce("invalid HTTPS endpoint")
            configuration = nil
            lastSent = nil
            lastSentAt = nil
            return
        }

        let current = Configuration(url: url, token: token)
        if configuration != current {
            configuration = current
            lastSent = nil
            lastSentAt = nil
        }
        guard !isSending else { return }

        let projects = Set(defaults.stringArray(forKey: "liveStatusProjects") ?? [])
        let content = Content(
            snapshots: snapshots, projects: projects,
            includeCacheReads: Preferences.shared.includeCacheReads
        )
        let now = Date()
        let neededAt = content != lastSent ? now : (lastSentAt ?? .distantPast).addingTimeInterval(300)
        let allowedAt = lastAttemptAt?.addingTimeInterval(30) ?? now
        let sendAt = max(neededAt, allowedAt)
        if sendAt > now {
            let created = Timer(fire: sendAt, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.publishLatest() }
            }
            RunLoop.main.add(created, forMode: .common)
            timer = created
            return
        }

        isSending = true
        lastAttemptAt = now
        queue.async { [weak self] in
            Self.send(content, configuration: current) { failure in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isSending = false
                    if let failure {
                        self.logOnce(failure)
                    } else if self.configuration == current {
                        // A failed request never becomes the diffing baseline.
                        self.lastSent = content
                        self.lastSentAt = Date()
                    }
                    self.publishLatest()
                }
            }
        }
    }

    private func logOnce(_ kind: String) {
        guard loggedFailures.insert(kind).inserted else { return }
        // No URL, token, response body or localized error: those can carry secrets.
        NSLog("Live status: %@", kind)
    }

    private struct Configuration: Equatable {
        let url: URL
        let token: String
    }

    private struct Content: Encodable, Equatable {
        let working: Int
        let waiting: Int
        let open: Int
        let tokensToday: Int
        let agents: [Agent]
        let sessions: [Session]

        init(snapshots: [AgentSnapshot], projects: Set<String>, includeCacheReads: Bool) {
            let rows = snapshots.map { snapshot in
                Agent(
                    id: snapshot.agent.rawValue, name: snapshot.agent.displayName,
                    working: snapshot.workingSessions.count,
                    waiting: snapshot.waitingSessions.count, open: snapshot.sessions.count,
                    tokensToday: snapshot.usageToday?.total(includingCacheReads: includeCacheReads)
                )
            }
            working = rows.reduce(0) { $0 + $1.working }
            waiting = rows.reduce(0) { $0 + $1.waiting }
            open = rows.reduce(0) { $0 + $1.open }
            tokensToday = rows.reduce(0) { $0 + ($1.tokensToday ?? 0) }
            agents = rows.filter { $0.open > 0 || ($0.tokensToday ?? 0) > 0 }.sorted {
                if $0.working != $1.working { return $0.working > $1.working }
                if ($0.tokensToday ?? 0) != ($1.tokensToday ?? 0) {
                    return ($0.tokensToday ?? 0) > ($1.tokensToday ?? 0)
                }
                return $0.id < $1.id
            }
            let publicSessions = snapshots.flatMap(\.sessions).map { session in
                let project = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                return Session(
                    agent: session.agent.rawValue,
                    state: session.activity.isWorking ? "working" : (session.activity.isWaiting ? "waiting" : "idle"),
                    project: project.flatMap { projects.contains($0) ? $0 : nil }
                )
            }
            sessions = Array(publicSessions.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.agent != $1.agent { return $0.agent < $1.agent }
                return ($0.project ?? "") < ($1.project ?? "")
            }.prefix(12))
        }
    }

    private struct Agent: Encodable, Equatable {
        let id: String
        let name: String
        let working: Int
        let waiting: Int
        let open: Int
        let tokensToday: Int?

        private enum CodingKeys: String, CodingKey { case id, name, working, waiting, open, tokensToday }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(name, forKey: .name)
            try values.encode(working, forKey: .working)
            try values.encode(waiting, forKey: .waiting)
            try values.encode(open, forKey: .open)
            try values.encode(tokensToday, forKey: .tokensToday)
        }
    }

    private struct Session: Encodable, Equatable {
        let agent: String
        let state: String
        let project: String?

        var rank: Int { state == "working" ? 0 : (state == "waiting" ? 1 : 2) }

        private enum CodingKeys: String, CodingKey { case agent, state, project }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(agent, forKey: .agent)
            try values.encode(state, forKey: .state)
            try values.encode(project, forKey: .project)
        }
    }

    private struct Payload: Encodable {
        let content: Content

        private enum CodingKeys: String, CodingKey { case v, at }

        func encode(to encoder: Encoder) throws {
            try content.encode(to: encoder)
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(1, forKey: .v)
            try values.encode(ISO8601DateFormatter().string(from: Date()), forKey: .at)
        }
    }

    nonisolated private static func send(
        _ content: Content, configuration: Configuration, completion: @escaping (String?) -> Void
    ) {
        var request = URLRequest(url: configuration.url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try JSONEncoder().encode(Payload(content: content))
        } catch {
            completion("JSON encoding failed")
            return
        }

        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 10
        settings.timeoutIntervalForResource = 10
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        callbacks.qualityOfService = .utility
        let session = URLSession(configuration: settings, delegate: RedirectBlocker(), delegateQueue: callbacks)
        session.dataTask(with: request) { _, response, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                completion("network error \((error as NSError).code)")
            } else if let response = response as? HTTPURLResponse {
                completion((200..<300).contains(response.statusCode) ? nil : "HTTP \(response.statusCode)")
            } else {
                completion("missing HTTP response")
            }
        }.resume()
    }

    /// The opt-in is for this endpoint, not whatever a redirect points at.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
