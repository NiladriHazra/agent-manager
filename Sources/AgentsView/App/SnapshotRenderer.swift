import SwiftUI

/// `agents-view --snapshot <path>` renders the dropdown to a PNG offscreen.
///
/// Exists so the interface can be checked against real data without clicking
/// the menu bar, which needs Accessibility permission that a build machine or
/// CI runner will not have.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              index + 1 < CommandLine.arguments.count
        else { return }

        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let model = AppModel()

        final class Flag: @unchecked Sendable { var done = false }
        let flag = Flag()

        // Give the providers time to fill in before drawing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            render(model: model, to: output)
            flag.done = true
        }

        let deadline = Date().addingTimeInterval(60)
        while !flag.done, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        exit(flag.done ? 0 : 1)
    }

    private static func render(model: AppModel, to output: URL) {
        // ImageRenderer does not lay out ScrollView content offscreen, so the
        // rows are drawn in a plain stack here. The live menu keeps the scroll.
        let view = VStack(alignment: .leading, spacing: 6) {
            ForEach(model.visibleSnapshots) { AgentRowView(snapshot: $0) }
        }
        .padding(10)
        .frame(width: 320)
        .background(Theme.surface)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("render failed")
            return
        }
        try? png.write(to: output)
        print("wrote \(output.path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}
