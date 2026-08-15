// swift-tools-version:5.9
import PackageDescription

// agents-view: a macOS menu bar app that shows which coding agents are running
// and how much weekly quota is left. Built with SwiftPM only (no Xcode);
// scripts/build.sh assembles the .app bundle from the release binary.
let package = Package(
    name: "AgentManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentManager",
            path: "Sources/AgentManager",
            resources: [.process("Resources")]
        )
    ]
)
