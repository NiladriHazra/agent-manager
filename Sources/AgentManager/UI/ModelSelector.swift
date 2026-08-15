import SwiftUI

/// Which model's usage the row is showing.
///
/// An agent's week is rarely one model. The selector defaults to the one used
/// most recently — the model you are on right now — and "All models" totals
/// them, so the headline is never a figure nobody can account for.
struct ModelSelector: View {
    let models: [ModelUsage]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button("All models") { selection = nil }
            Divider()
            ForEach(models) { model in
                Button(model.label) { selection = model.model }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentLabel)
                    .font(BrandFont.body(9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentLabel: String {
        guard let selection else { return "all models" }
        return models.first { $0.model == selection }?.label ?? selection
    }
}
