import AppKit
import SwiftUI

/// The menu bar item, owned directly rather than through `MenuBarExtra`.
///
/// `MenuBarExtra` never delivers a right-click to its label, so there was no
/// way to offer Settings and Quit the way every other menu bar app does. An
/// `NSStatusItem` can distinguish the two clicks: left opens the panel, right
/// opens a normal menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var observation: NSKeyValueObservation?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(model: model).frame(minWidth: 332)
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        render()

        // The title tracks the model, so the bar stays current while closed.
        observation = nil
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.render()
            }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarGlyph.klipeo(working: model.workingCount > 0)
        button.imagePosition = .imageLeading
        button.title = title.isEmpty ? "" : " \(title)"
        button.toolTip = "\(model.workingCount) working · \(model.waitingCount) waiting on you"
    }

    private var title: String {
        let quota = model.headlineQuota.map { "\(Int($0.quota.usedPercent))%" }
        switch Preferences.shared.menuBarMode {
        case .countAndQuota:
            guard let quota else { return "\(model.workingCount)" }
            return "\(model.workingCount) · \(quota)"
        case .countOnly: return "\(model.workingCount)"
        case .quotaOnly: return quota ?? "–"
        case .iconOnly: return ""
        }
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.menuOpened()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh now", action: #selector(refresh), keyEquivalent: "r")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit agent-manager", action: #selector(quit), keyEquivalent: "q")
            .target = self

        // A menu assigned to the item takes over left-click too, so it is
        // attached only for the length of this one click.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { model.refresh() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.menuClosed()
    }
}
