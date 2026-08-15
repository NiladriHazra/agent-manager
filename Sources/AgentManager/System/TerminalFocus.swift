import AppKit
import Darwin
import Foundation

/// Brings the terminal running a session to the front.
///
/// A row that shows a session but cannot take you to it is a dead end, so
/// clicking one activates the app that owns it. The owning app is found by
/// walking up the parent chain until a process inside an `.app` bundle appears
/// — the agent's parent is a shell, and the shell's parent is the terminal.
///
/// Terminal.app and iTerm2 both expose a tab's `tty`, so those two can select
/// the exact tab. Everything else can only be raised to the front, which is
/// still better than nothing.
enum TerminalFocus {
    static func focus(pid: Int32, tty: String?) {
        guard let bundle = owningApp(of: pid) else { return }

        NSWorkspace.shared.openApplication(
            at: bundle,
            configuration: NSWorkspace.OpenConfiguration()
        )

        guard let tty, let script = tabScript(bundle: bundle, tty: tty) else { return }
        // Best effort: the first run prompts for Automation permission, and a
        // refusal simply leaves the app raised without tab selection.
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    /// Terminals that expose a tab's `tty`, so the exact session can be
    /// selected rather than the app merely raised.
    private static let scriptable: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]

    /// Whether clicking would visibly do anything.
    ///
    /// Takes the table the caller already built: the scan runs every second and
    /// must not enumerate every process once per session.
    ///
    /// Raising an app that is already frontmost looks broken — which is exactly
    /// what happened for agents running inside a terminal that cannot be
    /// scripted. Those rows offer no click at all rather than a dead one.
    static func canFocus(pid: Int32, in table: [Int32: ProcessScanner.Proc]) -> Bool {
        guard let bundle = owningApp(of: pid, table: table) else { return false }
        if let id = Bundle(url: bundle)?.bundleIdentifier, scriptable.contains(id) { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleURL != bundle
    }

    private static func owningApp(of pid: Int32) -> URL? {
        let table = Dictionary(
            uniqueKeysWithValues: ProcessScanner.allProcessesUnfiltered().map { ($0.pid, $0) }
        )
        return owningApp(of: pid, table: table)
    }

    private static func owningApp(of pid: Int32, table byPid: [Int32: ProcessScanner.Proc]) -> URL? {
        var current = byPid[pid]?.ppid ?? 0
        var hops = 0
        while current > 1, hops < 24 {
            if let path = byPid[current]?.executable,
               let range = path.range(of: ".app/Contents/MacOS/") {
                return URL(fileURLWithPath: String(path[path.startIndex..<range.lowerBound]) + ".app")
            }
            current = byPid[current]?.ppid ?? 0
            hops += 1
        }
        return nil
    }

    private static func tabScript(bundle: URL, tty: String) -> String? {
        switch Bundle(url: bundle)?.bundleIdentifier {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}
