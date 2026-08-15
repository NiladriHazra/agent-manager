import Combine
import Foundation
import SwiftUI

enum MenuBarMode: String, CaseIterable, Identifiable {
    case countAndQuota
    case countOnly
    case quotaOnly
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .countAndQuota: return "Count and quota"
        case .countOnly: return "Count only"
        case .quotaOnly: return "Quota only"
        case .iconOnly: return "Icon only"
        }
    }
}

/// Settings, persisted to UserDefaults.
///
/// Deliberately not `@AppStorage`: that is a SwiftUI `DynamicProperty` and only
/// publishes changes when it is declared inside a `View`. In an
/// `ObservableObject` it still reads and writes, but `objectWillChange` never
/// fires, so changing a setting would silently fail to update the menu bar.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults: UserDefaults

    @Published var menuBarMode: MenuBarMode { didSet { defaults.set(menuBarMode.rawValue, forKey: Key.menuBarMode) } }
    @Published var refreshSeconds: Int { didSet { defaults.set(refreshSeconds, forKey: Key.refreshSeconds) } }
    @Published var warnThreshold: Int { didSet { defaults.set(warnThreshold, forKey: Key.warnThreshold) } }
    @Published var criticalThreshold: Int { didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) } }
    @Published var includeCacheReads: Bool { didSet { defaults.set(includeCacheReads, forKey: Key.includeCacheReads) } }
    @Published var hideNotInstalled: Bool { didSet { defaults.set(hideNotInstalled, forKey: Key.hideNotInstalled) } }
    /// Off by default: the panel answers "what is working right now", so idle
    /// agents are noise unless you ask for them.
    @Published var hiddenAgents: Set<AgentID> {
        didSet { defaults.set(hiddenAgents.map(\.rawValue).sorted(), forKey: Key.hiddenAgents) }
    }
    /// Which readings a row is allowed to draw. Agents publish wildly different
    /// data, so this is stored per agent rather than globally.
    @Published var hiddenMetrics: [String: Set<String>] {
        didSet {
            defaults.set(
                hiddenMetrics.mapValues { Array($0).sorted() },
                forKey: Key.hiddenMetrics
            )
        }
    }

    private enum Key {
        static let menuBarMode = "menuBarMode"
        static let refreshSeconds = "refreshSeconds"
        static let warnThreshold = "warnThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let includeCacheReads = "includeCacheReads"
        static let hideNotInstalled = "hideNotInstalled"
        static let hiddenAgents = "hiddenAgents"
        static let hiddenMetrics = "hiddenMetrics"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMode = (defaults.string(forKey: Key.menuBarMode)
            .flatMap(MenuBarMode.init(rawValue:))) ?? .countAndQuota
        refreshSeconds = defaults.object(forKey: Key.refreshSeconds) as? Int ?? 60
        hiddenMetrics = (defaults.dictionary(forKey: Key.hiddenMetrics) as? [String: [String]] ?? [:])
            .mapValues(Set.init)
        warnThreshold = defaults.object(forKey: Key.warnThreshold) as? Int ?? 20
        criticalThreshold = defaults.object(forKey: Key.criticalThreshold) as? Int ?? 10
        includeCacheReads = defaults.bool(forKey: Key.includeCacheReads)
        hideNotInstalled = defaults.object(forKey: Key.hideNotInstalled) as? Bool ?? true
        hiddenAgents = Set(
            (defaults.stringArray(forKey: Key.hiddenAgents) ?? []).compactMap(AgentID.init(rawValue:))
        )
    }

    func isHidden(_ agent: AgentID) -> Bool { hiddenAgents.contains(agent) }

    func setHidden(_ agent: AgentID, _ hidden: Bool) {
        if hidden { hiddenAgents.insert(agent) } else { hiddenAgents.remove(agent) }
    }

    /// Lives here rather than in a view body so it is testable and so
    /// PreferencesCheck can exercise the same path the UI uses.
    func visibilityBinding(for agent: AgentID) -> Binding<Bool> {
        Binding(get: { !self.isHidden(agent) }, set: { self.setHidden(agent, !$0) })
    }

    func isEnabled(_ metric: Metric, for agent: AgentID) -> Bool {
        !(hiddenMetrics[agent.rawValue]?.contains(metric.rawValue) ?? false)
    }

    func setEnabled(_ metric: Metric, for agent: AgentID, _ enabled: Bool) {
        var set = hiddenMetrics[agent.rawValue] ?? []
        if enabled { set.remove(metric.rawValue) } else { set.insert(metric.rawValue) }
        hiddenMetrics[agent.rawValue] = set
    }

    func metricBinding(_ metric: Metric, for agent: AgentID) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(metric, for: agent) },
            set: { self.setEnabled(metric, for: agent, $0) }
        )
    }
}
