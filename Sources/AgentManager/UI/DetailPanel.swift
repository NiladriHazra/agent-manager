import SwiftUI

/// What the right-hand column is showing.
///
/// Both kinds of drill-down open sideways rather than pushing the list taller:
/// a stack of terminals, or one terminal's subagents.
enum DetailTarget: Equatable {
    case sessions(AgentID)
    case subAgents(pid: Int32)
}

struct DetailPanel: View {
    let title: String
    let count: Int
    let activeCount: Int
    let onClose: () -> Void
    let rows: AnyView

    private let maxHeight: CGFloat = 420
    private let fade: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // An explicit height, not a maximum: a ScrollView given only a
            // maximum collapses to nothing inside MenuBarExtra's window.
            if RenderMode.isOffscreen {
                rows.padding(.horizontal, 11).padding(.bottom, 11)
            } else {
                ScrollView {
                    rows
                        .padding(.horizontal, 11)
                        // Room for the fade to eat into, so the first and last
                        // rows are never cut mid-tile at rest.
                        .padding(.vertical, fade)
                }
                .frame(height: min(CGFloat(count) * 74 + fade * 2, maxHeight))
                .mask(scrollFade)
                .scrollIndicators(.never)
            }
        }
    }

    /// Content dissolves at both ends instead of being sliced off, so a list
    /// longer than the panel reads as continuing rather than truncated.
    private var scrollFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.055),
                .init(color: .black, location: 0.945),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(BrandFont.body(13, weight: .bold))
                .foregroundStyle(.white)
            Text(verbatim: "\(count)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .glassCapsule(tint: .white.opacity(0.08))

            Spacer()

            if activeCount > 0 {
                StatusPill(text: "\(activeCount) active", tone: .positive, indicator: .typing)
                    .scaleEffect(0.9, anchor: .trailing)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .glassCapsule(tint: .white.opacity(0.06))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
