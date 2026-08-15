import SwiftUI

/// The two windows as one split bar: daily on the left, weekly on the right.
///
/// Only Codex publishes a real limit, so the two halves do not mean the same
/// thing for every agent and the bar must not pretend they do. A half backed by
/// a vendor limit fills to that percentage. A half backed only by locally
/// counted tokens fills relative to the agent's own recent peak, and is drawn
/// dimmer with the label `counted` so it is never mistaken for a quota.
struct WindowBar: View {
    let dayFraction: Double
    let weekFraction: Double
    let dayIsQuota: Bool
    let weekIsQuota: Bool
    /// The agent's own colour, measured from its mark.
    let tint: Color

    private let height: CGFloat = 5

    var body: some View {
        HStack(spacing: 4) {
            half(fraction: dayFraction, isQuota: dayIsQuota)
            half(fraction: weekFraction, isQuota: weekIsQuota)
        }
        .frame(height: height)
    }

    private func half(fraction: Double, isQuota: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Capsule()
                    .fill(
                        LinearGradient(
                            // A vendor-published limit is drawn at full
                            // strength; locally counted tokens are drawn in the
                            // same hue but muted, so the two never look alike.
                            colors: isQuota
                                ? [tint.opacity(0.95), tint]
                                : [tint.opacity(0.5), tint.opacity(0.34)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}
