import SwiftUI

/// The vendor's own mark. AppKit rasterizes the bundled SVGs directly.
///
/// There is no inverted variant: the well behind it is always the same dark
/// disc, so a mark that changed with state was the bug, not a feature.
struct AgentLogo: View {
    let agent: AgentID

    var body: some View {
        Group {
            if let image = Self.load(agent.logoName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(.white)
            } else {
                Text(String(agent.displayName.prefix(1)))
                    .font(BrandFont.body(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// Cached: `body` runs for every row on every refresh, and an uncached
    /// version re-read and re-rasterized the SVG from disk each time.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    private static func load(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 38, height: 38)
        cache[name] = image
        return image
    }
}

/// The text under the split bar: used, left, window, and when it resets.
struct QuotaLine: View {
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

/// The old name, kept because `ago` and `countdown` are used all over.
typealias QuotaBar = QuotaLine
