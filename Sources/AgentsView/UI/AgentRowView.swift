import SwiftUI

/// One agent: its own mark, a live activity line, and either a real quota bar
/// or a clearly labelled local usage figure. The two are visually distinct on
/// purpose so a usage number is never mistaken for a remaining allowance.
struct AgentRowView: View {
    let snapshot: AgentSnapshot
    @ObservedObject private var prefs = Preferences.shared
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AgentLogo(agent: snapshot.agent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.agent.displayName)
                        .font(BrandFont.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    subtitle
                }

                Spacer(minLength: 8)
                trailing
            }

            if let quota = snapshot.quota {
                QuotaBar(quota: quota, warn: prefs.warnThreshold, critical: prefs.criticalThreshold)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(cornerRadius: 12, hovered: hovered)
        .onHover { hovered = $0 }
    }

    @ViewBuilder private var subtitle: some View {
        switch snapshot.availability {
        case .loading:
            Text("reading…").font(BrandFont.body(11)).foregroundStyle(Theme.textTertiary)
        case .notInstalled:
            Text("not installed").font(BrandFont.body(11)).foregroundStyle(Theme.textTertiary)
        case .unavailable(let reason):
            Text(reason).font(BrandFont.body(11)).foregroundStyle(Theme.textTertiary)
        case .ready:
            if let first = snapshot.sessions.first {
                Text(first.activityLine)
                    .font(BrandFont.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else if let usage = snapshot.usage {
                HStack(spacing: 4) {
                    Text(formatTokens(usage.total(includingCacheReads: prefs.includeCacheReads)))
                    Text("this week")
                    Text("· usage").foregroundStyle(Theme.textTertiary)
                }
                .font(BrandFont.body(11))
                .foregroundStyle(Theme.textSecondary)
            } else {
                Text("idle").font(BrandFont.body(11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if snapshot.sessions.count > 1 {
            Pill(text: "\(snapshot.sessions.count) running", tone: .positive)
        } else if snapshot.isRunning {
            Pill(text: "running", tone: .positive)
        } else if let credits = snapshot.credits {
            Pill(text: "\(credits) cr", tone: .quota)
        }
    }

    private func formatTokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

struct Pill: View {
    let text: String
    let tone: Theme.Tone

    var body: some View {
        Text(text)
            .font(BrandFont.body(10, weight: .medium))
            .foregroundStyle(tone.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tone.fill))
            .overlay(Capsule().strokeBorder(tone.stroke, lineWidth: 1))
    }
}

/// The vendor's own mark. AppKit rasterizes the bundled SVGs directly, so no
/// build-time conversion is needed.
struct AgentLogo: View {
    let agent: AgentID

    var body: some View {
        Group {
            if let image = Self.load(agent.logoName) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text(String(agent.displayName.prefix(1)))
                    .font(BrandFont.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 18, height: 18)
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg") else { return nil }
        let image = NSImage(contentsOf: url)
        image?.size = NSSize(width: 36, height: 36)
        return image
    }
}

/// A real vendor limit, with the reset rendered as a countdown.
struct QuotaBar: View {
    let quota: Quota
    let warn: Int
    let critical: Int

    private var tone: Theme.Tone {
        let left = quota.remainingPercent
        if left <= Double(critical) { return .negative }
        if left <= Double(warn) { return .warning }
        return .quota
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(
                            colors: tone == .quota ? [Theme.accentLight, Theme.accent] : [tone.text, tone.text.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(3, geo.size.width * quota.remainingPercent / 100))
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text("\(Int(quota.remainingPercent))% left")
                    .foregroundStyle(tone.text)
                Text("·").foregroundStyle(Theme.textTertiary)
                Text(quota.windowLabel).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("resets \(Self.countdown(to: quota.resetsAt))")
                    .foregroundStyle(Theme.textTertiary)
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
}
