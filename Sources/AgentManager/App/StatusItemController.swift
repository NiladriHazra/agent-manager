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
    private var settingsWindow: NSWindow?
    private var hotkey: Hotkey?
    private var floating: NSWindow?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Remembers its slot across launches, so it comes back where it was
        // instead of being appended at the end of a crowded bar.
        statusItem.autosaveName = "agent-manager"
        statusItem.isVisible = true
        statusItem.behavior = []

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuContentView(model: model))
        // Without this the popover keeps its first measured size, so opening
        // the side panel widened the content and clipped it instead.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        render()

        // The way back in when macOS drops the item from a crowded bar.
        hotkey = Hotkey { [weak self] in self?.toggleFloating() }

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
        // A bar with no room can leave the item hidden; asking for it back on
        // every tick is cheap and makes a vanished icon self-healing.
        if !statusItem.isVisible { statusItem.isVisible = true }
        guard let button = statusItem.button else { return }
        button.image = MenuBarGlyph.klipeo(working: model.workingCount > 0)
        button.imagePosition = .imageLeading
        // Auto-shrinking on a crowded bar was tried and removed: there is no
        // reliable signal for "macOS dropped me", and every proxy for it
        // latched the title off when nothing was wrong. The explicit setting
        // below is honest about what it does.
        button.attributedTitle = Preferences.shared.forceCompactMenuBar
            ? NSAttributedString(string: "")
            : barTitle
        button.toolTip = "\(model.workingCount) working · \(model.waitingCount) waiting on you"
    }

    /// The bar, assembled piece by piece: an optional agent count, then one
    /// entry per chosen agent. A single agent shows its percentage alone; more
    /// than one prefixes each with that agent's own mark, because two bare
    /// percentages side by side say nothing about which is which.
    private var barTitle: NSAttributedString {
        let prefs = Preferences.shared
        let text = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        if prefs.showAgentCount {
            text.append(NSAttributedString(string: " \(model.workingCount)", attributes: attributes))
        }

        guard prefs.showPercentages else { return text }
        let readings = model.menuBarReadings.prefix(prefs.maxMenuBarAgents)

        for (index, reading) in readings.enumerated() {
            let style = prefs.style(for: reading.agent)
            let separator = index == 0 && !prefs.showAgentCount ? " " : (readings.count > 1 ? "  " : " · ")
            text.append(NSAttributedString(string: separator, attributes: attributes))

            if style.showsMark, let mark = MenuBarGlyph.mark(for: reading.agent) {
                let attachment = NSTextAttachment()
                attachment.image = mark
                attachment.bounds = CGRect(x: 0, y: -2, width: 11, height: 11)
                text.append(NSAttributedString(attachment: attachment))
                if style.showsPercent {
                    text.append(NSAttributedString(string: " ", attributes: attributes))
                }
            }
            if style.showsPercent {
                text.append(NSAttributedString(string: "\(reading.percent)%", attributes: attributes))
            }
        }
        return text
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
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open in a window  ⌥⌘A", action: #selector(openFloating), keyEquivalent: "")
            .target = self
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

    /// A floating copy of the panel, for when there is no icon left to click.
    /// Deliberately a panel that joins every Space and sits above normal
    /// windows, since it is summoned over whatever you are working in.
    func toggleFloating() {
        if let floating, floating.isVisible {
            floating.orderOut(nil)
            model.menuClosed()
            return
        }

        model.menuOpened()
        model.refresh()

        let window = floating ?? {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 332, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.051, alpha: 1)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: MenuContentView(model: model))
            host.sizingOptions = [.preferredContentSize]
            panel.contentViewController = host
            floating = panel
            return panel
        }()

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refresh() { model.refresh() }

    @objc private func openFloating() { toggleFloating() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    /// The Settings scene is unreliable to open from a status item in an
    /// accessory app, so the window is owned here instead.
    @objc private func openSettings() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            // No fullSizeContentView: with a transparent title bar the content
            // scrolled up underneath the traffic lights and the window title.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "agent-manager Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    func popoverDidClose(_ notification: Notification) {
        model.menuClosed()
    }
}
