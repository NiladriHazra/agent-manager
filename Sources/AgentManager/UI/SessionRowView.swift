import SwiftUI

/// One terminal, not one agent. Four Codex sessions in four terminals are four
/// tiles, each with its own branch, activity and subagents.
struct SessionRowView: View {
    let agent: AgentID
    let session: RunningSession
    let quota: Quota?
    let quotaObserved: Date?
    let usage: Usage?
    let usageToday: Usage?
    let isInspecting: Bool
    let onInspect: () -> Void

    @ObservedObject private var prefs = Preferences.shared
    private var working: Bool { session.activity.isWorking }
    private var activeSubAgents: Int { session.subAgents.filter(\.isWorking).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                IconWell(agent: agent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.displayName)
                        .font(BrandFont.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(secondary)
                        .font(BrandFont.body(11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                StatusPill(text: state.text, tone: state.tone, indicator: state.indicator)
            }

            if prefs.isEnabled(.branch, for: agent) { metadata }

            // Token totals are per account, not per terminal. The side panel
            // lists individual sessions, so it passes none — and an empty bar
            // full of dashes is worse than no bar.
            if showsWindows, quota != nil || usage != nil || usageToday != nil {
                UsagePanel(
                    agent: agent,
                    quota: quota,
                    quotaObserved: quotaObserved,
                    usage: usage,
                    usageToday: usageToday,
                    includeCacheReads: prefs.includeCacheReads,
                    warn: prefs.warnThreshold,
                    critical: prefs.criticalThreshold
                )
                .padding(.top, 9)
            }

            if let chat = visibleChat {
                ChatLine(chat: chat, tint: LogoTint.color(for: agent))
                    .padding(.top, 9)
            }

            if !session.subAgents.isEmpty, prefs.isEnabled(.subAgents, for: agent) { subAgentToggle }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassTile(radius: 16, highlighted: isInspecting)
        // The row is the control: clicking it raises the terminal that owns
        // this session, so a listed session is always reachable.
        .contentShape(Rectangle())
        .onTapGesture {
            guard session.canFocus else { return }
            TerminalFocus.focus(pid: session.pid, tty: session.tty)
        }
        .help(session.canFocus ? "Show this session's terminal" : "")
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
        .padding(.top, 8)
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
                    StatusPill(text: "\(activeSubAgents) active", tone: .positive, indicator: .typing)
                        .scaleEffect(0.88, anchor: .leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var showsWindows: Bool { prefs.isEnabled(.windows, for: agent) }

    /// The chat block honours three separate switches, so a row can show its
    /// context bar without its token line, or neither.
    private var visibleChat: ChatStats? {
        guard var chat = session.chat else { return nil }
        if !prefs.isEnabled(.context, for: agent) { chat.contextTokens = 0 }
        if !prefs.isEnabled(.chatTokens, for: agent) {
            chat.input = 0; chat.output = 0; chat.cacheCreate = 0; chat.thinking = 0
        }
        if !prefs.isEnabled(.cost, for: agent) { chat.cost = nil }
        if !prefs.isEnabled(.model, for: agent) { chat.model = nil }
        guard chat.contextTokens > 0 || chat.output > 0 || (chat.cost ?? 0) > 0 else { return nil }
        return chat
    }

    private var state: (text: String, tone: StatusPill.Tone, indicator: StatusPill.Indicator) {
        switch session.activity {
        case .working: return ("running", .positive, .typing)
        case .waiting: return ("waiting", .warning, .shimmer)
        case .idle: return ("open", .neutral, .none)
        }
    }

    private var secondary: String {
        switch session.activity {
        case .working: return session.activityLine
        case .waiting: return "asked for your reply · \(idleFor)"
        case .idle: return "idle · \(idleFor)"
        }
    }

    private var idleFor: String {
        guard let since = session.activity.since else { return "no recent activity" }
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
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
///
/// These are the smallest rows in the app, so they carry only what separates
/// one from another: the task, where it is running, and how long ago it last
/// wrote. Everything else would be noise at this size.
struct SubAgentRow: View {
    let subAgent: SubAgent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WaveLoader(
                color: subAgent.isWorking ? StatusPill.Tone.positive.dot : .white.opacity(0.38),
                animated: subAgent.isWorking
            )
            .padding(.top, 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(subAgent.label)
                    .font(BrandFont.body(11.5, weight: subAgent.isWorking ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(subAgent.isWorking ? 1 : 0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if let branch = subAgent.branch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 7.5))
                            Text(branch)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.white.opacity(0.42))
                    }
                    Spacer(minLength: 4)
                    Text(subAgent.lastWrite.map { QuotaBar.ago($0) } ?? "")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(subAgent.isWorking ? 0.6 : 0.3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .glassTile(radius: 14, highlighted: subAgent.isWorking)
    }
}

/// The circular icon well Control Center uses.
///
/// One appearance, always. It used to invert to a white disc while a session
/// was working, so the same agent looked like two different marks depending on
/// which tab you were on. State is the pill's job, not the logo's.
struct IconWell: View {
    let agent: AgentID
    /// The chrome rim belongs to the disc in front. Repeating it on the discs
    /// behind a stack turns three clean edges into one smeared one.
    var bezel = true
    var size: CGFloat = 30

    var body: some View {
        // The mark goes in an overlay, not behind: Liquid Glass composites
        // above whatever it is applied to, which hid the logo entirely.
        Circle()
            // Opaque, not translucent: in a stack a see-through well let the
            // disc behind bleed through and both logos turned to mush.
            .fill(Theme.surface)
            .overlay(Circle().fill(Color.white.opacity(0.06)))
            .overlay {
                // Brushed-chrome bezel: a bright arc where the light lands, a
                // dark one opposite, and a faint spectral split between them.
                bezel ? AnyView(Circle().strokeBorder(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.08),
                            Color(red: 0.62, green: 0.78, blue: 1.0).opacity(0.4),
                            .white.opacity(0.05),
                            Color(red: 1.0, green: 0.82, blue: 0.72).opacity(0.32),
                            .white.opacity(0.5),
                        ],
                        center: .center,
                        angle: .degrees(-58)
                    ),
                    lineWidth: 1.1
                )) : AnyView(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
            }
            .overlay {
                AgentLogo(agent: agent)
                    .frame(width: size * 0.53, height: size * 0.53)
            }
            .frame(width: size, height: size)
    }
}
