import Foundation
import Testing
@testable import SnowpineTranscribeCore

private func word(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

private let sample = Transcript(title: "Visit", sourceFileName: "visit.m4a", createdAt: Date(timeIntervalSince1970: 0), duration: 75,
                                localeIdentifier: "en-US", segments: [
    TranscriptSegment(id: 0, start: 1.25, end: 3.5, text: "Thanks for joining."),
    TranscriptSegment(id: 1, start: 65, end: 70, text: "Résumé --> next\nsteps."),
])

@Test func clockStaysShortUntilAnHour() {
    #expect(TimeFormat.clock(0) == "0:00")
    #expect(TimeFormat.clock(65.9) == "1:05")
    #expect(TimeFormat.clock(3725) == "1:02:05")
}

@Test func badTimesNeverCrash() {
    #expect(TimeFormat.clock(.nan) == "0:00")
    #expect(TimeFormat.clock(-5) == "0:00")
    #expect(TimeFormat.srt(.infinity) == "00:00:00,000")
}

@Test func subtitleTimesCarryMilliseconds() {
    #expect(TimeFormat.srt(3725.25) == "01:02:05,250")
    #expect(TimeFormat.vtt(1.999) == "00:00:01.999")
}

@Test func roundingUpToTheNextSecondCarries() {
    #expect(TimeFormat.srt(59.9996) == "00:01:00,000")
}

@Test func sentencesBecomeLines() {
    let lines = SegmentBuilder.segments(from: [word("Thanks", 0, 0.4), word("for", 0.4, 0.6), word("joining.", 0.6, 1.2),
                                               word("Next", 1.3, 1.6), word("steps.", 1.6, 2.4)])
    #expect(lines.map(\.text) == ["Thanks for joining.", "Next steps."])
    #expect(lines[1].start == 1.3 && lines[1].end == 2.4)
}

@Test func aLongPauseStartsANewLine() {
    let lines = SegmentBuilder.segments(from: [word("one", 0, 0.5), word("two", 5, 5.5)])
    #expect(lines.map(\.text) == ["one", "two"])
}

@Test func endlessTalkStillBreaksUp() {
    let words = (0..<400).map { word("word", Double($0) * 0.3, Double($0) * 0.3 + 0.25) }
    let lines = SegmentBuilder.segments(from: words)
    #expect(lines.count > 1)
    #expect(lines.allSatisfy { $0.text.count <= SegmentBuilder.maxCharacters && $0.end - $0.start <= SegmentBuilder.maxSeconds + 1 })
    #expect(lines.reduce(0) { $0 + $1.text.split(separator: " ").count } == 400)
}

@Test func lineIDsContinueFromEarlierResults() {
    let lines = SegmentBuilder.segments(from: [word("Hello.", 0, 1.5)], startingID: 7)
    #expect(lines.first?.id == 7)
}

@Test func searchIgnoresCaseAndAccents() {
    #expect(TranscriptSearch.matches("RESUME", in: sample.segments).map(\.id) == [1])
    #expect(TranscriptSearch.matches("  ", in: sample.segments).count == 2)
    #expect(TranscriptSearch.matches("missing", in: sample.segments).isEmpty)
}

@Test func plainTextHasTimes() {
    #expect(TranscriptExport.text.render(sample).hasPrefix("[0:01] Thanks for joining.\n"))
}

@Test func subtitlesStayValidWhateverWasSaid() {
    let srt = TranscriptExport.srt.render(sample)
    #expect(srt.hasPrefix("1\n00:00:01,250 --> 00:00:03,500\nThanks for joining.\n\n2\n"))
    #expect(srt.contains("Résumé -\u{203A} next steps."))
    #expect(srt.components(separatedBy: "-->").count == 3)
    #expect(TranscriptExport.vtt.render(sample).hasPrefix("WEBVTT\n\n00:00:01.250 --> 00:00:03.500\n"))
}

@Test func jsonExportRoundTrips() throws {
    let data = Data(TranscriptExport.json.render(sample).utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(Transcript.self, from: data) == sample)
}

@Test func wordCountCountsWords() {
    #expect(sample.wordCount == 7)
}

private func tempStore() -> LibraryStore {
    LibraryStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
}

@Test func libraryKeepsAndDeletesTranscripts() throws {
    let store = tempStore()
    defer { try? FileManager.default.removeItem(at: store.folder) }
    var older = sample
    older.id = UUID()
    older.createdAt = Date(timeIntervalSince1970: 100)
    var newer = sample
    newer.id = UUID()
    newer.createdAt = Date(timeIntervalSince1970: 200)
    try store.save(older)
    try store.save(newer)
    try store.saveBookmark(Data([1, 2]), for: older.id)
    #expect(try store.load().transcripts.map(\.id) == [newer.id, older.id])
    #expect(store.bookmark(for: older.id) == Data([1, 2]))
    try store.delete(older.id)
    #expect(try store.load().transcripts.map(\.id) == [newer.id])
    #expect(store.bookmark(for: older.id) == nil)
}

@Test func aDamagedFileIsCountedNotTreatedAsEmpty() throws {
    let store = tempStore()
    defer { try? FileManager.default.removeItem(at: store.folder) }
    try store.save(sample)
    try Data("not json".utf8).write(to: store.folder.appendingPathComponent("broken.json"))
    let loaded = try store.load()
    #expect(loaded.transcripts.count == 1)
    #expect(loaded.unreadable == 1)
    #expect(FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("broken.json").path))
}

@Test func absurdTimesFromADamagedFileNeverCrash() {
    #expect(TimeFormat.clock(1e100).contains(":"))
    #expect(TimeFormat.srt(1e100).contains(":"))
    #expect(TimeFormat.vtt(-1e100) == "00:00:00.000")
    let huge = Transcript(title: "x", sourceFileName: "x", duration: 1e100, localeIdentifier: "en", segments: [TranscriptSegment(id: 0, start: 1e100, end: 1e100, text: "hi")])
    #expect(TranscriptExport.srt.render(huge).contains("hi"))
}

@Test func aFileClaimingAnotherIdIsSetAsideSoDeleteCantRemoveTheWrongFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(folder: folder)
    let kept = Transcript(title: "Kept", sourceFileName: "a.m4a", duration: 1, localeIdentifier: "en-US",
                          segments: [TranscriptSegment(id: 0, start: 0, end: 1, text: "Hello.")])
    try store.save(kept)
    let original = folder.appendingPathComponent(kept.id.uuidString + ".json")
    try FileManager.default.copyItem(at: original, to: folder.appendingPathComponent(UUID().uuidString + ".json"))
    let loaded = try store.load()
    #expect(loaded.transcripts.map(\.id) == [kept.id])
    #expect(loaded.unreadable == 1)
}

@Test func anOversizedFileIsSetAsideUnread() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = LibraryStore(folder: folder, maximumFileBytes: 10)
    let big = Transcript(title: "Big", sourceFileName: "a.m4a", duration: 1, localeIdentifier: "en-US",
                         segments: [TranscriptSegment(id: 0, start: 0, end: 1, text: "Hello there.")])
    try store.save(big)
    let loaded = try store.load()
    #expect(loaded.transcripts.isEmpty)
    #expect(loaded.unreadable == 1)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(big.id.uuidString + ".json").path))
}

@Test func markdownCannotFormLinksOrImages() {
    let t = Transcript(title: "![x](https://example.com/a.png)", sourceFileName: "a.m4a", duration: 1, localeIdentifier: "en-US",
                       segments: [TranscriptSegment(id: 0, start: 0, end: 1, text: "see [here](https://example.com) # *now*")])
    let md = TranscriptExport.markdown.render(t)
    #expect(!md.contains("![x]("))
    #expect(!md.contains("[here]("))
    #expect(md.contains("\\[here\\]"))
    #expect(md.contains("\\*now\\*"))
}

@Test func subtitleMarkupShowsAsTyped() {
    let t = Transcript(title: "T", sourceFileName: "a.m4a", duration: 1, localeIdentifier: "en-US",
                       segments: [TranscriptSegment(id: 0, start: 0, end: 1, text: "a <b>bold</b> & ---> move")])
    let vtt = TranscriptExport.vtt.render(t)
    #expect(vtt.contains("&lt;b&gt;bold&lt;/b&gt; &amp;"))
    let srt = TranscriptExport.srt.render(t)
    #expect(srt.contains("\u{2039}b\u{203A}bold"))
    // Only the real timing line has an arrow.
    #expect(srt.components(separatedBy: "-->").count == 2)
}

@Test func anEmptyCueStaysAValidCue() {
    let t = Transcript(title: "T", sourceFileName: "a.m4a", duration: 1, localeIdentifier: "en-US",
                       segments: [TranscriptSegment(id: 0, start: 0, end: 1, text: "\n\n")])
    #expect(TranscriptExport.srt.render(t).contains("\n...\n"))
}
