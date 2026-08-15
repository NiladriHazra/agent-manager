import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case working
    case waiting
    case open

    var id: String { rawValue }

    var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .open: return "Open"
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @State private var tab: PanelTab = .working
    @State private var detail: DetailTarget?
    @State private var primed = false

    var body: some View {
        HStack(spacing: 0) {
            main
            if detail != nil {
                Divider().overlay(Color.white.opacity(0.10))
                sidePanel
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.28), value: detail)
        .background(RenderMode.isOffscreen ? Theme.surface : Color.clear)
        .onAppear {
            model.menuOpened()
            // Offscreen renders open the side panel so it can be inspected.
            guard RenderMode.isOffscreen, !primed else { return }
            primed = true
            detail = groups.first { $0.sessions.count > 1 }.map { .sessions($0.agent) }
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
                        AgentGroupView(group: group, detail: $detail)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 11)
            .glassGroup()
        }
        .frame(width: 332)
    }

    /// Sessions gathered under their tool, so an account-level number like the
    /// Codex quota is stated once rather than repeated on all four terminals.
    private var groups: [AgentGroup] {
        model.visibleSnapshots.compactMap { snapshot in
            let sessions: [RunningSession]
            switch tab {
            case .working: sessions = snapshot.workingSessions
            case .waiting: sessions = snapshot.waitingSessions
            case .open: sessions = snapshot.openSessions
            }
            guard !sessions.isEmpty else { return nil }
            return AgentGroup(
                agent: snapshot.agent,
                sessions: sessions,
                quota: snapshot.quota,
                quotaObserved: snapshot.quotaObserved,
                usage: snapshot.usage,
                usageToday: snapshot.usageToday
            )
        }
    }

    @ViewBuilder private var sidePanel: some View {
        switch detail {
        case .sessions(let agent):
            if let group = groups.first(where: { $0.agent == agent }) {
                DetailPanel(
                    title: agent.displayName,
                    count: group.sessions.count,
                    activeCount: group.sessions.filter { $0.activity.isWorking }.count,
                    onClose: { detail = nil },
                    rows: AnyView(
                        VStack(spacing: 7) {
                            ForEach(group.sessions) { session in
                                SessionRowView(
                                    agent: agent,
                                    session: session,
                                    quota: nil,
                                    quotaObserved: nil,
                                    usage: nil,
                                    usageToday: nil,
                                    isInspecting: false,
                                    onInspect: { detail = .subAgents(pid: session.pid) }
                                )
                            }
                        }
                    )
                )
            }
        case .subAgents(let pid):
            if let session = groups.flatMap(\.sessions).first(where: { $0.pid == pid }) {
                DetailPanel(
                    title: "Sub-agents",
                    count: session.subAgents.count,
                    activeCount: session.subAgents.filter(\.isWorking).count,
                    onClose: { detail = nil },
                    rows: AnyView(
                        VStack(spacing: 5) {
                            ForEach(session.subAgents) { SubAgentRow(subAgent: $0) }
                        }
                    )
                )
            }
        case .none:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agents")
                .font(BrandFont.body(15, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            Spacer()
            ForEach(PanelTab.allCases) { option in
                let count = model.count(for: option)
                Button { tab = option; detail = nil } label: {
                    HStack(spacing: 6) {
                        Text(option.label).font(BrandFont.body(11, weight: .semibold))
                        Text(verbatim: "\(count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(tab == option ? 0.75 : 0.4))
                    }
                    .foregroundStyle(tab == option ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .glassTab(selected: tab == option)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private var emptyMessage: String {
        switch tab {
        case .working: return "Nothing working right now"
        case .waiting: return "No one is waiting on you"
        case .open: return "No idle sessions"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(emptyMessage)
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
    let usageToday: Usage?
}

/// What sits in the menu bar. Right-clicking it opens Settings and Quit, the
/// way a menu bar app is expected to behave, so the panel needs no footer.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.klipeo(working: model.workingCount > 0))
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
