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

/// Everything the settings window writes. Backed by UserDefaults so it survives
/// relaunches without any storage code of our own.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("menuBarMode") var menuBarMode: MenuBarMode = .countAndQuota
    @AppStorage("refreshSeconds") var refreshSeconds: Int = 60
    @AppStorage("warnThreshold") var warnThreshold: Int = 20
    @AppStorage("criticalThreshold") var criticalThreshold: Int = 10
    @AppStorage("includeCacheReads") var includeCacheReads: Bool = false
    @AppStorage("hideNotInstalled") var hideNotInstalled: Bool = true
    @AppStorage("hiddenAgents") private var hiddenAgentsRaw: String = ""

    var hiddenAgents: Set<AgentID> {
        get { Set(hiddenAgentsRaw.split(separator: ",").compactMap { AgentID(rawValue: String($0)) }) }
        set { hiddenAgentsRaw = newValue.map(\.rawValue).sorted().joined(separator: ",") }
    }

    func isHidden(_ agent: AgentID) -> Bool { hiddenAgents.contains(agent) }

    func setHidden(_ agent: AgentID, _ hidden: Bool) {
        var current = hiddenAgents
        if hidden { current.insert(agent) } else { current.remove(agent) }
        hiddenAgents = current
        objectWillChange.send()
    }
}
