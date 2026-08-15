import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case working
    case open

    var id: String { rawValue }
    var label: String { self == .working ? "Working" : "Open" }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @State private var tab: PanelTab = .working
    @State private var inspecting: Int32?
    @State private var primed = false

    var body: some View {
        HStack(spacing: 0) {
            main
            if let inspected = inspectedSession {
                Divider().overlay(Color.white.opacity(0.10))
                SubAgentPanel(session: inspected.session) { inspecting = nil }
                    .frame(width: 268)
            }
        }
        .background {
            if RenderMode.isOffscreen {
                Theme.surface
            } else {
                VisualEffectBackground(material: .popover)
            }
        }
        .onAppear {
            model.menuOpened()
            // Offscreen renders open the side panel so it can be inspected.
            guard RenderMode.isOffscreen, !primed else { return }
            primed = true
            inspecting = groups.flatMap(\.sessions).first { !$0.subAgents.isEmpty }?.pid
        }
        .onDisappear { model.menuClosed() }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabs

            VStack(spacing: 9) {
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.agent) { group in
                        AgentGroupView(group: group, inspecting: $inspecting)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 11)
        }
        .frame(width: 332)
    }

    /// Sessions gathered under their tool, so an account-level number like the
    /// Codex quota is stated once rather than repeated on all four terminals.
    private var groups: [AgentGroup] {
        model.visibleSnapshots.compactMap { snapshot in
            let sessions = tab == .working ? snapshot.workingSessions : snapshot.openSessions
            guard !sessions.isEmpty else { return nil }
            return AgentGroup(
                agent: snapshot.agent,
                sessions: sessions,
                quota: snapshot.quota,
                quotaObserved: snapshot.quotaObserved,
                usage: snapshot.usage
            )
        }
    }

    private var inspectedSession: (agent: AgentID, session: RunningSession)? {
        guard let inspecting else { return nil }
        for group in groups {
            if let match = group.sessions.first(where: { $0.pid == inspecting }) {
                return (group.agent, match)
            }
        }
        return nil
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agents")
                .font(BrandFont.body(15, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Text("updated \(QuotaBar.ago(model.lastUpdated ?? Date()))")
                .font(BrandFont.body(9.5))
                .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(PanelTab.allCases) { option in
                let count = option == .working ? model.workingCount : model.openCount
                Button { tab = option; inspecting = nil } label: {
                    HStack(spacing: 6) {
                        Text(option.label).font(BrandFont.body(11, weight: .semibold))
                        Text(verbatim: "\(count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(tab == option ? 0.75 : 0.4))
                    }
                    .foregroundStyle(tab == option ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background {
                        if tab == option {
                            Capsule().fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.13)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(tab == .working ? "Nothing working right now" : "No idle sessions")
                .font(BrandFont.body(12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if tab == .working, model.openCount > 0 {
                Text("\(model.openCount) open at a prompt")
                    .font(BrandFont.body(11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct AgentGroup {
    let agent: AgentID
    let sessions: [RunningSession]
    let quota: Quota?
    let quotaObserved: Date?
    let usage: Usage?
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
        let quota = model.headlineQuota.map { "\(Int($0.quota.usedPercent))%" }
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
