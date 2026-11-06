import AppKit
import AVFoundation
import Foundation
import SnowpineTranscribeCore
import UniformTypeIdentifiers

/// Everything the window shows. One recording is transcribed at a time; others wait in line.
@MainActor
final class AppModel: ObservableObject {
    struct Job {
        var fileName: String
        var fraction: Double = 0
        var status = "Starting"
        var lines: [TranscriptSegment] = []
    }

    @Published var library: [Transcript] = []
    @Published var selection: UUID?
    @Published var job: Job?
    @Published var waiting: [URL] = []
    @Published var languages: [Locale] = []
    @Published var language: Locale = Locale(identifier: "en-US")
    @Published var problem: String?
    @Published var unreadableCount = 0
    @Published var libraryFailed = false
    @Published var isDropTarget = false
    /// Finished transcripts that couldn't be written to disk. They stay here so nothing is lost.
    @Published var unsaved: Set<UUID> = []

    let store: LibraryStore
    let player = TranscriptPlayer()
    private var task: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    var isWorking: Bool { job != nil }
    var selected: Transcript? { library.first { $0.id == selection } }

    init(store: LibraryStore? = nil) {
        self.store = store ?? AppModel.defaultStore()
        reload()
    }

    nonisolated static func defaultStore() -> LibraryStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LibraryStore(folder: base.appendingPathComponent("Transcripts"))
    }

    func reload() {
        do {
            let loaded = try store.load()
            library = loaded.transcripts
            unreadableCount = loaded.unreadable
            libraryFailed = false
        } catch {
            libraryFailed = true
        }
    }

    func loadLanguages() async {
        language = await SpeechEngine.defaultLanguage()
        languages = await SpeechEngine.languages()
    }

    // MARK: Transcribing

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.message = "Choose a recording. It stays on this Mac."
        panel.prompt = "Transcribe"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        problem = nil
        waiting.append(contentsOf: files)
        startNext()
    }

    private func startNext() {
        guard job == nil, !waiting.isEmpty else { return }
        let url = waiting.removeFirst()
        job = Job(fileName: url.lastPathComponent)
        selection = nil
        player.stop()
        let chosen = language
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Transcribing a recording")
        task = Task { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await SpeechEngine.transcribe(url: url, locale: chosen) { update in
                    Task { @MainActor [weak self] in self?.apply(update) }
                }
                try Task.checkCancellation()
                self?.finish(url: url, result: result)
            } catch is CancellationError {
                self?.endJob()
            } catch {
                self?.fail(url: url, error: error)
            }
        }
    }

    private func apply(_ update: SpeechEngine.Update) {
        guard job != nil else { return }
        job?.fraction = max(job?.fraction ?? 0, update.fraction)
        job?.status = update.status
        job?.lines.append(contentsOf: update.newSegments)
    }

    private func finish(url: URL, result: (segments: [TranscriptSegment], duration: Double, locale: Locale)) {
        guard !result.segments.isEmpty else {
            problem = "No speech was found in \(url.lastPathComponent). Nothing was saved."
            endJob()
            return
        }
        let transcript = Transcript(title: url.deletingPathExtension().lastPathComponent, sourceFileName: url.lastPathComponent,
                                    duration: result.duration, localeIdentifier: result.locale.identifier, segments: result.segments)
        library.insert(transcript, at: 0)
        selection = transcript.id
        do {
            try store.save(transcript)
        } catch {
            unsaved.insert(transcript.id)
            problem = "\u{201C}\(transcript.title)\u{201D} finished but couldn't be saved. It's still open here, so export it or try saving again before you quit."
        }
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) {
            try? store.saveBookmark(bookmark, for: transcript.id)
        }
        endJob()
    }

    func retrySave(_ transcript: Transcript) {
        do {
            try store.save(transcript)
            unsaved.remove(transcript.id)
            problem = nil
        } catch {
            problem = "\u{201C}\(transcript.title)\u{201D} still couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func fail(url: URL, error: Error) {
        problem = "\(url.lastPathComponent): \(error.localizedDescription)"
        endJob()
    }

    private func endJob() {
        job = nil
        task = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        startNext()
    }

    /// Stops the current recording and anything waiting.
    func cancel() {
        waiting.removeAll()
        task?.cancel()
    }

    // MARK: Saved transcripts

    func delete(_ transcript: Transcript) {
        let alert = NSAlert()
        alert.messageText = "Delete \u{201C}\(transcript.title)\u{201D}?"
        alert.informativeText = "This deletes the transcript from this app. Your recording isn't touched."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.delete(transcript.id)
            library.removeAll { $0.id == transcript.id }
            unsaved.remove(transcript.id)
            if selection == transcript.id {
                player.stop()
                selection = nil
            }
        } catch {
            problem = "That transcript couldn't be deleted: \(error.localizedDescription)"
        }
    }

    func copyAll(_ transcript: Transcript) {
        copy(TranscriptExport.text.render(transcript))
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func export(_ transcript: Transcript, as kind: TranscriptExport) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(transcript.title).\(kind.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: kind.fileExtension) ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try kind.render(transcript).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            problem = "That file couldn't be saved: \(error.localizedDescription)"
        }
    }

    func play(_ transcript: Transcript, from seconds: Double) {
        let title = transcript.title
        player.onFailure = { [weak self] in
            self?.problem = "The recording for \u{201C}\(title)\u{201D} couldn't be played. It may have been changed or damaged."
        }
        guard let data = store.bookmark(for: transcript.id), let refreshed = player.play(id: transcript.id, bookmark: data, from: seconds) else {
            problem = "The recording for \u{201C}\(title)\u{201D} couldn't be found. It may have been moved or deleted."
            return
        }
        if let refreshed { try? store.saveBookmark(refreshed, for: transcript.id) }
    }

    /// True when it's fine to quit, asking first if that would lose work.
    func confirmQuit() -> Bool {
        guard isWorking || !unsaved.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = isWorking ? "Stop transcribing and quit?" : "Quit without saving?"
        alert.informativeText = isWorking
            ? "This recording isn't finished, so its transcript won't be saved."
            : "A finished transcript couldn't be saved and will be lost. Export it first if you need it."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Working")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// The search box's text. A small model rather than @State, so the app also builds with only the Command Line Tools.
@MainActor
final class SearchState: ObservableObject {
    @Published var query = ""
}

/// Plays a recording from a line, so a name or number can be checked by ear.
@MainActor
final class TranscriptPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    @Published private(set) var transcriptID: UUID?

    /// Called when the recording turns out not to be playable.
    var onFailure: (() -> Void)?

    private var player: AVPlayer?
    private var observer: Any?
    private var statusWatch: NSKeyValueObservation?
    private var scopedURL: URL?

    /// Starts playing. Returns nil if the recording can't be reached, otherwise a refreshed bookmark if the old one went stale.
    func play(id: UUID, bookmark: Data, from seconds: Double) -> Data?? {
        var refreshed: Data?
        if transcriptID != id || player == nil {
            stop()
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  url.isFileURL, url.startAccessingSecurityScopedResource() else { return nil }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                url.stopAccessingSecurityScopedResource()
                return nil
            }
            if stale { refreshed = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]) }
            scopedURL = url
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            transcriptID = id
            statusWatch = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    self?.stop()
                    self?.onFailure?()
                }
            }
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    self?.time = time.seconds
                    self?.isPlaying = (self?.player?.rate ?? 0) > 0
                }
            }
        }
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
        isPlaying = true
        time = seconds
        return .some(refreshed)
    }

    func togglePause() {
        guard let player else { return }
        if player.rate > 0 { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        statusWatch = nil
        player = nil
        isPlaying = false
        transcriptID = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
