import AVFoundation
import CoreMedia
import Foundation
import SnowpineTranscribeCore
import Speech

/// Runs Apple's on-device speech engine over a recording. Audio is read from the file
/// and handed straight to the engine; it is never copied, saved or sent anywhere.
enum SpeechEngine {
    enum Problem: LocalizedError {
        case unsupportedLanguage(String)
        case noAudio
        case unreadable(String)
        case engineUnavailable
        case modelDownload(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage(let name):
                return "This Mac can't transcribe \(name) on-device. Choose another language."
            case .noAudio:
                return "That file has no sound to transcribe."
            case .unreadable:
                return "That file couldn't be read. It may be damaged, or it may not be a recording."
            case .modelDownload(let detail):
                return "macOS couldn't get the speech model for this language. Check your internet connection, then try again. (\(detail))"
            case .engineUnavailable:
                return "On-device speech isn't available on this Mac."
            }
        }
    }

    struct Update: Sendable {
        var fraction: Double
        var status: String
        var newSegments: [TranscriptSegment]
    }

    /// Languages this Mac can transcribe, sorted by display name.
    static func languages() async -> [Locale] {
        let all = await SpeechTranscriber.supportedLocales
        return all.sorted { name(of: $0) < name(of: $1) }
    }

    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    static func defaultLanguage() async -> Locale {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en-US")
    }

    static func transcribe(url: URL, locale requested: Locale,
                           onUpdate: @escaping @Sendable (Update) -> Void) async throws -> (segments: [TranscriptSegment], duration: Double, locale: Locale) {
        guard SpeechTranscriber.isAvailable else { throw Problem.engineUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw Problem.unsupportedLanguage(name(of: requested))
        }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        try await prepareModel(for: transcriber, onUpdate: onUpdate)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Problem.engineUnavailable
        }
        let source = try await AudioSource(url: url, format: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)

        let duration = source.duration
        let results = Task { () -> [TranscriptSegment] in
            var all: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let lines = SegmentBuilder.segments(from: words(in: result.text, fallback: result.range), startingID: all.count)
                all.append(contentsOf: lines)
                let heard = result.range.end.seconds
                let fraction = duration > 0 && heard.isFinite ? min(1, heard / duration) : 0
                onUpdate(Update(fraction: fraction, status: "Transcribing", newSegments: lines))
            }
            return all
        }

        do {
            try await withTaskCancellationHandler {
                if let end = try await analyzer.analyzeSequence(source) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } onCancel: {
                results.cancel()
            }
            try Task.checkCancellation()
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        let segments = try await results.value
        if let failure = source.failure { throw failure }
        return (segments, duration, locale)
    }

    /// macOS downloads and keeps the speech model itself. The app never touches the network.
    private static func prepareModel(for transcriber: SpeechTranscriber, onUpdate: @escaping @Sendable (Update) -> Void) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else { return }
        guard status != .unsupported else { throw Problem.engineUnavailable }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        onUpdate(Update(fraction: 0, status: "macOS is getting the speech model for this language", newSegments: []))
        do {
            try await request.downloadAndInstall()
        } catch {
            throw Problem.modelDownload(error.localizedDescription)
        }
    }

    /// The words of a result with their times. If the engine gave no word times, the whole result becomes one word run.
    private static func words(in text: AttributedString, fallback: CMTimeRange) -> [TimedWord] {
        var out: [TimedWord] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let cleaned = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] ?? fallback
            let start = range.start.seconds, end = range.end.seconds
            let pieces = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for word in pieces {
                out.append(TimedWord(text: word, start: start.isFinite ? start : 0, end: end.isFinite ? end : 0))
            }
        }
        return out
    }
}

/// Reads a recording's sound as the engine asks for it, so a long file never piles up in memory.
final class AudioSource: AsyncSequence, @unchecked Sendable {
    typealias Element = AnalyzerInput

    let duration: Double
    private(set) var failure: Error?
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let format: AVAudioFormat
    private let lock = NSLock()

    init(url: URL, format: AVAudioFormat) async throws {
        self.format = format
        guard url.isFileURL else { throw SpeechEngine.Problem.unreadable("Only files on this Mac can be transcribed.") }
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw SpeechEngine.Problem.unreadable(error.localizedDescription)
        }
        guard let track = tracks.first else { throw SpeechEngine.Problem.noAudio }
        duration = (try? await asset.load(.duration).seconds) ?? 0
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SpeechEngine.Problem.unreadable(error.localizedDescription)
        }
        let isFloat = format.commonFormat == .pcmFormatFloat32 || format.commonFormat == .pcmFormatFloat64
        let bits: Int
        switch format.commonFormat {
        case .pcmFormatInt16: bits = 16
        case .pcmFormatInt32, .pcmFormatFloat32: bits = 32
        case .pcmFormatFloat64: bits = 64
        default: bits = 16
        }
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw SpeechEngine.Problem.unreadable("The sound format isn't supported.") }
        reader.add(output)
        guard reader.startReading() else {
            throw SpeechEngine.Problem.unreadable(reader.error?.localizedDescription ?? "It may be damaged.")
        }
    }

    struct Iterator: AsyncIteratorProtocol {
        let source: AudioSource
        mutating func next() async throws -> AnalyzerInput? {
            try Task.checkCancellation()
            return try source.nextBuffer()
        }
    }

    func makeAsyncIterator() -> Iterator { Iterator(source: self) }

    private func nextBuffer() throws -> AnalyzerInput? {
        lock.lock(); defer { lock.unlock() }
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed {
                let error = SpeechEngine.Problem.unreadable(reader.error?.localizedDescription ?? "Reading stopped early.")
                failure = error
                throw error
            }
            return nil
        }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return try nextUnlocked() }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else {
            let error = SpeechEngine.Problem.unreadable("The sound couldn't be decoded (\(status)).")
            failure = error
            throw error
        }
        return AnalyzerInput(buffer: buffer, bufferStartTime: nil)
    }

    private func nextUnlocked() throws -> AnalyzerInput? {
        lock.unlock(); defer { lock.lock() }
        return try nextBuffer()
    }
}
