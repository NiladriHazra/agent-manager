import Foundation

// Explicit entry point rather than @main: the diagnostics mode has to run and
// exit before SwiftUI takes over the process, which it cannot do from an App
// initializer.
// Line-buffered so diagnostics stream out even when redirected to a file.
setvbuf(stdout, nil, _IOLBF, 0)
Diagnostics.runIfRequested()
MainActor.assumeIsolated { SnapshotRenderer.runIfRequested() }
AgentsViewApp.main()
