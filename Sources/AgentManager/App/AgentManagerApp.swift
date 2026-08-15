import AppKit
import SwiftUI

/// Creates the menu bar item as soon as the app launches.
///
/// The item is the app's entire interface, so it cannot wait on a scene: the
/// only SwiftUI scene here is Settings, which may never be opened.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(model: model)
    }

    /// Settings switches the app to a regular one so its window can take focus;
    /// closing the last window puts it back in the menu bar where it belongs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.setActivationPolicy(.accessory) }
        return false
    }
}

struct AgentManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
