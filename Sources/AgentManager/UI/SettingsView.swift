import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            agents.tabItem { Label("Agents", systemImage: "square.grid.2x2") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 340)
    }

    private var general: some View {
        Form {
            Picker("Menu bar shows", selection: $prefs.menuBarMode) {
                ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
            }

            Picker("Refresh every", selection: $prefs.refreshSeconds) {
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
            }
            .onChange(of: prefs.refreshSeconds) { model.restartTimer() }

            Section("Low quota warnings") {
                Stepper("Amber below \(prefs.warnThreshold)%", value: $prefs.warnThreshold, in: 5...50, step: 5)
                Stepper("Red below \(prefs.criticalThreshold)%", value: $prefs.criticalThreshold, in: 1...25, step: 1)
            }

            Section("Usage") {
                Toggle("Count cache reads in totals", isOn: $prefs.includeCacheReads)
                Text("Cache reads run around a hundred times larger than everything else, so they are excluded by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLoginItem(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var agents: some View {
        Form {
            Section("Show in the list") {
                ForEach(AgentID.allCases) { agent in
                    Toggle(agent.displayName, isOn: prefs.visibilityBinding(for: agent))
                }
            }
            Section {
                Toggle("Hide agents that are not installed", isOn: $prefs.hideNotInstalled)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agent-manager").font(.title3.bold())
            Text("Which coding agents are running, and how much weekly quota is left.")
                .foregroundStyle(.secondary)

            Divider()

            Text("Where the numbers come from")
                .font(.callout.weight(.semibold))
            Text("""
            Codex writes its real limit to its own session log, so its bar is the vendor's number.
            Claude Code and OpenCode publish no limit anywhere on disk, so those rows show tokens \
            counted from local transcripts and are labelled usage. Nothing here calls an \
            undocumented API or sends anything off this machine.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            // Ad-hoc signed builds outside /Applications are frequently refused.
            loginError = "macOS refused this. Move the app to /Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
