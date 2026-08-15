import SwiftUI

/// Shows the menu bar as it will actually look, from the same live readings,
/// so a combination of switches can be judged without closing Settings.
struct MenuBarPreview: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        HStack(spacing: 7) {
            Text("Preview")
                .font(BrandFont.body(10))
                .foregroundStyle(.white.opacity(0.35))

            HStack(spacing: 6) {
                Image(nsImage: MenuBarGlyph.klipeo(working: model.workingCount > 0))
                    .renderingMode(.template)
                    .foregroundStyle(.white)

                if prefs.showAgentCount {
                    Text("\(model.workingCount)")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                }

                if prefs.showPercentages {
                    let readings = Array(model.menuBarReadings.prefix(prefs.maxMenuBarAgents))
                    ForEach(readings, id: \.agent) { reading in
                        HStack(spacing: 3) {
                            if readings.count > 1 {
                                AgentLogo(agent: reading.agent).frame(width: 11, height: 11)
                            }
                            Text("\(reading.percent)%")
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    if readings.isEmpty {
                        Text("no readings yet")
                            .font(BrandFont.body(10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .glassTile(radius: 13)
        }
    }
}
