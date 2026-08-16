import Combine
import Foundation
import SwiftUI

/// Owns the snapshot list the UI renders and decides when to refresh.
///
/// Work happens off the main actor; only the finished snapshots are published,
/// and only when they actually differ, so an idle menu bar does no rendering.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshots: [AgentSnapshot] = []
    // Neither is observed by a view. Publishing them invalidated the whole
    // panel three times per refresh, defeating the snapshot diffing below.
    private(set) var lastUpdated: Date?
    private var isRefreshing = false

    private let index = UsageIndex()
    private var providers: [AgentProvider] = []
    private var timer: Timer?
    private var menuIsOpen = false

    init() {
        providers = allProviders(index: index)
        snapshots = providers.map { AgentSnapshot(agent: $0.agent) }
        startTimer()
    }

    /// The single quota worth surfacing in the menu bar. Only Codex publishes a
    /// real one today, so it is attributed rather than presented as a
    /// cross-agent minimum, which would be a lie.
    var headlineQuota: (agent: AgentID, quota: Quota)? {
        snapshots
            .compactMap { snap in snap.quota.map { (snap.agent, $0) } }
            .min { $0.1.remainingPercent < $1.1.remainingPercent }
    }

    /// Working, not merely alive. A session parked at a prompt is not doing
    /// anything and should not be counted as if it were.
    var workingCount: Int {
        snapshots.reduce(0) { $0 + $1.workingSessions.count }
    }

    var openCount: Int {
        snapshots.reduce(0) { $0 + $1.sessions.count }
    }

    /// Sessions that finished a turn and are holding for your reply.
    var waitingCount: Int {
        snapshots.reduce(0) { $0 + $1.waitingSessions.count }
    }

    /// The one number worth putting in the menu bar for an agent.
    ///
    /// A vendor quota if there is one, otherwise the fullest live context,
    /// which is the only other real percentage any of these agents produce.
    /// Agents with neither contribute nothing rather than a made-up figure.
    func headlinePercent(for agent: AgentID) -> Int? {
        guard let snapshot = snapshots.first(where: { $0.agent == agent }) else { return nil }
        if let quota = snapshot.quota { return Int(quota.usedPercent) }
        // The session you are actually in: working first, then the one that
        // wrote most recently. Taking the fullest made the number jump between
        // unrelated sessions on every refresh.
        let ordered = snapshot.sessions.sorted { lhs, rhs in
            if lhs.activity.isWorking != rhs.activity.isWorking { return lhs.activity.isWorking }
            return (lhs.activity.since ?? .distantPast) > (rhs.activity.since ?? .distantPast)
        }
        guard let fraction = ordered.compactMap({ $0.chat?.contextFraction }).first,
              fraction > 0 else { return nil }
        return Int(fraction * 100)
    }

    /// Agents the user picked that actually have a number today.
    var menuBarReadings: [(agent: AgentID, percent: Int)] {
        Preferences.shared.menuBarAgents.compactMap { agent in
            headlinePercent(for: agent).map { (agent, $0) }
        }
    }

    func count(for tab: PanelTab) -> Int {
        switch tab {
        case .working: return workingCount
        case .waiting: return waitingCount
        case .open: return openCount
        }
    }

    var visibleSnapshots: [AgentSnapshot] {
        let prefs = Preferences.shared
        return snapshots.filter { snapshot in
            if prefs.isHidden(snapshot.agent) { return false }
            if prefs.hideNotInstalled, snapshot.availability == .notInstalled, snapshot.sessions.isEmpty {
                return false
            }
            return true
        }
    }

    func menuOpened() {
        menuIsOpen = true
        refresh()
        startTimer()
    }

    func menuClosed() {
        menuIsOpen = false
        startTimer(refreshNow: false)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let providers = self.providers
        Task.detached(priority: .utility) {
            let running = ProcessScanner.runningAgents()
            // Concurrently: probing in sequence made every refresh as slow as
            // the sum of all providers, and Codex alone took most of a second.
            let built = await withTaskGroup(of: (Int, AgentSnapshot).self) { group in
                for (index, provider) in providers.enumerated() {
                    let mine = running.filter { $0.agent == provider.agent }
                    group.addTask { (index, await provider.probe(sessions: mine)) }
                }
                var collected: [(Int, AgentSnapshot)] = []
                for await pair in group { collected.append(pair) }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let result = built
            await MainActor.run {
                if result != self.snapshots { self.snapshots = result }
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }

    private func startTimer(refreshNow: Bool = true) {
        timer?.invalidate()
        // An open panel is being read right now: probes run concurrently and
        // unchanged files are cached, so a one-second beat is affordable. A
        // closed one only needs to keep the menu bar roughly current.
        let interval = menuIsOpen ? 1 : TimeInterval(max(10, Preferences.shared.refreshSeconds))

        // .common, not the default mode. While a popover or a menu is open the
        // run loop switches to event tracking, where a default-mode timer never
        // fires — which is exactly when the panel is on screen being watched,
        // so it sat frozen until something forced a refresh.
        let created = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(created, forMode: .common)
        timer = created

        if refreshNow { refresh() }
    }

    func restartTimer() { startTimer() }
}
