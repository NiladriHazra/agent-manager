import AppKit
import SwiftUI

/// The real macOS material, the same one Control Center and system popovers
/// use. A flat colour cannot reproduce it: this samples and blurs the desktop
/// behind the window, so the panel picks up whatever is underneath.
enum RenderMode {
    /// ImageRenderer cannot rasterize an NSView, so offscreen snapshots fall
    /// back to a flat surface instead of drawing an unsupported placeholder.
    nonisolated(unsafe) static var isOffscreen = false
}
