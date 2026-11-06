import Foundation

/// Saves finished transcripts as JSON files in one folder on this Mac.
public struct LibraryStore: Sendable {
    public struct Loaded: Sendable {
        public var transcripts: [Transcript]
        /// Files that were there but couldn't be read. They are kept, never overwritten or hidden.
        public var unreadable: Int
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func load() throws -> Loaded {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var transcripts: [Transcript] = []
        var unreadable = 0
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let transcript = try? decoder.decode(Transcript.self, from: data) {
                transcripts.append(transcript)
            } else {
                unreadable += 1
            }
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
