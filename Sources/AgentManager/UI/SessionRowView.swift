import SwiftUI

/// One terminal, not one agent. Four Codex sessions in four terminals are four
/// rows, each with its own branch, activity and subagents.
struct SessionRowView: View {
    let agent: AgentID
    let session: RunningSession
    let quota: Quota?
    let quotaObserved: Date?

    @ObservedObject private var prefs = Preferences.shared
    @State private var expanded = RenderMode.isOffscreen
    @State private var hovered = false

    private var working: Bool { session.activity.isWorking }
    private var activeSubAgents: Int { session.subAgents.filter(\.isWorking).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                IconChip(agent: agent, lit: working)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(agent.displayName)
                            .font(BrandFont.body(12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(verbatim: "pid \(session.pid)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text(working ? session.activityLine : "idle · \(idleFor)")
                        .font(BrandFont.body(10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                StatusChip(text: working ? "working" : "open", tone: working ? .positive : .neutral, pulsing: working)
            }

            metadata

            if !session.subAgents.isEmpty {
                subAgentToggle
                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(session.subAgents) { SubAgentRow(subAgent: $0) }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let quota {
                QuotaBar(quota: quota, observed: quotaObserved, warn: prefs.warnThreshold, critical: prefs.criticalThreshold)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.15 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.16), value: expanded)
    }

    /// Branch and directory, set in monospace because they are code, not prose.
    @ViewBuilder private var metadata: some View {
        let repo = session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        if session.branch != nil || repo != nil {
            HStack(spacing: 10) {
                if let branch = session.branch {
                    Label {
                        Text(branch).font(.system(size: 10, design: .monospaced))
                    } icon: {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                }
                if let repo {
                    Label {
                        Text(repo).font(.system(size: 10, design: .monospaced))
                    } icon: {
                        Image(systemName: "folder").font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 5)
            .padding(.leading, 35)
        }
    }

    private var subAgentToggle: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text("sub-agents")
                    .font(BrandFont.body(11, weight: .medium))
                Text("\(session.subAgents.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                if activeSubAgents > 0 {
                    Text("\(activeSubAgents) active")
                        .font(BrandFont.body(10))
                        .foregroundStyle(Theme.Tone.positive.text)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.leading, 35)
    }

    private var idleFor: String {
        guard case .idle(let since) = session.activity, let since else { return "no recent activity" }
        return QuotaBar.ago(since)
    }
}

/// A subagent line: its task, its branch, and whether it is still going.
struct SubAgentRow: View {
    let subAgent: SubAgent

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(subAgent.isWorking ? Theme.Tone.positive.text : Color.white.opacity(0.22))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(subAgent.label)
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(subAgent.isWorking ? 0.85 : 0.5))
                    .lineLimit(1)
                if let branch = subAgent.branch {
                    Text(branch)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text(subAgent.lastWrite.map { QuotaBar.ago($0) } ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.07)))
        .padding(.leading, 35)
    }
}
