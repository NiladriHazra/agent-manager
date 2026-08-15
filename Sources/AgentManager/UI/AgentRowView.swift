import SwiftUI

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
                        .frame(width: max(6, geo.size.width * quota.usedPercent / 100))
                }
            }
            .frame(height: 5)

            HStack(spacing: 4) {
                Text("\(Int(quota.usedPercent))% used").foregroundStyle(.white.opacity(0.85))
                Text("·").foregroundStyle(.white.opacity(0.3))
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
