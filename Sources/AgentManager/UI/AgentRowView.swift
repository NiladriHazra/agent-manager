import SwiftUI

/// A Control Center tile: a circular icon chip, a two-line label, and a status
/// on the right. Working tiles are filled and lit; idle ones stay quiet.
struct AgentRowView: View {
    let snapshot: AgentSnapshot
    @ObservedObject private var prefs = Preferences.shared
    @State private var hovered = false

    private var isWorking: Bool { snapshot.isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconChip(agent: snapshot.agent, lit: isWorking)

                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.agent.displayName)
                        .font(BrandFont.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                    subtitle
                }

                Spacer(minLength: 6)
                trailing
            }

            if let quota = snapshot.quota {
                QuotaBar(
                    quota: quota,
                    observed: snapshot.quotaObserved,
                    warn: prefs.warnThreshold,
                    critical: prefs.criticalThreshold
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.14 : 0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var subtitle: some View {
        switch snapshot.availability {
        case .loading:
            label("reading…")
        case .notInstalled:
            label("not installed")
        case .unavailable(let reason):
            label(reason)
        case .ready:
            if let session = snapshot.workingSessions.first ?? snapshot.sessions.first {
                label(session.activity.isWorking
                    ? session.activityLine
                    : "idle · \(Self.since(session.activity))")
            } else if let usage = snapshot.usage {
                label("\(formatTokens(usage.total(includingCacheReads: prefs.includeCacheReads))) this week · usage")
            } else {
                label("idle")
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.body(11))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
    }

    @ViewBuilder private var trailing: some View {
        if isWorking {
            StatusChip(
                text: snapshot.workingSessions.count > 1
                    ? "\(snapshot.workingSessions.count) working"
                    : "working",
                tone: .positive,
                pulsing: true
            )
        } else if snapshot.isRunning {
            StatusChip(
                text: snapshot.sessions.count > 1 ? "\(snapshot.sessions.count) open" : "open",
                tone: .neutral,
                pulsing: false
            )
        } else if let credits = snapshot.credits {
            StatusChip(text: "\(credits) cr", tone: .quota, pulsing: false)
        }
    }

    private static func since(_ activity: Activity) -> String {
        guard case .idle(let date) = activity, let date else { return "no recent activity" }
        return QuotaBar.ago(date)
    }

    private func formatTokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

/// The circular icon well Control Center uses: a filled disc that lights up
/// when the thing it represents is active.
struct IconChip: View {
    let agent: AgentID
    var lit: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(lit ? Color.white.opacity(0.92) : Color.white.opacity(0.11))
            AgentLogo(agent: agent, inverted: lit)
                .frame(width: 19, height: 19)
        }
        .frame(width: 36, height: 36)
    }
}

struct StatusChip: View {
    let text: String
    let tone: Theme.Tone
    var pulsing: Bool

    @State private var breathing = false

    var body: some View {
        HStack(spacing: 5) {
            if pulsing {
                Circle()
                    .fill(tone.text)
                    .frame(width: 5, height: 5)
                    .opacity(breathing ? 0.3 : 1)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathing)
                    .onAppear { breathing = true }
            }
            Text(text)
        }
        .font(BrandFont.body(10, weight: .medium))
        .foregroundStyle(tone.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tone.fill))
        .overlay(Capsule().strokeBorder(tone.stroke, lineWidth: 0.5))
    }
}

/// The vendor's own mark. AppKit rasterizes the bundled SVGs directly. Marks
/// are inverted on a lit chip so a white logo stays legible on white.
struct AgentLogo: View {
    let agent: AgentID
    var inverted = false

    var body: some View {
        Group {
            if let image = Self.load(agent.logoName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(inverted && agent.markIsMonochrome ? Color(hex: 0x1A1A1C) : .white)
            } else {
                Text(String(agent.displayName.prefix(1)))
                    .font(BrandFont.body(12, weight: .semibold))
                    .foregroundStyle(inverted ? Color(hex: 0x1A1A1C) : .white.opacity(0.7))
            }
        }
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg") else { return nil }
        let image = NSImage(contentsOf: url)
        image?.size = NSSize(width: 38, height: 38)
        return image
    }
}

/// A Control Center slider: a tall rounded track with a filled portion.
struct QuotaBar: View {
    let quota: Quota
    var observed: Date?
    let warn: Int
    let critical: Int

    private var tone: Theme.Tone {
        let left = quota.remainingPercent
        if left <= Double(critical) { return .negative }
        if left <= Double(warn) { return .warning }
        return .quota
    }

    /// A reading older than this is worth flagging: the vendor only writes it
    /// while the agent runs, so it can silently be hours out of date.
    private var staleLabel: String? {
        guard let observed, Date().timeIntervalSince(observed) > 900 else { return nil }
        return "as of \(Self.ago(observed))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.13))
                    Capsule()
                        .fill(LinearGradient(
                            colors: tone == .quota
                                ? [Theme.accentLight, Theme.accent]
                                : [tone.text, tone.text.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(6, geo.size.width * quota.remainingPercent / 100))
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Text("\(Int(quota.remainingPercent))% left").foregroundStyle(tone.text)
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(quota.windowLabel).foregroundStyle(.white.opacity(0.4))
                Spacer()
                if let staleLabel {
                    Text(staleLabel).foregroundStyle(.white.opacity(0.3))
                } else {
                    Text("resets \(Self.countdown(to: quota.resetsAt))")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(BrandFont.body(10))
        }
    }

    static func countdown(to date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }

    static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
