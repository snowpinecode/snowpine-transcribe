import AppKit
import SnowpineTranscribeCore
import SwiftUI

/// Draws the real screens with a made-up meeting, for the README, the web page and the smoke test.
/// Nothing is shown on screen and no audio is touched.
enum DocsRenderer {
    static let sampleLines: [(Double, String)] = [
        (0, "Thanks for making time today."),
        (4.2, "I want to walk through how orders come in, because that's where most of the day goes."),
        (11.5, "Right now every order lands in one shared inbox, and two of us sort it by hand."),
        (19.3, "The photos are the slowest part, since we have to match each one to an order."),
        (27.8, "If you could change one thing, what would it be?"),
        (31.4, "Honestly, I'd stop typing the same three replies all morning."),
        (38.6, "Got it. Let's look at those three replies next, and I'll note the order numbers."),
        (47.1, "We also take bookings by text, and those get lost over the weekend."),
        (55.9, "So the plan is one place for orders, and a booking link for the weekend."),
    ]

    static var sample: Transcript {
        let lines = sampleLines.enumerated().map { index, line in
            TranscriptSegment(id: index, start: line.0 + 1520, end: line.0 + 1523, text: line.1)
        }
        return Transcript(title: "Client visit", sourceFileName: "Client visit.m4a", duration: 5468, localeIdentifier: "en-US", segments: lines)
    }

    @MainActor
    static func run(outputDirectory: String) -> Int32 {
        let folder = URL(fileURLWithPath: outputDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                try render(TranscriptPicture(), appearance: appearance, to: folder.appendingPathComponent("transcript-\(name).png"))
                try render(StartPicture(), appearance: appearance, to: folder.appendingPathComponent("start-\(name).png"))
                try render(WorkingPicture(), appearance: appearance, to: folder.appendingPathComponent("working-\(name).png"))
            }
        } catch {
            FileHandle.standardError.write(Data("DOCS FAIL: \(error.localizedDescription)\n".utf8))
            return 1
        }
        print("DOCS OK folder=\(folder.path)")
        return 0
    }

    /// Checks the screens draw and the brand fonts load. The speech engine has its own check: scripts/check-engine.sh.
    @MainActor
    static func smokeTest(outputDirectory: String) -> Int32 {
        guard BrandFonts.allLoaded else {
            FileHandle.standardError.write(Data("SMOKE FAIL: the brand fonts did not load\n".utf8))
            return 1
        }
        let code = run(outputDirectory: outputDirectory)
        if code == 0 { print("SMOKE OK") }
        return code
    }

    @MainActor
    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) throws {
        let size = NSSize(width: 900, height: 620)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError(errorDescription: "no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw RenderError(errorDescription: "no png") }
        try png.write(to: url)
    }

    private struct RenderError: LocalizedError { let errorDescription: String? }
}

@MainActor private func pictureModel() -> AppModel {
    let model = AppModel(store: LibraryStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("snowpine-transcribe-pictures")))
    model.library = [DocsRenderer.sample]
    model.languages = [Locale(identifier: "en-US")]
    return model
}

private struct PictureFrame<Content: View>: View {
    let content: Content
    var body: some View {
        content.background(Color(nsColor: .windowBackgroundColor)).tint(Brand.action)
    }
}

private struct TranscriptPicture: View {
    var body: some View {
        let model = MainActor.assumeIsolated { pictureModel() }
        return PictureFrame(content: TranscriptView(model: model, player: model.player, transcript: DocsRenderer.sample))
    }
}

private struct StartPicture: View {
    var body: some View {
        let model = MainActor.assumeIsolated { pictureModel() }
        return PictureFrame(content: StartView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity))
    }
}

private struct WorkingPicture: View {
    var body: some View {
        let lines = Array(DocsRenderer.sample.segments.prefix(5))
        return PictureFrame(content: WorkingView(job: AppModel.Job(fileName: "Client visit.m4a", fraction: 0.42, status: "Transcribing", lines: lines), waiting: 0) {})
    }
}
