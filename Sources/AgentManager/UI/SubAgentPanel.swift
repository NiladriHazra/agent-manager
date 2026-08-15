import SwiftUI

/// Subagents open beside the list rather than inside it. A session with 13 of
/// them would otherwise push the panel taller than the screen.
struct SubAgentPanel: View {
    let session: RunningSession
    let onClose: () -> Void

    private var active: Int { session.subAgents.filter(\.isWorking).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // An explicit height, not a maximum: a ScrollView with only a
            // maximum collapses to nothing inside MenuBarExtra's window. It
            // also refuses to lay out offscreen, so snapshots use a plain stack.
            if RenderMode.isOffscreen {
                VStack(spacing: 5) {
                    ForEach(session.subAgents) { SubAgentRow(subAgent: $0) }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(session.subAgents) { SubAgentRow(subAgent: $0) }
                    }
                    .padding(.horizontal, 11)
                    .padding(.bottom, 11)
                }
                .frame(height: min(CGFloat(session.subAgents.count) * 48 + 14, 420))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("Sub-agents")
                .font(BrandFont.body(12, weight: .semibold))
                .foregroundStyle(.white)
            Text(verbatim: "\(session.subAgents.count)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 5)
                .frame(height: 15)
                .background(Capsule().fill(Color.white.opacity(0.10)))

            Spacer()

            if active > 0 {
                StatusPill(text: "\(active) active", tone: .positive, showsDot: true)
                    .scaleEffect(0.9, anchor: .trailing)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }
}
