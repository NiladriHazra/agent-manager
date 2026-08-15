import AppKit

/// The menu bar mark, drawn rather than borrowed from SF Symbols.
///
/// It is a hub with three orbiting nodes: one manager, several agents. Rendered
/// as a template image so macOS tints it correctly in light and dark bars and
/// when the menu is highlighted. The centre fills in when something is working.
enum MenuBarGlyph {
    nonisolated(unsafe) private static var cache: [Bool: NSImage] = [:]
    nonisolated(unsafe) private static var klipeoCache: [Bool: NSImage] = [:]

    /// Klipeo's own mark, as a template so macOS tints it for the current menu
    /// bar. Built with the drawing-handler initialiser rather than lockFocus,
    /// which can hand back an invalid image mid-render.
    static func klipeo(working: Bool) -> NSImage {
        if let cached = klipeoCache[working] { return cached }
        guard let url = Bundle.module.url(forResource: "klipeo-mark", withExtension: "png"),
              let source = NSImage(contentsOf: url), source.isValid
        else { return image(working: working) }

        let side: CGFloat = 16
        let rendered = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver,
                        fraction: working ? 1.0 : 0.5)
            return true
        }
        guard rendered.isValid else { return image(working: working) }
        rendered.isTemplate = true
        klipeoCache[working] = rendered
        return rendered
    }

    static func image(working: Bool) -> NSImage {
        if let cached = cache[working] { return cached }

        let side: CGFloat = 17
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()

        let centre = CGPoint(x: side / 2, y: side / 2)
        let orbit: CGFloat = side * 0.375
        let nodeRadius: CGFloat = side * 0.086
        let hubRadius: CGFloat = side * 0.132

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Three nodes on an even orbit, with spokes back to the hub.
        for index in 0..<3 {
            let angle = CGFloat(index) * (2 * .pi / 3) - .pi / 2
            let node = CGPoint(
                x: centre.x + cos(angle) * orbit,
                y: centre.y + sin(angle) * orbit
            )

            let spoke = NSBezierPath()
            spoke.move(to: CGPoint(
                x: centre.x + cos(angle) * (hubRadius + side * 0.041),
                y: centre.y + sin(angle) * (hubRadius + side * 0.041)
            ))
            spoke.line(to: CGPoint(
                x: node.x - cos(angle) * nodeRadius,
                y: node.y - sin(angle) * nodeRadius
            ))
            spoke.lineWidth = side * 0.052
            spoke.lineCapStyle = .round
            spoke.stroke()

            let dot = NSBezierPath(ovalIn: NSRect(
                x: node.x - nodeRadius, y: node.y - nodeRadius,
                width: nodeRadius * 2, height: nodeRadius * 2
            ))
            dot.fill()
        }

        let hub = NSBezierPath(ovalIn: NSRect(
            x: centre.x - hubRadius, y: centre.y - hubRadius,
            width: hubRadius * 2, height: hubRadius * 2
        ))
        if working {
            hub.fill()
        } else {
            hub.lineWidth = side * 0.072
            hub.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        cache[working] = image
        return image
    }
}
