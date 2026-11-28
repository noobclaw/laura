import Foundation

/// File extensions Spindle recognises as music, and which of them iOS can decode.
enum AudioFormats {
    static let playable: Set<String> = ["mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "alac", "mp4"]
    static let unplayable: Set<String> = ["wma", "ape", "ogg", "oga", "opus", "dsf", "dff", "wv", "mpc"]

    static func ext(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }
    static func isAudio(_ path: String) -> Bool {
        let e = ext(path)
        return playable.contains(e) || unplayable.contains(e)
    }
    static func isPlayable(_ path: String) -> Bool { playable.contains(ext(path)) }
}

enum SourceKind: String, Codable, CaseIterable {
    case demo, webdav, folder
}

struct SourceConfig: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: SourceKind
    var name: String
    /// WebDAV: base address, e.g. `http://nas.local:5005/music/`.
    var address: String?
    var username: String?
    /// Folder: security-scoped bookmark.
    var bookmark: Data?
    var addedAt: Date
    var lastScan: Date?

    init(id: UUID = UUID(), kind: SourceKind, name: String, address: String? = nil, username: String? = nil,
         bookmark: Data? = nil, addedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.name = name; self.address = address
        self.username = username; self.bookmark = bookmark; self.addedAt = addedAt
    }

    /// The demo shelf never counts against the free source limit.
    var countsTowardLimit: Bool { kind != .demo }
}

struct Track: Codable, Identifiable, Hashable {
    var id: String
    var sourceID: UUID
    /// Path relative to the source root, decoded (no percent escapes), "/"-separated.
    var path: String
    var title: String
    var artist: String
    var album: String
    var albumArtist: String?
    var trackNumber: Int?
    var duration: Double?
    var size: Int64?
    var modified: Date?
    var addedAt: Date
    var enriched: Bool

    static func makeID(source: UUID, path: String) -> String { source.uuidString + "|" + path }

    var isPlayable: Bool { AudioFormats.isPlayable(path) }
    var albumKey: String { Album.key(title: album, artist: albumArtist ?? artist) }
}

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let tracks: [Track]
    let addedAt: Date

    static func key(title: String, artist: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) + "\u{1F}" +
        artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

struct Artist: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let albums: [Album]
}

struct Playlist: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.trackIDs = trackIDs; self.createdAt = createdAt
    }
}

/// What is written to disk. `schemaVersion` lets a future build migrate (and back up) older files.
struct LibrarySnapshot: Codable {
    static let currentSchema = 1
    var schemaVersion: Int = LibrarySnapshot.currentSchema
    var sources: [SourceConfig] = []
    var tracks: [Track] = []
    var playlists: [Playlist] = []
    var offline: [String: String] = [:]   // track id -> file name in Offline/
}

/// Placeholders shown when tags and folders give no name.
enum Unknown {
    static let artist = "Unknown Artist"
    static let album = "Unknown Album"
}
