import SwiftUI

/// The glass primitives.
///
/// Flat white fills over a blur cannot look like glass: what sells it is the
/// material actually sampling what is behind, plus a rim that is bright along
/// the top edge and fades toward the bottom, the way a lit pane of glass reads.
struct GlassTile: ViewModifier {
    var radius: CGFloat = 20
    var highlighted = false
    /// Tiles that respond to a click ask for the material's own pointer
    /// reaction rather than a hand-rolled hover fill.
    var interactive = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !RenderMode.isOffscreen {
            content.glassEffect(
                interactive
                    ? .regular.tint(.white.opacity(highlighted ? 0.10 : 0.03)).interactive()
                    : .regular.tint(.white.opacity(highlighted ? 0.10 : 0.03)),
                in: .rect(cornerRadius: radius)
            )
        } else {
            legacy(content)
        }
    }

    /// Pre-26 fallback: material plus a hand-painted rim, which is the closest
    /// approximation available without the real material.
    private func legacy(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlighted ? 0.14 : 0.07),
                                Color.white.opacity(highlighted ? 0.05 : 0.015),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                // The rim light. Bright where the light hits, nearly gone below.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }
}

extension View {
    func glassTile(radius: CGFloat = 20, highlighted: Bool = false, interactive: Bool = true) -> some View {
        modifier(GlassTile(radius: radius, highlighted: highlighted, interactive: interactive))
    }

    /// Real glass for a capsule, so pills and chips get the same treatment as
    /// tiles rather than a painted-on approximation.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *), !RenderMode.isOffscreen {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                self.glassEffect(.regular, in: .capsule)
            }
        } else {
            self.background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(tint ?? .clear))
            )
        }
    }

    /// Groups adjacent glass so shapes merge and share refraction the way
    /// Apple's own controls do, rather than reading as separate panes.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *), !RenderMode.isOffscreen {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// The Klipeo StatusPill, transcribed exactly: a tonal capsule with white text,
/// a hairline tinted border, a light top edge and a soft shadow pooling at the
/// bottom. The colour carries the meaning; the text stays white.
struct StatusPill: View {
    enum Tone {
        case positive, negative, warning, neutral, credits

        /// emerald-950/60, red-950/60, orange-950/60, white/[0.04], sky-950/60
        var fill: Color {
            switch self {
            case .positive: return Color(red: 0.008, green: 0.173, blue: 0.133).opacity(0.60)
            case .negative: return Color(red: 0.271, green: 0.039, blue: 0.039).opacity(0.60)
            case .warning: return Color(red: 0.263, green: 0.078, blue: 0.027).opacity(0.60)
            case .neutral: return Color.white.opacity(0.04)
            case .credits: return Color(red: 0.031, green: 0.184, blue: 0.286).opacity(0.60)
            }
        }

        /// emerald-300/15 and friends
        var border: Color {
            switch self {
            case .positive: return Color(red: 0.431, green: 0.906, blue: 0.718).opacity(0.15)
            case .negative: return Color(red: 0.988, green: 0.647, blue: 0.647).opacity(0.15)
            case .warning: return Color(red: 0.992, green: 0.729, blue: 0.455).opacity(0.15)
            case .neutral: return Color.white.opacity(0.10)
            case .credits: return Color(red: 0.490, green: 0.827, blue: 0.988).opacity(0.15)
            }
        }

        /// inset 0 1px 0 rgba(...)
        var topHighlight: Color {
            switch self {
            case .positive: return Color(red: 0.525, green: 0.937, blue: 0.675).opacity(0.12)
            case .negative: return Color(red: 0.988, green: 0.647, blue: 0.647).opacity(0.12)
            case .warning: return Color(red: 0.992, green: 0.729, blue: 0.455).opacity(0.12)
            case .neutral: return Color.white.opacity(0.08)
            case .credits: return Color(red: 0.490, green: 0.827, blue: 0.988).opacity(0.14)
            }
        }

        var dot: Color {
            switch self {
            case .positive: return Color(red: 0.204, green: 0.827, blue: 0.600)
            case .negative: return Color(red: 0.973, green: 0.443, blue: 0.443)
            case .warning: return Color(red: 0.984, green: 0.573, blue: 0.235)
            case .neutral: return Color.white.opacity(0.45)
            case .credits: return Color(red: 0.220, green: 0.741, blue: 0.973)
            }
        }
    }

    let text: String
    let tone: Tone
    var showsDot = false
    /// Breathing halo, for a state that is genuinely still moving.
    var pulses = false

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                StatusDot(color: tone.dot, pulses: pulses)
            }
            Text(text)
                .font(BrandFont.body(10.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .frame(height: 21)
        .glassCapsule(tint: tone.fill)
        .overlay(Capsule().strokeBorder(tone.border, lineWidth: 0.8))
    }
}

/// The state dot.
///
/// A flat filled circle reads as a debug marker. Depth is what makes it look
/// deliberate: a diffuse halo the colour bleeds into, a saturated core, and a
/// specular highlight offset toward the top left so it reads as a lit bead
/// rather than a printed dot.
struct StatusDot: View {
    let color: Color
    var pulses = false
    var size: CGFloat = 7

    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.32))
                .frame(width: size * 2.3, height: size * 2.3)
                .blur(radius: size * 0.55)
                .scaleEffect(breathing ? 1.18 : 0.86)
                .opacity(breathing ? 1 : 0.55)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.95), color],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.75))
                        .frame(width: size * 0.3, height: size * 0.3)
                        .blur(radius: 0.4)
                        .offset(x: size * 0.2, y: size * 0.16)
                }
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.7), radius: size * 0.5)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard pulses, !RenderMode.isOffscreen else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

extension View {
    /// The selected tab, as a glass capsule rather than a painted one so it
    /// picks up whatever is behind the panel.
    @ViewBuilder
    func glassTab(selected: Bool) -> some View {
        if selected {
            glassCapsule(tint: .white.opacity(0.10))
                .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.7))
        } else {
            self
        }
    }
}
