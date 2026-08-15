import SwiftUI

/// What this one chat has spent, and how close it is to compaction.
///
/// The context bar is the useful part mid-session: it is the model's live
/// working set, so it climbs through a long conversation and drops sharply the
/// moment the agent compacts. The window tier is inferred from the reading
/// itself, which is why it is written as an approximation.
struct ChatLine: View {
    let chat: ChatStats
    let tint: Color

    private var contextTone: Color {
        switch chat.contextFraction {
        case 0.9...: return StatusPill.Tone.negative.dot
        case 0.75...: return StatusPill.Tone.warning.dot
        default: return tint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.13))
                    Capsule()
                        .fill(contextTone)
                        .frame(width: max(3, geo.size.width * chat.contextFraction))
                }
            }
            .frame(height: 4)

            HStack(spacing: 5) {
                Text("context")
                    .foregroundStyle(.white.opacity(0.38))
                Text("\(short(chat.contextTokens)) / \(short(chat.contextWindow))")
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                Text("(\(Int(chat.contextFraction * 100))%)")
                    .foregroundStyle(contextTone)
                Spacer(minLength: 4)
                if let model = chat.modelLabel {
                    Text(model).foregroundStyle(.white.opacity(0.35))
                }
            }
            .font(BrandFont.body(9.5))

            HStack(spacing: 5) {
                Text("in \(short(chat.input + chat.cacheCreate))")
                    .foregroundStyle(.white.opacity(0.55))
                Text("·").foregroundStyle(.white.opacity(0.25))
                Text("out \(short(chat.output))")
                    .foregroundStyle(.white.opacity(0.55))
                if chat.thinking > 0 {
                    Text("·").foregroundStyle(.white.opacity(0.25))
                    Text("thinking \(short(chat.thinking))")
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 4)
                if chat.turns > 0 {
                    Text("\(chat.turns) turns").foregroundStyle(.white.opacity(0.3))
                }
            }
            .font(BrandFont.body(9.5))
            .monospacedDigit()
        }
    }

    private func short(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}
