import SwiftUI

/// One tool, collapsed to a single tile.
///
/// Four Codex terminals used to mean four full-height tiles saying almost the
/// same thing. They stack into one row carrying the account-level numbers, and
/// the individual terminals appear only when asked for.
struct AgentGroupView: View {
    let group: AgentGroup
    @Binding var inspecting: Int32?
    /// Owned by the panel: these rows are rebuilt on every refresh, so any
    /// state they held would be thrown away mid-interaction.
    @Binding var detail: DetailTarget?
    @ObservedObject private var prefs = Preferences.shared
    @State private var hovered = false

    private var expanded: Bool { detail == .sessions(group.agent) }

    private func toggleExpanded() {
        detail = expanded ? nil : .sessions(group.agent)
    }

    private var working: Int { group.sessions.filter { $0.activity.isWorking }.count }
    private var isSingle: Bool { group.sessions.count == 1 }
    private var totalSubAgents: Int { group.sessions.reduce(0) { $0 + $1.subAgents.count } }

    var body: some View {
        if isSingle, let only = group.sessions.first {
            // A lone session has nothing to stack, so it is shown directly.
            SessionRowView(
                agent: group.agent,
                session: only,
                quota: group.quota,
                quotaObserved: group.quotaObserved,
                usage: group.usage,
                usageToday: group.usageToday,
                isInspecting: detail == .subAgents(pid: only.pid),
                onInspect: { detail = detail == .subAgents(pid: only.pid) ? nil : .subAgents(pid: only.pid) }
            )
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 11) {
                    StackedIcons(agent: group.agent, count: group.sessions.count, lit: working > 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.agent.displayName)
                            .font(BrandFont.body(13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(summary)
                            .font(BrandFont.body(11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if working > 0 {
                        StatusPill(text: "\(working) working", tone: .positive, showsDot: true)
                    } else {
                        StatusPill(text: "\(group.sessions.count) open", tone: .neutral)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(expanded ? 0.75 : 0.35))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 14)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let quota = group.quota {
                QuotaBar(
                    quota: quota,
                    observed: group.quotaObserved,
                    warn: prefs.warnThreshold,
                    critical: prefs.criticalThreshold
                )
                .padding(.top, 11)
                WindowLine(
                    today: group.usageToday,
                    week: group.usage,
                    includeCacheReads: prefs.includeCacheReads
                )
                .padding(.top, 8)
            } else {
                WindowLine(
                    today: group.usageToday,
                    week: group.usage,
                    includeCacheReads: prefs.includeCacheReads
                )
                .padding(.top, 10)
            }

            if !expanded {
                SessionStrip(sessions: group.sessions)
                    .padding(.top, 10)
            }

        }
        .padding(14)
        .glassTile(radius: 18, highlighted: hovered || expanded)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.18), value: expanded)
    }

    /// What the stack is doing, without having to open it.
    private var summary: String {
        let places = Set(group.sessions.compactMap { $0.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } })
        let where_ = places.count == 1 ? places.first! : "\(places.count) repos"
        if totalSubAgents > 0 {
            return "\(where_) · \(totalSubAgents) sub-agents"
        }
        return where_
    }
}

/// Overlapping discs, the way stacked cards read, with the count on top.
struct StackedIcons: View {
    let agent: AgentID
    let count: Int
    let lit: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<min(count, 3), id: \.self) { index in
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6))
                    .frame(width: 30, height: 30)
                    .offset(x: CGFloat(min(count, 3) - 1 - index) * 5)
                    .opacity(index == 0 ? 1 : 0.55)
            }
            IconWell(agent: agent, lit: lit)
        }
        .frame(width: 30 + CGFloat(min(count, 3) - 1) * 5, alignment: .leading)
    }
}

/// Both windows on one line, today on the left and the week on the right.
///
/// These tools publish no limit, so what is shown is what was consumed inside
/// each rolling window, counted locally, and it says so.
struct WindowLine: View {
    let today: Usage?
    let week: Usage?
    let includeCacheReads: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            side(label: "today", usage: today, resets: midnightCountdown)
            Spacer(minLength: 10)
            side(label: "7 days", usage: week, resets: "rolling", trailing: true)
        }
        .font(BrandFont.body(10))
    }

    private func side(label: String, usage: Usage?, resets: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.white.opacity(0.38))
                Text(format(usage)).foregroundStyle(.white.opacity(0.82))
            }
            Text(resets)
                .font(BrandFont.body(9))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    /// Today's window turns over at local midnight.
    private var midnightCountdown: String {
        let calendar = Calendar.current
        guard let next = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) else { return "resets at midnight" }
        return "resets \(QuotaBar.countdown(to: next))"
    }

    private func format(_ usage: Usage?) -> String {
        guard let usage else { return "–" }
        let value = usage.total(includingCacheReads: includeCacheReads)
        switch value {
        case 1_000_000...: return String(format: "%.1fM tokens", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.0fK tokens", Double(value) / 1_000)
        default: return "\(value) tokens"
        }
    }
}

/// A one-line preview of what is inside a collapsed stack: a pip per session,
/// lit when that session is working, plus where they are running.
struct SessionStrip: View {
    let sessions: [RunningSession]

    private var places: [String] {
        Array(Set(sessions.compactMap { $0.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } })).sorted()
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(sessions) { session in
                    Capsule()
                        .fill(session.activity.isWorking
                              ? StatusPill.Tone.positive.dot
                              : Color.white.opacity(0.22))
                        .frame(width: session.activity.isWorking ? 14 : 8, height: 4)
                }
            }
            ForEach(places.prefix(2), id: \.self) { place in
                Text(place)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
            if places.count > 2 {
                Text("+\(places.count - 2)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
            }
            Spacer(minLength: 0)
        }
    }
}
