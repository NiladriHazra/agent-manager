import Foundation

/// `agent-manager --diagnose` prints exactly what each provider read, so a wrong
/// number in the menu bar can be traced to its source without guessing.
enum Diagnostics {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--diagnose") else { return }

        // The main thread must keep running its runloop rather than block:
        // parking it here at process start starves the concurrency runtime and
        // the task never gets scheduled at all.
        final class Flag: @unchecked Sendable { var done = false }
        let flag = Flag()

        Task.detached(priority: .high) {
            await report()
            flag.done = true
        }

        let deadline = Date().addingTimeInterval(120)
        while !flag.done, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if !flag.done { print("\ntimed out after 120s") }
        exit(0)
    }

    private static func report() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let index = UsageIndex()

        print("agent-manager diagnostics\n")

        let clock = Date()
        let running = ProcessScanner.runningAgents()
        print("processes  \(running.count) agent(s) in \(ms(since: clock))")
        for session in running {
            print("           pid \(session.pid)  \(session.agent.rawValue)  cwd=\(session.cwd ?? "?")")
        }

        let providers = allProviders(index: index)

        print("")
        for provider in providers {
            let started = Date()
            let snapshot = await provider.probe(sessions: running.filter { $0.agent == provider.agent })
            var line = "\(pad(provider.agent.rawValue, 12))\(pad(describe(snapshot.availability), 16))\(pad(ms(since: started), 9))"
            if let quota = snapshot.quota {
                line += "quota \(Int(quota.remainingPercent))% left of \(quota.windowLabel), resets \(QuotaBar.countdown(to: quota.resetsAt))"
                if let observed = snapshot.quotaObserved {
                    line += "  [read \(QuotaBar.ago(observed))]"
                }
            }
            if let usage = snapshot.usage {
                if snapshot.quota != nil { line += "  " }
                line += "usage out=\(usage.output) in=\(usage.input) cacheRead=\(usage.cacheRead)"
                if let cost = usage.cost { line += String(format: " cost=$%.2f", cost) }
            } else if snapshot.quota == nil {
                line += "no numbers"
            }
            print(line)
            for session in snapshot.sessions {
                let state: String
                switch session.activity {
                case .working: state = "WORKING"
                case .waiting(let since): state = "WAITING " + (since.map { QuotaBar.ago($0) } ?? "")
                case .idle(let since): state = "idle " + (since.map { QuotaBar.ago($0) } ?? "(unknown)")
                }
                print("            \u{21B3} \(pad(state, 16))\(session.activityLine)")
            }
        }
    }

    private static func describe(_ availability: Availability) -> String {
        switch availability {
        case .ready: return "ready"
        case .loading: return "loading"
        case .notInstalled: return "not installed"
        case .unavailable(let reason): return reason
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func ms(since: Date) -> String {
        String(format: "%.0fms", Date().timeIntervalSince(since) * 1000)
    }
}
