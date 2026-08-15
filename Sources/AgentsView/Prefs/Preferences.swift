import Combine
import Foundation

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
    @Published var showIdleAgents: Bool { didSet { defaults.set(showIdleAgents, forKey: Key.showIdleAgents) } }
    @Published var hiddenAgents: Set<AgentID> {
        didSet { defaults.set(hiddenAgents.map(\.rawValue).sorted(), forKey: Key.hiddenAgents) }
    }

    private enum Key {
        static let menuBarMode = "menuBarMode"
        static let refreshSeconds = "refreshSeconds"
        static let warnThreshold = "warnThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let includeCacheReads = "includeCacheReads"
        static let hideNotInstalled = "hideNotInstalled"
        static let showIdleAgents = "showIdleAgents"
        static let hiddenAgents = "hiddenAgents"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMode = (defaults.string(forKey: Key.menuBarMode)
            .flatMap(MenuBarMode.init(rawValue:))) ?? .countAndQuota
        refreshSeconds = defaults.object(forKey: Key.refreshSeconds) as? Int ?? 60
        warnThreshold = defaults.object(forKey: Key.warnThreshold) as? Int ?? 20
        criticalThreshold = defaults.object(forKey: Key.criticalThreshold) as? Int ?? 10
        includeCacheReads = defaults.bool(forKey: Key.includeCacheReads)
        hideNotInstalled = defaults.object(forKey: Key.hideNotInstalled) as? Bool ?? true
        showIdleAgents = defaults.bool(forKey: Key.showIdleAgents)
        hiddenAgents = Set(
            (defaults.stringArray(forKey: Key.hiddenAgents) ?? []).compactMap(AgentID.init(rawValue:))
        )
    }

    func isHidden(_ agent: AgentID) -> Bool { hiddenAgents.contains(agent) }

    func setHidden(_ agent: AgentID, _ hidden: Bool) {
        if hidden { hiddenAgents.insert(agent) } else { hiddenAgents.remove(agent) }
    }
}
