import AppKit
import SwiftUI

/// The colour a bar takes for a given agent, read from the agent's own mark.
///
/// Rather than hand-assigning colours, the mark is rasterized once and its
/// dominant saturated hue is measured. Claude's orange and Gemini's blue come
/// out of the artwork itself. Several vendors ship a purely monochrome mark —
/// there is no logo colour to match — and those fall back to the Klipeo accent
/// rather than having a colour invented for them.
enum LogoTint {
    @MainActor private static var cache: [AgentID: Color] = [:]

    @MainActor
    static func color(for agent: AgentID) -> Color {
        if let cached = cache[agent] { return cached }
        let color = measure(agent) ?? Theme.accent
        cache[agent] = color
        return color
    }

    @MainActor
    private static func measure(_ agent: AgentID) -> Color? {
        let url = Bundle.module.url(forResource: agent.logoName, withExtension: "svg")
            ?? Bundle.module.url(forResource: agent.logoName, withExtension: "png")
        guard let url,
              let image = NSImage(contentsOf: url),
              let bitmap = rasterize(image) else { return nil }

        var best: (weight: Int, hue: CGFloat, saturation: CGFloat)?
        var buckets: [Int: (count: Int, hue: CGFloat, saturation: CGFloat)] = [:]

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let raw = bitmap.colorAt(x: x, y: y),
                      let color = raw.usingColorSpace(.sRGB), color.alphaComponent > 0.35
                else { continue }

                var hue: CGFloat = 0, saturation: CGFloat = 0
                var brightness: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                guard saturation > 0.28, brightness > 0.25 else { continue }

                let bucket = Int(hue * 24)
                let entry = buckets[bucket] ?? (0, hue, saturation)
                buckets[bucket] = (entry.count + 1, hue, max(entry.saturation, saturation))
            }
        }

        for (_, entry) in buckets where entry.count > (best?.weight ?? 0) {
            best = (entry.count, entry.hue, entry.saturation)
        }

        // A handful of stray anti-aliased pixels is not a brand colour.
        guard let best, best.weight >= 12 else { return nil }
        return Color(hue: best.hue, saturation: min(best.saturation, 0.78), brightness: 0.92)
    }

    @MainActor
    private static func rasterize(_ image: NSImage) -> NSBitmapImageRep? {
        let side = 48
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
