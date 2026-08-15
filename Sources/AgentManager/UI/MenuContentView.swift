import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case working
    case open

    var id: String { rawValue }
    var label: String { self == .working ? "Working" : "Open" }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var tab: PanelTab = .working

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabs

            VStack(spacing: 5) {
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows, id: \.session.id) { entry in
                        SessionRowView(
                            agent: entry.agent,
                            session: entry.session,
                            quota: entry.quota,
                            quotaObserved: entry.observed
                        )
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 9)
        }
        .frame(width: 300)
        .background {
            if RenderMode.isOffscreen {
                Theme.surface
            } else {
                // No dark overlay: it is what was flattening the material into a
                // plain dark panel instead of the translucent Control Center look.
                VisualEffectBackground(material: .hudWindow)
            }
        }
        .onAppear { model.menuOpened() }
        .onDisappear { model.menuClosed() }
    }

    private struct Row {
        let agent: AgentID
        let session: RunningSession
        let quota: Quota?
        let observed: Date?
    }

    /// One row per terminal rather than per tool, so four Codex sessions in
    /// four terminals read as four rows.
    private var rows: [Row] {
        model.visibleSnapshots.flatMap { snapshot -> [Row] in
            let sessions = tab == .working ? snapshot.workingSessions : snapshot.openSessions
            return sessions.map {
                Row(agent: snapshot.agent, session: $0, quota: snapshot.quota, observed: snapshot.quotaObserved)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agents")
                .font(BrandFont.body(15, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if let headline = model.headlineQuota {
                Text("\(headline.agent.displayName) \(Int(headline.quota.remainingPercent))%")
                    .font(BrandFont.body(10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { option in
                let count = option == .working ? model.workingCount : model.openCount
                Button { tab = option } label: {
                    HStack(spacing: 6) {
                        Text(option.label)
                            .font(BrandFont.body(11, weight: .semibold))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tab == option ? .white.opacity(0.8) : .white.opacity(0.4))
                    }
                    .foregroundStyle(tab == option ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(tab == option ? 0.16 : 0))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(tab == .working ? "Nothing working right now" : "No idle sessions")
                .font(BrandFont.body(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if tab == .working, model.openCount > 0 {
                Text("\(model.openCount) session\(model.openCount == 1 ? "" : "s") open at a prompt")
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// What sits in the menu bar. Right-clicking it opens Settings and Quit, the
/// way a menu bar app is expected to behave, so the panel needs no footer.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(working: model.workingCount > 0))
            if !text.isEmpty { Text(text).monospacedDigit() }
        }
        .contextMenu {
            Button("Settings…") { openSettings() }
            Button("Refresh now") { model.refresh() }
            Divider()
            Button("Quit agent-manager") { NSApplication.shared.terminate(nil) }
        }
    }

    private var text: String {
        let quota = model.headlineQuota.map { "\(Int($0.quota.remainingPercent))%" }
        switch prefs.menuBarMode {
        case .countAndQuota:
            guard let quota else { return "\(model.workingCount)" }
            return "\(model.workingCount) · \(quota)"
        case .countOnly: return "\(model.workingCount)"
        case .quotaOnly: return quota ?? "–"
        case .iconOnly: return ""
        }
    }
}
