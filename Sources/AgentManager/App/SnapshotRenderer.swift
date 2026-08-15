import SwiftUI

/// `agent-manager --snapshot <path>` renders the dropdown to a PNG offscreen.
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
        RenderMode.isOffscreen = true
        // Renders the real panel, so what this writes is what the menu shows.
        // The window material cannot be sampled offscreen, so it is stood in
        // with the surface colour here.
        // The side panel opens from onAppear, after ImageRenderer has already
        // measured, so the width is stated here rather than inferred.
        let view = MenuContentView(model: model)
            .frame(width: 601, alignment: .leading)
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
