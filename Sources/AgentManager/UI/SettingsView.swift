import ServiceManagement
import SwiftUI

/// Settings, in the same glass language as the panel.
///
/// A left rail of sections, a scrolling detail on the right. The per-agent
/// section only offers readings that agent genuinely publishes, so no switch
/// here is decorative.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, agents, readings, about

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return "General"
            case .agents: return "Agents"
            case .readings: return "Readings"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .agents: return "square.grid.2x2"
            case .readings: return "chart.bar"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(.white.opacity(0.08))
            ScrollView {
                content
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 460)
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(BrandFont.body(13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ForEach(Section.allCases) { option in
                Button { section = option } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.icon).font(.system(size: 11))
                        Text(option.label).font(BrandFont.body(12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(section == option ? .white : .white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .glassTab(selected: section == option)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 168)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .general: general
        case .agents: agents
        case .readings: readings
        case .about: about
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                heading("Menu bar")
                caption("The Klipeo mark is always shown. Everything beside it is yours to choose.")
                Toggle("Number of working agents", isOn: $prefs.showAgentCount)
                Toggle("Percentages", isOn: $prefs.showPercentages)

                if prefs.showPercentages {
                    Picker("At most", selection: $prefs.maxMenuBarAgents) {
                        Text("1 agent").tag(1)
                        Text("2 agents").tag(2)
                        Text("3 agents").tag(3)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(AgentID.allCases.filter { percentSource(for: $0) != nil }) { agent in
                            HStack(spacing: 9) {
                                IconWell(agent: agent, size: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.displayName)
                                        .font(BrandFont.body(11.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(percentSource(for: agent) ?? "")
                                        .font(BrandFont.body(9.5))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                if prefs.isInMenuBar(agent) {
                                    Picker("", selection: prefs.styleBinding(for: agent)) {
                                        ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0) }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 108)
                                }
                                Toggle("", isOn: prefs.menuBarBinding(for: agent))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .glassTile(radius: 12)
                        }
                    }
                    caption("One agent shows its percentage alone. Two or more each carry their own mark, since bare percentages side by side do not say which is which. Choosing more than the limit drops the oldest.")
                }

                MenuBarPreview(model: model)
                    .padding(.top, 2)
            }

            Group {
                heading("Refresh")
                Picker("While the panel is closed", selection: $prefs.refreshSeconds) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .onChange(of: prefs.refreshSeconds) { model.restartTimer() }
                caption("An open panel refreshes every second.")
            }

            Group {
                heading("Low quota")
                Stepper("Amber below \(prefs.warnThreshold)% left", value: $prefs.warnThreshold, in: 5...90)
                Stepper("Red below \(prefs.criticalThreshold)% left", value: $prefs.criticalThreshold, in: 1...50)
            }

            Toggle("Launch at login", isOn: launchAtLogin)
        }
        .font(BrandFont.body(12))
        .foregroundStyle(.white.opacity(0.9))
    }

    /// What an agent's percentage would actually mean, so nobody switches on a
    /// number without knowing what it measures.
    private func percentSource(for agent: AgentID) -> String? {
        if Metric.supported(by: agent).contains(.quota) { return "share of its weekly limit used" }
        if Metric.supported(by: agent).contains(.context) { return "fullest live context" }
        return nil
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("Which agents appear")
            ForEach(AgentID.allCases) { agent in
                HStack(spacing: 10) {
                    IconWell(agent: agent, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent.displayName)
                            .font(BrandFont.body(12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(summary(for: agent))
                            .font(BrandFont.body(10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: prefs.visibilityBinding(for: agent))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .glassTile(radius: 14)
            }

            Toggle("Hide agents that are not installed", isOn: $prefs.hideNotInstalled)
                .font(BrandFont.body(12))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 4)
        }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("What each row shows")
            caption("Only readings the agent actually writes to disk are listed.")

            ForEach(AgentID.allCases) { agent in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        IconWell(agent: agent, size: 20)
                        Text(agent.displayName)
                            .font(BrandFont.body(12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    ForEach(Metric.supported(by: agent)) { metric in
                        Toggle(metric.label, isOn: prefs.metricBinding(metric, for: agent))
                            .font(BrandFont.body(11))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassTile(radius: 14)
            }

            Toggle("Count cache reads in token totals", isOn: $prefs.includeCacheReads)
                .font(BrandFont.body(12))
                .foregroundStyle(.white.opacity(0.9))
            caption("Cache reads run about a hundred times larger than everything else, so they are excluded by default.")
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("agent-manager")
            caption("Reads only local files. Nothing is sent anywhere, and no undocumented vendor API is called.")
            caption("A quota bar appears only where the vendor wrote a real limit to disk. Everything else is counted locally and labelled as usage.")
            Link("github.com/NiladriHazra/agent-manager",
                 destination: URL(string: "https://github.com/NiladriHazra/agent-manager")!)
                .font(BrandFont.body(11))
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.body(12.5, weight: .bold))
            .foregroundStyle(.white)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.body(10.5))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(for agent: AgentID) -> String {
        let metrics = Metric.supported(by: agent)
        if metrics.contains(.quota) { return "publishes a real quota" }
        if metrics.contains(.context) { return "usage, context and sub-agents" }
        if metrics.contains(.cost) { return "usage and spend" }
        return "presence only"
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }
}
