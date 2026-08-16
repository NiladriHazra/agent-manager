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
    /// The mark is always shown; everything beside it is optional.
    @Published var showAgentCount: Bool { didSet { defaults.set(showAgentCount, forKey: Key.showAgentCount) } }
    @Published var showPercentages: Bool { didSet { defaults.set(showPercentages, forKey: Key.showPercentages) } }
    /// Which agents contribute a percentage, in the order they were added.
    @Published var menuBarAgents: [AgentID] {
        didSet { defaults.set(menuBarAgents.map(\.rawValue), forKey: Key.menuBarAgents) }
    }
    @Published var maxMenuBarAgents: Int { didSet { defaults.set(maxMenuBarAgents, forKey: Key.maxMenuBarAgents) } }
    /// Per agent: which percentage the menu bar shows.
    @Published var percentSources: [String: String] {
        didSet { defaults.set(percentSources, forKey: Key.percentSources) }
    }
    /// Weekly and daily token budgets, in millions, for agents that publish no
    /// limit of their own.
    @Published var weeklyBudgets: [String: Int] {
        didSet { defaults.set(weeklyBudgets, forKey: Key.weeklyBudgets) }
    }
    @Published var dailyBudgets: [String: Int] {
        didSet { defaults.set(dailyBudgets, forKey: Key.dailyBudgets) }
    }
    /// Per agent: mark, number, or both.
    @Published var menuBarStyles: [String: String] {
        didSet { defaults.set(menuBarStyles, forKey: Key.menuBarStyles) }
    }
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
        static let showAgentCount = "showAgentCount"
        static let showPercentages = "showPercentages"
        static let menuBarAgents = "menuBarAgents"
        static let maxMenuBarAgents = "maxMenuBarAgents"
        static let menuBarStyles = "menuBarStyles"
        static let percentSources = "percentSources"
        static let weeklyBudgets = "weeklyBudgets"
        static let dailyBudgets = "dailyBudgets"
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
        showAgentCount = defaults.object(forKey: Key.showAgentCount) as? Bool ?? true
        showPercentages = defaults.object(forKey: Key.showPercentages) as? Bool ?? true
        maxMenuBarAgents = defaults.object(forKey: Key.maxMenuBarAgents) as? Int ?? 2
        menuBarStyles = defaults.dictionary(forKey: Key.menuBarStyles) as? [String: String] ?? [:]
        percentSources = defaults.dictionary(forKey: Key.percentSources) as? [String: String] ?? [:]
        weeklyBudgets = defaults.dictionary(forKey: Key.weeklyBudgets) as? [String: Int] ?? [:]
        dailyBudgets = defaults.dictionary(forKey: Key.dailyBudgets) as? [String: Int] ?? [:]
        // Codex by default: it is the only agent that publishes a real limit.
        menuBarAgents = (defaults.array(forKey: Key.menuBarAgents) as? [String])?
            .compactMap(AgentID.init(rawValue:)) ?? [.codex]
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

    func isInMenuBar(_ agent: AgentID) -> Bool { menuBarAgents.contains(agent) }

    /// Adding beyond the cap drops the oldest, so the bar cannot silently grow
    /// past the width the user asked for.
    func setInMenuBar(_ agent: AgentID, _ included: Bool) {
        var list = menuBarAgents.filter { $0 != agent }
        if included {
            list.append(agent)
            if list.count > maxMenuBarAgents { list.removeFirst(list.count - maxMenuBarAgents) }
        }
        menuBarAgents = list
    }

    func menuBarBinding(for agent: AgentID) -> Binding<Bool> {
        Binding(get: { self.isInMenuBar(agent) }, set: { self.setInMenuBar(agent, $0) })
    }

    /// A single agent defaults to its number alone: with nothing to tell apart,
    /// a mark beside the Klipeo one is just clutter.
    func style(for agent: AgentID) -> MenuBarStyle {
        if let stored = menuBarStyles[agent.rawValue].flatMap(MenuBarStyle.init(rawValue:)) {
            return stored
        }
        return menuBarAgents.count > 1 ? .markAndPercent : .percentOnly
    }

    func setStyle(_ style: MenuBarStyle, for agent: AgentID) {
        menuBarStyles[agent.rawValue] = style.rawValue
    }

    func styleBinding(for agent: AgentID) -> Binding<MenuBarStyle> {
        Binding(get: { self.style(for: agent) }, set: { self.setStyle($0, for: agent) })
    }

    /// A vendor quota when the agent has one, otherwise the week against a
    /// budget, which is the figure people actually watch.
    func percentSource(for agent: AgentID) -> PercentSource {
        let available = PercentSource.available(for: agent)
        if let stored = percentSources[agent.rawValue].flatMap(PercentSource.init(rawValue:)),
           available.contains(stored) {
            return stored
        }
        return available.first ?? .context
    }

    func setPercentSource(_ source: PercentSource, for agent: AgentID) {
        percentSources[agent.rawValue] = source.rawValue
    }

    func percentSourceBinding(for agent: AgentID) -> Binding<PercentSource> {
        Binding(get: { self.percentSource(for: agent) }, set: { self.setPercentSource($0, for: agent) })
    }

    /// Budgets are held in millions of tokens, which is the scale these agents
    /// actually run at: a week of Claude here is ~186M.
    func budgetMillions(for agent: AgentID, weekly: Bool) -> Int {
        (weekly ? weeklyBudgets : dailyBudgets)[agent.rawValue] ?? (weekly ? 200 : 40)
    }

    func budgetBinding(for agent: AgentID, weekly: Bool) -> Binding<Int> {
        Binding(
            get: { self.budgetMillions(for: agent, weekly: weekly) },
            set: { value in
                if weekly { self.weeklyBudgets[agent.rawValue] = max(1, value) }
                else { self.dailyBudgets[agent.rawValue] = max(1, value) }
            }
        )
    }
}
