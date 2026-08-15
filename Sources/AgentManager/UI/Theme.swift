import SwiftUI

/// The Klipeo design tokens, transcribed from the web app's globals.css so the
/// two surfaces read as one product.
enum Theme {
    static let surface = Color(hex: 0x0E0E0D)
    static let accent = Color(hex: 0x0A84FF)
    static let accentLight = Color(hex: 0x64B5FF)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static let hairline = Color.white.opacity(0.07)

    /// `.klipeo-liquid-glass`: a faint diagonal sheen over near-black, with a
    /// one-pixel highlight along the top edge.

    /// StatusPill tones, matching the shared component's palette.
    enum Tone {
        case positive, warning, negative, neutral, quota

        var fill: Color {
            switch self {
            case .positive: return Color(hex: 0x022C22).opacity(0.6)
            case .warning: return Color(hex: 0x431407).opacity(0.6)
            case .negative: return Color(hex: 0x450A0A).opacity(0.6)
            case .neutral: return Color.white.opacity(0.04)
            case .quota: return Color(hex: 0x082F49).opacity(0.6)
            }
        }

        var stroke: Color {
            switch self {
            case .positive: return Color(hex: 0x6EE7B7).opacity(0.15)
            case .warning: return Color(hex: 0xFDBA74).opacity(0.15)
            case .negative: return Color(hex: 0xFCA5A5).opacity(0.15)
            case .neutral: return Color.white.opacity(0.10)
            case .quota: return Color(hex: 0x7DD3FC).opacity(0.15)
            }
        }

        var text: Color {
            switch self {
            case .positive: return Color(hex: 0x6EE7B7)
            case .warning: return Color(hex: 0xFDBA74)
            case .negative: return Color(hex: 0xFCA5A5)
            case .neutral: return Color.white.opacity(0.75)
            case .quota: return Color(hex: 0x7DD3FC)
            }
        }
    }
}

extension View {
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Bricolage Grotesque is bundled because it is not a system face. If the
/// resource is missing the app falls back to the system font rather than
/// failing to draw.
enum BrandFont {
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        registerIfNeeded()
        return available
            ? .custom("BricolageGrotesque-Regular", size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    private nonisolated(unsafe) static var available = false
    private nonisolated(unsafe) static var registered = false

    private static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.module.url(forResource: "BricolageGrotesque-Regular", withExtension: "ttf") else { return }
        available = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
