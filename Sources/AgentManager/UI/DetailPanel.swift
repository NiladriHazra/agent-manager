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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // An explicit height, not a maximum: a ScrollView given only a
            // maximum collapses to nothing inside MenuBarExtra's window.
            if RenderMode.isOffscreen {
                rows.padding(.horizontal, 11).padding(.bottom, 11)
            } else {
                ScrollView {
                    rows.padding(.horizontal, 11).padding(.bottom, 11)
                }
                .frame(height: min(CGFloat(count) * 78 + 16, maxHeight))
            }
        }
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
                StatusPill(text: "\(activeCount) active", tone: .positive, showsDot: true)
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
        .padding(.top, 12)
        .padding(.bottom, 9)
    }
}
