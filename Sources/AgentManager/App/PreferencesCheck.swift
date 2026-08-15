import Combine
import Foundation

/// `agent-manager --check-prefs` exercises the settings round trip against a
/// throwaway defaults domain.
///
/// This exists because the first version used `@AppStorage` inside an
/// `ObservableObject`, which stores values but never notifies, so every setting
/// appeared to save while the interface silently ignored it. The check fails
/// loudly if that regresses.
enum PreferencesCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--check-prefs") else { return }

        let domain = "agent-manager.check.\(ProcessInfo.processInfo.processIdentifier)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            print("could not open a test defaults domain")
            exit(1)
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }

        var failures: [String] = []
        var notifications = 0
        let prefs = Preferences(defaults: defaults)
        let token = prefs.objectWillChange.sink { _ in notifications += 1 }

        // Defaults
        expect(prefs.menuBarMode == .countAndQuota, "default menu bar mode", &failures)
        expect(prefs.refreshSeconds == 60, "default refresh interval", &failures)
        expect(prefs.hideNotInstalled, "default hides uninstalled agents", &failures)
        expect(prefs.hiddenAgents.isEmpty, "nothing hidden by default", &failures)

        // Checked one property at a time. Counting notifications in bulk hides
        // a single property regressing, because the others still fire.
        let mutations: [(String, () -> Void)] = [
            ("menu bar mode", { prefs.menuBarMode = .quotaOnly }),
            ("refresh interval", { prefs.refreshSeconds = 300 }),
            ("warn threshold", { prefs.warnThreshold = 35 }),
            ("critical threshold", { prefs.criticalThreshold = 5 }),
            ("cache-read toggle", { prefs.includeCacheReads = true }),
            ("hide-uninstalled toggle", { prefs.hideNotInstalled = false }),
            ("hidden agents", { prefs.setHidden(.gemini, true) }),
        ]
        for (label, mutate) in mutations {
            let before = notifications
            mutate()
            expect(notifications > before, "changing \(label) publishes", &failures)
        }

        // Values must survive a relaunch.
        let reloaded = Preferences(defaults: defaults)
        expect(reloaded.menuBarMode == .quotaOnly, "menu bar mode persists", &failures)
        expect(reloaded.refreshSeconds == 300, "refresh interval persists", &failures)
        expect(reloaded.warnThreshold == 35, "warn threshold persists", &failures)
        expect(reloaded.includeCacheReads, "cache-read toggle persists", &failures)
        expect(reloaded.isHidden(.gemini), "hidden agent persists", &failures)
        expect(!reloaded.isHidden(.codex), "other agents stay visible", &failures)

        // Unhiding must round trip too.
        reloaded.setHidden(.gemini, false)
        expect(!Preferences(defaults: defaults).isHidden(.gemini), "unhiding persists", &failures)

        token.cancel()

        if failures.isEmpty {
            print("preferences: all checks passed")
            exit(0)
        }
        for failure in failures { print("FAIL  \(failure)") }
        exit(1)
    }

    private static func expect(_ condition: Bool, _ label: String, _ failures: inout [String]) {
        if condition { print("ok    \(label)") } else { failures.append(label) }
    }
}
