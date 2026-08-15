import SwiftUI

/// One tool, collapsed to a single tile.
///
/// Four Codex terminals used to mean four full-height tiles saying almost the
/// same thing. They stack into one row carrying the account-level numbers, and
/// the individual terminals appear only when asked for.
struct AgentGroupView: View {
    let group: AgentGroup
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
                    StackedIcons(agent: group.agent, count: group.sessions.count)

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

        }
        .padding(14)
        .glassTile(radius: 18, highlighted: hovered || expanded, interactive: true)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.18), value: expanded)
    }

    /// What the stack is doing, without having to open it.
    private var summary: String {
        let places = Set(group.sessions.compactMap { $0.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } })
        let where_ = places.count == 1 ? (places.first ?? "") : "\(places.count) repos"
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

    private var depth: Int { min(count, 3) }

    var body: some View {
        ZStack(alignment: .leading) {
            // Every disc carries the same mark and every disc is opaque, so the
            // one in front hides the middle of the one behind and you see a
            // stack of real logos rather than one logo on blank coins.
            ForEach(1..<max(depth, 1), id: \.self) { index in
                IconWell(agent: agent, size: 30)
                    .offset(x: CGFloat(index) * 9)
                    .zIndex(-Double(index))
            }
            IconWell(agent: agent)
                .zIndex(1)
        }
        .frame(width: 30 + CGFloat(depth - 1) * 9, alignment: .leading)
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
            side(label: "7 days", usage: week, resets: rollingWindow, trailing: true)
        }
        .font(BrandFont.body(10))
    }

    private func side(label: String, usage: Usage?, resets: Text, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.white.opacity(0.38))
                // The number is the reason this line exists, so it is the only
                // thing here at full weight and full white.
                Text(format(usage))
                    .font(BrandFont.body(11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            resets
                .font(BrandFont.body(9))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    /// A rolling window has no reset instant, so it states the span it covers
    /// instead of pretending to count down to one.
    private var rollingWindow: Text {
        // Text formats this itself; a DateFormatter built in body is one of the
        // most expensive objects Foundation has, and body runs every refresh.
        Text("since \(Date.now.addingTimeInterval(-7 * 86_400), format: .dateTime.day().month(.abbreviated)), rolling")
    }

    /// Today's window turns over at local midnight.
    private var midnightCountdown: Text {
        let calendar = Calendar.current
        guard let next = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) else { return Text("resets at midnight") }
        return Text("resets \(QuotaBar.countdown(to: next))")
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

