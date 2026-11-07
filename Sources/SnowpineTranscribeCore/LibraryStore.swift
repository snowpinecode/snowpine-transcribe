import Foundation

/// Saves finished transcripts as JSON files in one folder on this Mac.
public struct LibraryStore: Sendable {
    public struct Loaded: Sendable {
        public var transcripts: [Transcript]
        /// Files that were there but couldn't be read. They are kept, never overwritten or hidden.
        public var unreadable: Int
    }

    public let folder: URL
    /// A 4 hour transcript is about 1 MB. A far larger file is damaged, so it isn't read into memory.
    public static let defaultMaximumFileBytes = 64 * 1024 * 1024
    public let maximumFileBytes: Int

    public init(folder: URL, maximumFileBytes: Int = LibraryStore.defaultMaximumFileBytes) {
        self.folder = folder
        self.maximumFileBytes = maximumFileBytes
    }

    public func load() throws -> Loaded {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var transcripts: [Transcript] = []
        var unreadable = 0
        var seen = Set<UUID>()
        for file in files where file.pathExtension == "json" {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= maximumFileBytes,
                  let data = try? Data(contentsOf: file),
                  let transcript = try? decoder.decode(Transcript.self, from: data),
                  // The file name is the id. A file claiming another id (or a repeat) is set aside,
                  // so Delete always removes the file that was shown.
                  file.deletingPathExtension().lastPathComponent.uppercased() == transcript.id.uuidString,
                  seen.insert(transcript.id).inserted else {
                unreadable += 1
                continue
            }
            transcripts.append(transcript)
        }
        transcripts.sort { $0.createdAt > $1.createdAt }
        return Loaded(transcripts: transcripts, unreadable: unreadable)
    }

    public func save(_ transcript: Transcript) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(transcript).write(to: file(for: transcript.id, extension: "json"), options: .atomic)
    }

    public func delete(_ id: UUID) throws {
        for ext in ["json", "bookmark"] {
            let url = file(for: id, extension: ext)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    public func saveBookmark(_ data: Data, for id: UUID) throws {
        try data.write(to: file(for: id, extension: "bookmark"), options: .atomic)
    }

    public func bookmark(for id: UUID) -> Data? {
        try? Data(contentsOf: file(for: id, extension: "bookmark"))
    }

    private func file(for id: UUID, extension ext: String) -> URL {
        folder.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
    }
}
