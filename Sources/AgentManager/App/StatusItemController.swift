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
    /// Set when the bar has no room for the full title, so the item keeps its
    /// place instead of being dropped entirely.
    private var compact = false
    private var crowdedUntil = Date.distantPast

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
        let wantsCompact = compact || Preferences.shared.forceCompactMenuBar
        button.attributedTitle = wantsCompact ? NSAttributedString(string: "") : barTitle
        button.toolTip = "\(model.workingCount) working · \(model.waitingCount) waiting on you"
        guard !Preferences.shared.forceCompactMenuBar else { return }
        adjustForCrowding()
    }

    /// Screen recording and dictation both add their own indicators, and a full
    /// bar makes macOS drop whatever no longer fits — which was this item,
    /// title and all. Dropping to the mark alone keeps a foothold, and the
    /// title returns as soon as there is room again.
    private func adjustForCrowding() {
        guard let button = statusItem.button else { return }

        // No window at all means the item is not being drawn: the bar has run
        // out of room and macOS has dropped it. Shrinking to the mark is the
        // only lever available, so take it and stay there for a while.
        guard let window = button.window else {
            if !compact {
                compact = true
                button.attributedTitle = NSAttributedString(string: "")
            }
            crowdedUntil = Date().addingTimeInterval(120)
            return
        }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let frame = window.frame
        let crowded = frame.minX < screen.visibleFrame.minX + 4 || frame.width < 24

        if crowded {
            crowdedUntil = Date().addingTimeInterval(120)
            if !compact {
                compact = true
                button.attributedTitle = NSAttributedString(string: "")
            }
            return
        }

        // Only widen again once the bar has been roomy for a while: restoring
        // the title the instant a pixel frees up flaps between two widths.
        if compact, Date() > crowdedUntil, frame.minX > screen.visibleFrame.minX + 80 {
            compact = false
            button.attributedTitle = barTitle
        }
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
