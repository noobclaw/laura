import AVFoundation
import Foundation

/// Where Spindle keeps its own files. Everything lives in Application Support (not Caches),
/// so artwork and offline songs survive restarts, network changes and low-storage purges.
enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Spindle", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var library: URL { root.appendingPathComponent("library.json") }
    static var libraryBackup: URL { root.appendingPathComponent("library.backup.json") }
    static var artwork: URL { dir("Artwork") }
    static var offline: URL { dir("Offline") }
    static var demo: URL { dir("Demo") }
}

/// A folder the user picked in the Files sheet (local, iCloud, or an SMB server connected in Files).
enum FolderSource {
    struct File: Equatable { var relativePath: String; var size: Int64?; var modified: Date? }

    static func bookmark(for url: URL) throws -> Data {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Recursively lists music files under `root` (caller holds security-scoped access).
    static func scan(root: URL, progress: (Int) -> Void = { _ in }) throws -> [File] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw SourceError.folderUnavailable
        }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        var out: [File] = []
        for case let url as URL in e {
            guard AudioFormats.isAudio(url.lastPathComponent) else { continue }
            let v = try? url.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile ?? true else { continue }
            var path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if path.hasPrefix(rootPath) { path = String(path.dropFirst(rootPath.count)) }
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            out.append(File(relativePath: path, size: v?.fileSize.map { Int64($0) }, modified: v?.contentModificationDate))
            if out.count % 50 == 0 { progress(out.count) }
        }
        progress(out.count)
        return out
    }
}

/// Eight short pieces synthesised on first launch so the shelf is never empty and every
/// playback feature can be tried without a NAS (also what App Review listens to).
enum DemoLibrary {
    struct Piece { let album: String; let number: Int; let title: String; let root: Double; let tempo: Double; let pattern: [Int] }

    static let artist = "Spindle Demo Ensemble"
    static let pieces: [Piece] = [
        Piece(album: "Harbor Lights", number: 1, title: "Low Tide", root: 220.0, tempo: 84, pattern: [0, 4, 7, 11, 7, 4]),
        Piece(album: "Harbor Lights", number: 2, title: "Lantern Walk", root: 246.94, tempo: 96, pattern: [0, 3, 7, 10, 12, 7]),
        Piece(album: "Harbor Lights", number: 3, title: "Salt and Brass", root: 196.0, tempo: 108, pattern: [0, 7, 12, 7, 5, 4]),
        Piece(album: "Harbor Lights", number: 4, title: "Night Ferry", root: 174.61, tempo: 72, pattern: [0, 5, 9, 12, 9, 5]),
        Piece(album: "Copper Sky", number: 1, title: "Morning Signal", root: 261.63, tempo: 112, pattern: [0, 4, 7, 12, 16, 12]),
        Piece(album: "Copper Sky", number: 2, title: "Long Way Home", root: 233.08, tempo: 90, pattern: [0, 2, 4, 7, 9, 7]),
        Piece(album: "Copper Sky", number: 3, title: "Static Bloom", root: 207.65, tempo: 120, pattern: [0, 3, 5, 7, 10, 12]),
        Piece(album: "Copper Sky", number: 4, title: "Last Light", root: 185.0, tempo: 66, pattern: [0, 7, 4, 9, 5, 12]),
    ]
    static let seconds = 20.0
    static let sampleRate = 22_050.0

    static func relativePath(_ p: Piece) -> String {
        "\(artist)/\(p.album)/\(String(format: "%02d", p.number)) \(p.title).wav"
    }

    /// Writes any missing files; returns the relative paths.
    @discardableResult
    static func ensureFiles(in dir: URL = AppPaths.demo) -> [String] {
        pieces.map { p in
            let rel = relativePath(p)
            let url = dir.appendingPathComponent(rel)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? wav(samples: render(p)).write(to: url, options: .atomic)
            }
            return rel
        }
    }

    static func render(_ p: Piece) -> [Int16] {
        let n = Int(seconds * sampleRate)
        var out = [Int16](repeating: 0, count: n)
        let beat = 60.0 / p.tempo / 2   // eighth notes
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let step = Int(t / beat)
            let local = t - Double(step) * beat
            let semis = Double(p.pattern[step % p.pattern.count] + (step / (p.pattern.count * 4)) % 2 * 2)
            let f = p.root * pow(2, semis / 12)
            let env = min(1, local * 60) * exp(-local * 3.2)
            let pad = 0.18 * sin(2 * .pi * p.root / 2 * t) * (0.6 + 0.4 * sin(2 * .pi * 0.25 * t))
            let tone = sin(2 * .pi * f * t) + 0.35 * sin(4 * .pi * f * t) + 0.12 * sin(6 * .pi * f * t)
            var s = 0.42 * env * tone + pad
            let fade = min(1, t / 0.8, (seconds - t) / 1.5)
            s *= max(0, fade)
            out[i] = Int16(max(-1, min(1, s)) * 26_000)
        }
        return out
    }

    static func wav(samples: [Int16]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let rate = UInt32(sampleRate)
        let bytes = UInt32(samples.count * 2)
        d.append(Data("RIFF".utf8)); u32(36 + bytes); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(bytes)
        var bytes8 = [UInt8](repeating: 0, count: samples.count * 2)
        for (i, s) in samples.enumerated() {
            let u = UInt16(bitPattern: s)
            bytes8[i * 2] = UInt8(u & 0xFF)
            bytes8[i * 2 + 1] = UInt8(u >> 8)
        }
        d.append(contentsOf: bytes8)
        return d
    }
}

/// Reads tags and embedded artwork with AVFoundation (local files and authenticated HTTP alike).
enum MetadataReader {
    struct Tags { var title: String?; var artist: String?; var album: String?; var albumArtist: String?; var trackNumber: Int?; var duration: Double?; var artwork: Data? }

    static func read(_ url: URL) async -> Tags? {
        let asset = AVURLAsset(url: url)
        var tags = Tags()
        if let d = try? await asset.load(.duration), d.isNumeric { tags.duration = d.seconds }
        guard let items = try? await asset.load(.metadata) else { return tags }
        for item in items {
            let key = item.commonKey?.rawValue ?? (item.key as? String) ?? ""
            let id = item.identifier?.rawValue ?? ""
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue: tags.title = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtist.rawValue: tags.artist = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyAlbumName.rawValue: tags.album = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtwork.rawValue: tags.artwork = try? await item.load(.dataValue)
            default: break
            }
            if id.hasSuffix("TPE2") || id.hasSuffix("aART") || id.lowercased().contains("albumartist") {
                tags.albumArtist = try? await item.load(.stringValue)
            }
            if id.hasSuffix("TRCK") || id.hasSuffix("trkn") || id.lowercased().hasSuffix("tracknumber") {
                if let s = try? await item.load(.stringValue), let n = Int(s.split(separator: "/").first ?? "") { tags.trackNumber = n }
                else if let n = try? await item.load(.numberValue) { tags.trackNumber = n.intValue }
            }
        }
        return tags
    }
}

/// Album artwork on disk, one file per album, kept forever (until the album leaves the library).
enum ArtworkStore {
    static func fileName(for albumKey: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in albumKey.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16) + ".img"
    }
    static func url(for albumKey: String, in dir: URL = AppPaths.artwork) -> URL { dir.appendingPathComponent(fileName(for: albumKey)) }
    static func has(_ albumKey: String, in dir: URL = AppPaths.artwork) -> Bool { FileManager.default.fileExists(atPath: url(for: albumKey, in: dir).path) }

    /// Writes once per album; later calls for the same album are ignored.
    @discardableResult
    static func save(_ data: Data, albumKey: String, in dir: URL = AppPaths.artwork) -> Bool {
        let u = url(for: albumKey, in: dir)
        guard !FileManager.default.fileExists(atPath: u.path) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }
}
