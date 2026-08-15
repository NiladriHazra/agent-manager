import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // A plain stack, not a ScrollView: inside MenuBarExtra's window a
            // ScrollView collapses to zero height, which left the panel showing
            // its header and footer with nothing in between. The list is bounded
            // by the number of agents, so it never needs to scroll.
            VStack(spacing: 6) {
                if model.visibleSnapshots.isEmpty {
                    emptyState
                } else {
                    ForEach(model.visibleSnapshots) { snapshot in
                        AgentRowView(snapshot: snapshot)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            footer
        }
        .frame(width: 320)
        .background {
            if RenderMode.isOffscreen {
                Theme.surface
            } else {
                VisualEffectBackground().overlay(Color.black.opacity(0.28))
            }
        }
        .onAppear { model.menuOpened() }
        .onDisappear { model.menuClosed() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Agents")
                .font(BrandFont.body(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(model.runningCount == 1 ? "1 running" : "\(model.runningCount) running")
                .font(BrandFont.body(11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The list only shows what is working, so it is empty most of the time.
    /// Say so, and keep any real quota visible rather than showing a blank box.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nothing running")
                .font(BrandFont.body(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if let headline = model.headlineQuota {
                Text("\(headline.agent.displayName) has \(Int(headline.quota.remainingPercent))% left this week")
                    .font(BrandFont.body(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("Idle agents are hidden. Turn them on in Settings.")
                .font(BrandFont.body(10))
                .foregroundStyle(Theme.textTertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: 12) {
                if let updated = model.lastUpdated {
                    Text("updated \(Self.relative(updated))")
                        .font(BrandFont.body(10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button("Settings") { openSettings() }
                    .buttonStyle(.plain)
                    .font(BrandFont.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(BrandFont.body(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}

/// What sits in the menu bar itself. Digits are monospaced and the layout is
/// fixed-width so the bar does not reflow every time a number ticks.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        // One Text rather than a stack of conditional views: MenuBarExtra
        // renders its label into a template image, and conditional subviews
        // there do not reliably re-render when the model changes.
        HStack(spacing: 4) {
            Image(systemName: glyph)
            if !text.isEmpty { Text(text).monospacedDigit() }
        }
    }

    private var text: String {
        let quota = model.headlineQuota.map { "\(Int($0.quota.remainingPercent))%" }
        switch prefs.menuBarMode {
        case .countAndQuota:
            guard let quota else { return "\(model.runningCount)" }
            return "\(model.runningCount) · \(quota)"
        case .countOnly:
            return "\(model.runningCount)"
        case .quotaOnly:
            return quota ?? "–"
        case .iconOnly:
            return ""
        }
    }

    private var glyph: String {
        guard let headline = model.headlineQuota else {
            return model.runningCount > 0 ? "diamond.fill" : "diamond"
        }
        let left = headline.quota.remainingPercent
        if left <= Double(prefs.criticalThreshold) { return "diamond.bottomhalf.filled" }
        return model.runningCount > 0 ? "diamond.fill" : "diamond"
    }
}
