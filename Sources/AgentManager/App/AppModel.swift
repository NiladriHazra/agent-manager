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
            var built: [AgentSnapshot] = []
            for provider in providers {
                let mine = running.filter { $0.agent == provider.agent }
                built.append(await provider.probe(sessions: mine))
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
        // An open panel is being read right now, so it refreshes far more
        // often; a closed one only needs to keep the menu bar roughly current.
        let interval = menuIsOpen ? 3 : TimeInterval(max(10, Preferences.shared.refreshSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if refreshNow { refresh() }
    }

    func restartTimer() { startTimer() }
}
