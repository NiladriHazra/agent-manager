import Darwin
import Foundation

/// Finds genuine agent CLI processes.
///
/// `ps` is unusable here: dozens of ChatGPT.app Electron helpers carry "Codex"
/// in their command line, and each real session is wrapped by shell scripts and
/// helper daemons. This reads the kernel process table directly (no forking,
/// ~1ms) and then allow-lists on argv[0] before rejecting known impostors.
enum ProcessScanner {
    struct Proc {
        let pid: Int32
        let ppid: Int32
        /// The path passed to exec, which is what identifies the tool. argv[0]
        /// is not reliable, and the kernel's short name is worse: Claude runs
        /// from a version-named binary, so its p_comm reads "2.1.233".
        let executable: String
        let argv: [String]
        /// Controlling terminal, e.g. `/dev/ttys008`. This is how a terminal
        /// app is asked to select the right tab.
        var tty: String?
        var name: String { (executable as NSString).lastPathComponent }
    }

    /// Helper binaries and wrappers that mention an agent but are not one.
    private static let rejectedArgFragments = [
        "--type=", "app-server", "code-mode-host", "mcp-server", "--listen",
        "remote-control", "crashpad", "ComputerUse", "gateway run", "-m hermes_cli",
    ]

    private static let shellNames: Set<String> = [
        "bash", "sh", "zsh", "node", "python3", "python", "env", "tail", "grep",
    ]

    static func runningAgents() -> [RunningSession] {
        let procs = allProcesses()
        let byPid = Dictionary(uniqueKeysWithValues: procs.map { ($0.pid, $0) })

        var matches: [(Proc, AgentID)] = []
        for proc in procs {
            guard let agent = classify(proc) else { continue }
            matches.append((proc, agent))
        }

        // Collapse wrapper chains: `/bin/bash .../codex` spawning the real
        // `codex` would otherwise count twice. Keep only the deepest process
        // of each agent in any ancestor chain.
        let matchedPids = Set(matches.map { $0.0.pid })
        let deepest = matches.filter { entry in
            var parent = entry.0.ppid
            var hops = 0
            while parent > 1, hops < 24 {
                if matchedPids.contains(parent),
                   let p = byPid[parent], classify(p) == entry.1 {
                    return false
                }
                parent = byPid[parent]?.ppid ?? 0
                hops += 1
            }
            return true
        }

        return deepest.map { proc, agent in
            RunningSession(
                pid: proc.pid,
                agent: agent,
                sessionID: resumedSessionID(proc.argv),
                title: nil,
                cwd: cwd(of: proc.pid),
                branch: nil,
                tty: proc.tty
            )
        }
    }

    /// Names a process might be known by. A wrapper script keeps the tool in
    /// argv[0], and an interpreter launch (`python3 .../bin/hermes`) puts it in
    /// argv[1], so all of them are considered.
    static func candidateNames(_ execPath: String, _ argv: [String]) -> [String] {
        var names = [(execPath as NSString).lastPathComponent]
        for arg in argv.prefix(2) where !arg.hasPrefix("-") {
            names.append((arg as NSString).lastPathComponent)
        }
        return names
    }

    static func classify(_ proc: Proc) -> AgentID? {
        let exec = proc.executable
        let names = candidateNames(exec, proc.argv)
        // Only a bare interpreter with no agent name anywhere is a shell.
        guard names.contains(where: { !shellNames.contains($0) }) else { return nil }
        // Anything shipped inside an .app bundle is a GUI helper, not the CLI.
        guard !exec.contains(".app/Contents/"), !exec.hasPrefix("/Applications/") else { return nil }

        let joined = proc.argv.joined(separator: " ")
        for fragment in rejectedArgFragments where joined.contains(fragment) { return nil }

        return AgentID.allCases.first { agent in
            names.contains { agent.executableNames.contains($0) }
        }
    }

    private static func ttyName(_ device: dev_t) -> String? {
        guard device != dev_t.max else { return nil }
        guard let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// Every process this user owns, with no agent filtering. Walking up to a
    /// terminal crosses shells and app bundles, which the agent filter drops.
    static func allProcessesUnfiltered() -> [Proc] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }

        let count = length / MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&name, 4, &buffer, &length, nil, 0) == 0 else { return [] }

        let uid = getuid()
        return (0..<(length / MemoryLayout<kinfo_proc>.stride)).compactMap { index in
            let entry = buffer[index]
            guard entry.kp_eproc.e_ucred.cr_uid == uid, entry.kp_proc.p_pid > 0 else { return nil }
            return Proc(
                pid: entry.kp_proc.p_pid,
                ppid: entry.kp_eproc.e_ppid,
                executable: executablePath(of: entry.kp_proc.p_pid) ?? "",
                argv: [],
                tty: nil
            )
        }
    }

    /// Cheap exec-path lookup for a single pid.
    static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let size = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard size > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Working directory of a pid. Same-user processes need no entitlement.
    static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, Int32(size))
        }
        guard result == Int32(size) else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    static func allProcesses() -> [Proc] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, 4, nil, &length, nil, 0) == 0, length > 0 else { return [] }

        let count = length / MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&name, 4, &buffer, &length, nil, 0) == 0 else { return [] }

        let actual = length / MemoryLayout<kinfo_proc>.stride
        let uid = getuid()
        let wanted = Set(AgentID.allCases.flatMap(\.executableNames))

        // One 1 MB buffer reused for every process. Allocating it per process
        // would churn ~600 MB; reused, the whole sweep measures ~13 ms.
        var argMax: Int32 = 0
        var argSize = MemoryLayout<Int32>.size
        var argMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argMib, 2, &argMax, &argSize, nil, 0) == 0, argMax > 0 else { return [] }
        var scratch = [CChar](repeating: 0, count: Int(argMax))

        var result: [Proc] = []
        for i in 0..<actual {
            let entry = buffer[i]
            guard entry.kp_eproc.e_ucred.cr_uid == uid, entry.kp_proc.p_pid > 0 else { continue }

            var size = scratch.count
            var procMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, entry.kp_proc.p_pid]
            guard sysctl(&procMib, 3, &scratch, &size, nil, 0) == 0,
                  size > MemoryLayout<Int32>.size else { continue }

            // The exec path sits immediately after the argc word.
            var cursor = MemoryLayout<Int32>.size
            while cursor < size, scratch[cursor] != 0 { cursor += 1 }
            let pathBytes = scratch[MemoryLayout<Int32>.size..<cursor].map { UInt8(bitPattern: $0) }
            guard let execPath = String(bytes: pathBytes, encoding: .utf8) else { continue }
            let argv = parseArguments(scratch, size: size)

            // A wrapper script keeps the tool's name in argv[0] even though the
            // kernel reports the interpreter it exec'd.
            guard wanted.contains(where: { candidateNames(execPath, argv).contains($0) }) else { continue }
            result.append(Proc(
                pid: entry.kp_proc.p_pid,
                ppid: entry.kp_eproc.e_ppid,
                executable: execPath,
                argv: argv,
                tty: ttyName(entry.kp_eproc.e_tdev)
            ))
        }
        return result
    }

    /// Splits the KERN_PROCARGS2 payload into argv, which is where flags like
    /// `--resume <uuid>` live.
    private static func parseArguments(_ buffer: [CChar], size: Int) -> [String] {
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { raw in
            for i in 0..<MemoryLayout<Int32>.size { raw[i] = UInt8(bitPattern: buffer[i]) }
        }
        guard argc > 0 else { return [] }

        var args: [String] = []
        var cursor = MemoryLayout<Int32>.size

        // Skip the exec path string, then the NUL padding before argv[0].
        while cursor < size, buffer[cursor] != 0 { cursor += 1 }
        while cursor < size, buffer[cursor] == 0 { cursor += 1 }

        while cursor < size, args.count < Int(argc) {
            let start = cursor
            while cursor < size, buffer[cursor] != 0 { cursor += 1 }
            if cursor > start {
                let bytes = buffer[start..<cursor].map { UInt8(bitPattern: $0) }
                if let text = String(bytes: bytes, encoding: .utf8) { args.append(text) }
            }
            cursor += 1
        }
        return args
    }

    /// `--resume <uuid>` / `-r <uuid>` gives an exact process-to-session map.
    static func resumedSessionID(_ argv: [String]) -> String? {
        for (index, arg) in argv.enumerated() where arg == "--resume" || arg == "-r" {
            let next = index + 1
            if next < argv.count, !argv[next].hasPrefix("-") { return argv[next] }
        }
        return nil
    }
}
