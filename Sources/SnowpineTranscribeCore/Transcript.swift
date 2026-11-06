import Foundation

/// One line of a transcript, with where it sits in the recording.
public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: Int, start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A finished transcript. It holds text and times only, never the audio.
public struct Transcript: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceFileName: String
    public var createdAt: Date
    public var duration: Double
    public var localeIdentifier: String
    public var segments: [TranscriptSegment]

    public init(id: UUID = UUID(), title: String, sourceFileName: String, createdAt: Date = Date(),
                duration: Double, localeIdentifier: String, segments: [TranscriptSegment]) {
        self.id = id
        self.title = title
        self.sourceFileName = sourceFileName
        self.createdAt = createdAt
        self.duration = duration
        self.localeIdentifier = localeIdentifier
        self.segments = segments
    }

    public var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
    }
}

/// One recognized word and its time in the recording.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Turns recognized words into readable lines. A line ends after a sentence, at a long
/// pause, or when it would run too long to read and search comfortably.
public enum SegmentBuilder {
    public static let pauseSeconds = 1.2
    public static let maxSeconds = 20.0
    public static let maxCharacters = 240

    public static func segments(from words: [TimedWord], startingID: Int = 0) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var current: [TimedWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            result.append(TranscriptSegment(id: startingID + result.count, start: first.start, end: last.end, text: text))
            current = []
        }

        for word in words where !word.text.isEmpty {
            if let last = current.last {
                let pause = word.start - last.end
                let length = current.reduce(0) { $0 + $1.text.count + 1 } + word.text.count
                if pause >= pauseSeconds || word.end - (current.first?.start ?? word.start) > maxSeconds || length > maxCharacters {
                    flush()
                }
            }
            current.append(word)
            if endsSentence(word.text), (current.last?.end ?? 0) - (current.first?.start ?? 0) >= 1 { flush() }
        }
        flush()
        return result
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"')]\u{201D}\u{2019}")).last else { return false }
        return ".!?".contains(last)
    }
}

/// How times are written.
public enum TimeFormat {
    /// 2:05 or 1:02:05, for reading.
    public static func clock(_ seconds: Double) -> String {
        let total = wholeSeconds(seconds)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 00:02:05,250 for SubRip subtitles.
    public static func srt(_ seconds: Double) -> String { stamp(seconds, separator: ",") }

    /// 00:02:05.250 for WebVTT subtitles.
    public static func vtt(_ seconds: Double) -> String { stamp(seconds, separator: ".") }

    private static func stamp(_ seconds: Double, separator: String) -> String {
        let safe = safeSeconds(seconds)
        let totalMilliseconds = Int((safe * 1000).rounded())
        let ms = totalMilliseconds % 1000
        let total = totalMilliseconds / 1000
        return String(format: "%02d:%02d:%02d%@%03d", total / 3600, total % 3600 / 60, total % 60, separator, ms)
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        Int(safeSeconds(seconds))
    }

    /// A damaged file can hold any number, so keep times in a range that converts safely.
    private static func safeSeconds(_ seconds: Double) -> Double {
        seconds.isFinite ? min(max(0, seconds), 1_000_000_000) : 0
    }
}

/// Finds lines by what was said, ignoring case and accents.
public enum TranscriptSearch {
    public static func matches(_ query: String, in segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return segments }
        return segments.filter { $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// The file types a transcript can be saved as.
public enum TranscriptExport: String, CaseIterable, Identifiable, Sendable {
    case text, markdown, srt, vtt, json

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .json: return "json"
        }
    }

    public var label: String {
        switch self {
        case .text: return "Plain text with times (.txt)"
        case .markdown: return "Markdown (.md)"
        case .srt: return "Subtitles (.srt)"
        case .vtt: return "Web subtitles (.vtt)"
        case .json: return "JSON (.json)"
        }
    }

    public func render(_ transcript: Transcript) -> String {
        let lines = transcript.segments
        switch self {
        case .text:
            return lines.map { "[\(TimeFormat.clock($0.start))] \($0.text)" }.joined(separator: "\n") + "\n"
        case .markdown:
            let body = lines.map { "**\(TimeFormat.clock($0.start))** \($0.text)" }.joined(separator: "\n\n")
            return "# \(transcript.title)\n\n\(body)\n"
        case .srt:
            return lines.enumerated().map { index, line in
                "\(index + 1)\n\(TimeFormat.srt(line.start)) --> \(TimeFormat.srt(line.end))\n\(Self.cueText(line.text))\n"
            }.joined(separator: "\n")
        case .vtt:
            let cues = lines.map { "\(TimeFormat.vtt($0.start)) --> \(TimeFormat.vtt($0.end))\n\(Self.cueText($0.text))\n" }
            return "WEBVTT\n\n" + cues.joined(separator: "\n")
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(transcript)) ?? Data()
            return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        }
    }

    /// A blank line or a stray cue arrow in the text would break a subtitle file.
    private static func cueText(_ text: String) -> String {
        text.replacingOccurrences(of: "-->", with: "->")
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
    }
}
