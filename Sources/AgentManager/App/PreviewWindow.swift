import AppKit
import SwiftUI

/// `agent-manager --preview-window` shows the panel in an ordinary window.
///
/// Materials only look like glass when they have a real window behind them to
/// sample; an offscreen render flattens them to grey. This makes the panel
/// screenshot-able without the Accessibility permission that clicking a menu
/// bar item needs.
@MainActor
enum PreviewWindow {
    nonisolated(unsafe) private static var retained: NSWindow?

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--preview-window") else { return }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let model = AppModel()
        let hosting = NSHostingView(rootView: MenuContentView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 332, height: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 220, width: 332, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        retained = window

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
