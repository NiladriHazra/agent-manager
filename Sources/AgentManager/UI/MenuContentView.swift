import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // A plain stack, not a ScrollView: inside MenuBarExtra's window a
            // ScrollView collapses to zero height, which left the panel showing
            // its header and footer with nothing in between.
            VStack(spacing: 8) {
                if model.visibleSnapshots.isEmpty {
                    emptyState
                } else {
                    ForEach(model.visibleSnapshots) { snapshot in
                        AgentRowView(snapshot: snapshot)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            footer
        }
        .frame(width: 336)
        .background {
            if RenderMode.isOffscreen {
                Theme.surface
            } else {
                VisualEffectBackground().overlay(Color.black.opacity(0.18))
            }
        }
        .onAppear { model.menuOpened() }
        .onDisappear { model.menuClosed() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agents")
                .font(BrandFont.body(20, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(BrandFont.body(11))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let working = model.workingCount
        let open = model.openCount
        if working > 0 {
            return open > working ? "\(working) working · \(open) open" : "\(working) working"
        }
        return open > 0 ? "\(open) open, none working" : "nothing running"
    }

    /// The list shows what is working, so it is empty most of the time. Say so,
    /// and keep any real quota visible rather than showing a blank box.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Nothing working right now")
                .font(BrandFont.body(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            if model.openCount > 0 {
                Text("\(model.openCount) session\(model.openCount == 1 ? "" : "s") open at a prompt")
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            if let headline = model.headlineQuota {
                Text("\(headline.agent.displayName): \(Int(headline.quota.remainingPercent))% left this week")
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            HStack(spacing: 14) {
                if let updated = model.lastUpdated {
                    Text("updated \(QuotaBar.ago(updated))")
                        .font(BrandFont.body(10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                FooterButton(title: "Settings") { openSettings() }
                FooterButton(title: "Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.body(11, weight: .medium))
                .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(hovered ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// What sits in the menu bar. Digits are monospaced and the layout is
/// fixed-width so the bar does not reflow every time a number ticks.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        // One Text rather than a stack of conditional views: MenuBarExtra
        // renders its label into a template image, and conditional subviews
        // there do not reliably re-render when the model changes.
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(working: model.workingCount > 0))
            if !text.isEmpty { Text(text).monospacedDigit() }
        }
    }

    private var text: String {
        let quota = model.headlineQuota.map { "\(Int($0.quota.remainingPercent))%" }
        switch prefs.menuBarMode {
        case .countAndQuota:
            guard let quota else { return "\(model.workingCount)" }
            return "\(model.workingCount) · \(quota)"
        case .countOnly:
            return "\(model.workingCount)"
        case .quotaOnly:
            return quota ?? "–"
        case .iconOnly:
            return ""
        }
    }
}
