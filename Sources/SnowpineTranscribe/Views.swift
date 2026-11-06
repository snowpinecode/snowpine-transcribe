import SnowpineTranscribeCore
import SwiftUI
import UniformTypeIdentifiers

/// Snowpine Code brand 2.0: neutral greys and Pine Blue, adapting to light and dark.
enum Brand {
    static let blue = Color(red: 0, green: 163 / 255, blue: 224 / 255)   // #00A3E0
    static let action = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0, green: 163 / 255, blue: 224 / 255, alpha: 1)
            : NSColor(red: 0, green: 119 / 255, blue: 166 / 255, alpha: 1)    // #0077A6
    })
    static func heading(_ size: CGFloat) -> Font { .custom(BrandFonts.headingName, size: size) }
    static func body(_ size: CGFloat) -> Font { .custom(BrandFonts.regularName, size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom(BrandFonts.bodyName, size: size) }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let problem = model.problem { ProblemBanner(text: problem) { model.problem = nil } }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Brand.action)
        .frame(minWidth: 760, minHeight: 500)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: { model.isDropTarget = $0 }
        .overlay {
            if model.isDropTarget {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue, lineWidth: 3).padding(6).allowsHitTesting(false)
            }
        }
        .task { await model.loadLanguages() }
    }

    @ViewBuilder private var detail: some View {
        if let job = model.job {
            WorkingView(job: job, waiting: model.waiting.count) { model.cancel() }
        } else if let transcript = model.selected {
            TranscriptView(model: model, player: model.player, transcript: transcript).id(transcript.id)
        } else {
            StartView(model: model)
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List(selection: Binding(get: { model.selected?.id }, set: { model.selection = $0 })) {
            if model.libraryFailed {
                Text("Your saved transcripts couldn't be read.").font(Brand.body(12)).foregroundStyle(.secondary)
                Button("Try Again") { model.reload() }
            }
            if model.unreadableCount > 0 {
                Text("\(model.unreadableCount) saved transcript\(model.unreadableCount == 1 ? "" : "s") couldn't be read.")
                    .font(Brand.body(12)).foregroundStyle(.secondary)
            }
            Section("Transcripts") {
                if model.library.isEmpty && !model.libraryFailed {
                    Text("None yet").font(Brand.body(13)).foregroundStyle(.secondary)
                }
                ForEach(model.library) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(Brand.medium(13)).lineLimit(1)
                        Text(TimeFormat.clock(item.duration) + " \u{00B7} " + item.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(Brand.body(11)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(item.id)
                    .contextMenu { Button("Delete\u{2026}") { model.delete(item) } }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { model.selection = nil } label: { Label("New Transcript", systemImage: "plus") }
                    .help("New transcript")
            }
        }
    }
}

struct ProblemBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(text).font(Brand.body(13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: dismiss).controlSize(.small)
        }
        .padding(12)
        .background(.quaternary)
    }
}

struct StartView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform").font(.system(size: 44, weight: .medium)).foregroundStyle(Brand.blue).accessibilityHidden(true)
            Text("Drop a recording here").font(Brand.heading(26))
            Text("Audio or video. It's transcribed on this Mac, and nothing leaves it.")
                .font(Brand.body(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { model.chooseFiles() } label: { Text("Choose a File\u{2026}").padding(.horizontal, 10) }
                .controlSize(.large).buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)
            if !model.languages.isEmpty {
                Picker("Language", selection: $model.language) {
                    ForEach(model.languages, id: \.identifier) { Text(SpeechEngine.name(of: $0)).tag($0) }
                }
                .frame(maxWidth: 280)
            }
        }
        .padding(32)
    }
}

struct WorkingView: View {
    let job: AppModel.Job
    let waiting: Int
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(job.fileName).font(Brand.heading(20)).lineLimit(1).truncationMode(.middle)
            ProgressView(value: job.fraction)
            HStack {
                Text("\(job.status) \u{00B7} \(Int(job.fraction * 100))%").font(Brand.body(13)).foregroundStyle(.secondary)
                if waiting > 0 { Text("\u{00B7} \(waiting) more waiting").font(Brand.body(13)).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", action: cancel)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(job.lines) { LineText(line: $0).id($0.id) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: job.lines.count) { proxy.scrollTo(job.lines.last?.id, anchor: .bottom) }
            }
        }
        .padding(24)
    }
}

private struct LineText: View {
    let line: TranscriptSegment
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(TimeFormat.clock(line.start)).font(Brand.medium(12).monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
            Text(line.text).font(Brand.body(14)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TranscriptView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: TranscriptPlayer
    let transcript: Transcript
    @StateObject private var search = SearchState()

    private var query: String { search.query }
    private var visible: [TranscriptSegment] { TranscriptSearch.matches(query, in: transcript.segments) }
    private var playingLine: Int? {
        guard player.transcriptID == transcript.id else { return nil }
        return transcript.segments.last { $0.start <= player.time + 0.05 }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visible.isEmpty {
                Text("No lines match \u{201C}\(query)\u{201D}.").font(Brand.body(14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visible) { line in
                            TranscriptRow(line: line, isPlaying: line.id == playingLine, query: query,
                                          play: { model.play(transcript, from: line.start) },
                                          copy: { model.copy(line.text) })
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                }
            }
        }
        .onDisappear { if player.transcriptID == transcript.id { player.stop() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcript.title).font(Brand.heading(20)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Text("\(TimeFormat.clock(transcript.duration)) \u{00B7} \(transcript.wordCount.formatted()) words \u{00B7} \(SpeechEngine.name(of: Locale(identifier: transcript.localeIdentifier)))")
                        .font(Brand.body(12)).foregroundStyle(.secondary)
                }
                Spacer()
                if player.transcriptID == transcript.id {
                    Button { player.togglePause() } label: {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                Button("Copy All") { model.copyAll(transcript) }
                Menu("Export") {
                    ForEach(TranscriptExport.allCases) { kind in
                        Button(kind.label) { model.export(transcript, as: kind) }
                    }
                }
                .fixedSize()
                Button { model.delete(transcript) } label: { Label("Delete", systemImage: "trash").labelStyle(.iconOnly) }
                    .help("Delete this transcript")
            }
            HStack(spacing: 8) {
                TextField("Search what was said", text: $search.query).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                if !query.isEmpty { Text("\(visible.count) of \(transcript.segments.count) lines").font(Brand.body(12)).foregroundStyle(.secondary) }
            }
        }
        .padding(16)
    }
}

struct TranscriptRow: View {
    let line: TranscriptSegment
    let isPlaying: Bool
    let query: String
    let play: () -> Void
    let copy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: play) {
                Text(TimeFormat.clock(line.start)).font(Brand.medium(12).monospacedDigit()).foregroundStyle(Brand.action)
                    .frame(width: 58, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help("Play from here")
            .accessibilityLabel("Play from \(TimeFormat.clock(line.start))")
            Text(highlighted).font(Brand.body(14)).lineSpacing(3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isPlaying ? Brand.blue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button("Play from Here", action: play)
            Button("Copy Line", action: copy)
        }
    }

    private var highlighted: AttributedString {
        var text = AttributedString(line.text)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return text }
        var from = text.startIndex
        while from < text.endIndex, let range = text[from...].range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].backgroundColor = Brand.blue.opacity(0.28)
            from = range.upperBound
        }
        return text
    }
}
