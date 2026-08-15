import Foundation

/// How one agent presents itself in the menu bar.
///
/// Per agent rather than global: a quota you watch closely earns its number,
/// while a second agent you only glance at may be better as a mark alone.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case markAndPercent
    case markOnly
    case percentOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markAndPercent: return "Icon + %"
        case .markOnly: return "Icon only"
        case .percentOnly: return "% only"
        }
    }

    var showsMark: Bool { self != .percentOnly }
    var showsPercent: Bool { self != .markOnly }
}
