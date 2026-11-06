import Foundation
import SnowpineTranscribeCore

BrandFonts.register()

// `SnowpineTranscribe --transcribe <file>` prints a transcript without opening a window.
if let flag = CommandLine.arguments.firstIndex(of: "--transcribe"), CommandLine.arguments.indices.contains(flag + 1) {
    let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    let done = DispatchSemaphore(value: 0)
    let wanted = CommandLine.arguments.firstIndex(of: "--locale").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? Locale(identifier: CommandLine.arguments[$0 + 1]) : nil }
    Task {
        do {
            let began = Date()
            let locale: Locale
            if let wanted { locale = wanted } else { locale = await SpeechEngine.defaultLanguage() }
            let result = try await SpeechEngine.transcribe(url: url, locale: locale) { update in
                FileHandle.standardError.write(Data("\(Int(update.fraction * 100))% \(update.status)\n".utf8))
            }
            let transcript = Transcript(title: url.deletingPathExtension().lastPathComponent, sourceFileName: url.lastPathComponent,
                                        duration: result.duration, localeIdentifier: result.locale.identifier, segments: result.segments)
            print(TranscriptExport.text.render(transcript), terminator: "")
            let spent = Date().timeIntervalSince(began)
            FileHandle.standardError.write(Data(String(format: "TRANSCRIBE OK lines=%d words=%d audio=%.1fs took=%.1fs\n", result.segments.count, transcript.wordCount, result.duration, spent).utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("TRANSCRIBE FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    done.wait()
}

if let flag = CommandLine.arguments.firstIndex(of: "--smoke-test") {
    let folder = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : NSTemporaryDirectory()
    exit(MainActor.assumeIsolated { DocsRenderer.smokeTest(outputDirectory: folder) })
}

if let flag = CommandLine.arguments.firstIndex(of: "--render-docs") {
    let folder = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : "docs"
    exit(MainActor.assumeIsolated { DocsRenderer.run(outputDirectory: folder) })
}

// `--launch-check` opens the model and checks the sandbox and fonts without showing a window (used by CI).
if CommandLine.arguments.contains("--launch-check") {
    let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    let ok = sandboxed && BrandFonts.allLoaded
    print("LAUNCH \(ok ? "OK" : "FAIL") sandboxed=\(sandboxed) fonts=\(BrandFonts.allLoaded)")
    exit(ok ? 0 : 1)
}

SnowpineTranscribeApp.main()
