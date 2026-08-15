import SwiftUI

/// One terminal, not one agent. Four Codex sessions in four terminals are four
/// tiles, each with its own branch, activity and subagents.
struct SessionRowView: View {
    let agent: AgentID
    let session: RunningSession
    let isInspecting: Bool
    let onInspect: () -> Void

    @State private var hovered = false

    private var working: Bool { session.activity.isWorking }
    private var activeSubAgents: Int { session.subAgents.filter(\.isWorking).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                IconWell(agent: agent, lit: working)

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName)
                        .font(BrandFont.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(working ? session.activityLine : "idle · \(idleFor)")
                        .font(BrandFont.body(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                StatusPill(
                    text: working ? "working" : "open",
                    tone: working ? .positive : .neutral,
                    showsDot: working
                )
            }

            metadata

            if !session.subAgents.isEmpty { subAgentToggle }
        }
        .padding(14)
        .glassTile(radius: 18, highlighted: hovered || isInspecting)
        .onHover { hovered = $0 }
    }

    /// Branch, working directory and pid, set in monospace because they are
    /// identifiers rather than prose.
    private var metadata: some View {
        HStack(spacing: 9) {
            if let branch = session.branch {
                Chip(icon: "arrow.triangle.branch", text: branch)
            }
            if let repo = session.cwd.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
                Chip(icon: "folder", text: repo)
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(session.pid)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.top, 10)
    }

    private var subAgentToggle: some View {
        Button(action: onInspect) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(isInspecting ? 0.9 : 0.45))
                Text("sub-agents")
                    .font(BrandFont.body(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(verbatim: "\(session.subAgents.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                if activeSubAgents > 0 {
                    StatusPill(text: "\(activeSubAgents) active", tone: .positive, showsDot: true)
                        .scaleEffect(0.88, anchor: .leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 11)
    }

    private var idleFor: String {
        guard case .idle(let since) = session.activity, let since else { return "no recent activity" }
        return QuotaBar.ago(since)
    }
}

/// A small monospace chip for a branch or directory.
private struct Chip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8.5))
            Text(text).font(.system(size: 10, design: .monospaced)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
        .clipShape(Capsule())
    }
}

/// A subagent: its task, its branch, and whether it is still going.
struct SubAgentRow: View {
    let subAgent: SubAgent

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(subAgent.isWorking ? StatusPill.Tone.positive.dot : Color.white.opacity(0.2))
                .frame(width: 5, height: 5)
                .shadow(color: subAgent.isWorking ? StatusPill.Tone.positive.dot.opacity(0.8) : .clear, radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(subAgent.label)
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(subAgent.isWorking ? 0.9 : 0.55))
                    .lineLimit(1)
                if let branch = subAgent.branch {
                    Text(branch)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(subAgent.lastWrite.map { QuotaBar.ago($0) } ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.6)
        )
    }
}

/// The circular icon well Control Center uses: a disc that lights up when the
/// thing it represents is active.
struct IconWell: View {
    let agent: AgentID
    var lit: Bool

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(lit ? Color.white.opacity(0.95) : Color.white.opacity(0.07))
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(lit ? 0.5 : 0.22), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.7
            )
            AgentLogo(agent: agent, inverted: lit).frame(width: 16, height: 16)
        }
        .frame(width: 30, height: 30)
    }
}
