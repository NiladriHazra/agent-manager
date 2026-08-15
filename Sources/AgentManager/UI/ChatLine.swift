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
            if chat.contextTokens > 0 { contextBar }
            tokenLine
        }
    }

    /// A ring, not a second long bar. The window bar directly above is already
    /// a full-width track, and two stacked bars read as one measurement split
    /// in half rather than two unrelated things.
    private var contextBar: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: chat.contextFraction)
                    .stroke(contextTone, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)

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
    }

    private var tokenLine: some View {
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
                if let cost = chat.cost, cost > 0 {
                    Text(String(format: "$%.2f", cost)).foregroundStyle(.white.opacity(0.5))
                } else if chat.turns > 0 {
                    Text("\(chat.turns) turns").foregroundStyle(.white.opacity(0.3))
                }
            }
            .font(BrandFont.body(9.5))
            .monospacedDigit()
    }

    private func short(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.0fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}
