import Foundation
import Observation

enum ScanState: Equatable {
    case idle
    case scanning(found: Int)
    case enriching(done: Int, total: Int)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .scanning, .enriching: return true
        default: return false
        }
    }
}

/// Sources, tracks, playlists and offline files, saved atomically to `library.json`.
@MainActor
@Observable
final class LibraryStore {
    private(set) var sources: [SourceConfig] = []
    private(set) var tracks: [String: Track] = [:]
    private(set) var playlists: [Playlist] = []
    private(set) var offline: [String: String] = [:]
    private(set) var index = LibraryIndex(tracks: [])
    var scanStates: [UUID: ScanState] = [:]
    /// Set when the library file was damaged at launch.
    var loadMessage: String?

    @ObservationIgnored let directory: URL
    @ObservationIgnored private var backedUp = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let autosave: Bool

    var fileURL: URL { directory.appendingPathComponent("library.json") }
    var backupURL: URL { directory.appendingPathComponent("library.backup.json") }

    init(directory: URL = AppPaths.root, autosave: Bool = true) {
        self.directory = directory
        self.autosave = autosave
    }

    // MARK: Persistence

    func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: fileURL), let snap = try? decoder.decode(LibrarySnapshot.self, from: data) {
            apply(snap)
            return
        }
        let mainExists = FileManager.default.fileExists(atPath: fileURL.path)
        if let data = try? Data(contentsOf: backupURL), let snap = try? decoder.decode(LibrarySnapshot.self, from: data) {
            apply(snap)
            if mainExists { loadMessage = String(localized: "Your library file was damaged, so Spindle restored the last good copy.", bundle: .l10n) }
            backedUp = true   // don't overwrite the good backup with the damaged file
            saveNow()
            return
        }
        if mainExists {
            loadMessage = String(localized: "Your library file couldn’t be read, so Spindle started fresh. Your music on the server is untouched.", bundle: .l10n)
            backedUp = true
        }
        apply(LibrarySnapshot())
    }

    private func apply(_ s: LibrarySnapshot) {
        sources = s.sources
        tracks = Dictionary(s.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        playlists = s.playlists
        offline = s.offline
        rebuildIndex()
    }

    var snapshot: LibrarySnapshot {
        LibrarySnapshot(sources: sources, tracks: Array(tracks.values), playlists: playlists, offline: offline)
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the previous good file once per launch, so a bad write can be recovered.
        if !backedUp, fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: fileURL, to: backupURL)
            backedUp = true
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func scheduleSave() {
        guard autosave else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func rebuildIndex() { index = LibraryIndex(tracks: Array(tracks.values)) }

    // MARK: Sources

    func addSource(_ s: SourceConfig) {
        sources.append(s)
        scheduleSave()
    }

    func updateSource(_ s: SourceConfig) {
        guard let i = sources.firstIndex(where: { $0.id == s.id }) else { return }
        sources[i] = s
        scheduleSave()
    }

    /// Removes the source, its songs, their offline files and playlist entries.
    func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
        let gone = Set(tracks.values.filter { $0.sourceID == id }.map(\.id))
        for t in gone {
            tracks[t] = nil
            if let f = offline.removeValue(forKey: t) { try? FileManager.default.removeItem(at: AppPaths.offline.appendingPathComponent(f)) }
        }
        for i in playlists.indices { playlists[i].trackIDs.removeAll { gone.contains($0) } }
        scanStates[id] = nil
        rebuildIndex()
        scheduleSave()
    }

    func tracks(of source: UUID) -> [Track] { tracks.values.filter { $0.sourceID == source } }
    func count(of source: UUID) -> Int { tracks.values.reduce(0) { $0 + ($1.sourceID == source ? 1 : 0) } }

    struct ScannedFile { var path: String; var size: Int64?; var modified: Date? }

    /// Merges a fresh listing: keeps tags already read for unchanged files, adds new ones from
    /// the path guess, drops files that disappeared. Returns the number of songs now in the source.
    @discardableResult
    func merge(source: UUID, files: [ScannedFile], now: Date = Date(), preEnriched: Bool = false, duration: Double? = nil) -> Int {
        var seen = Set<String>()
        for f in files {
            let id = Track.makeID(source: source, path: f.path)
            seen.insert(id)
            if let old = tracks[id], old.size == f.size || f.size == nil { continue }
            let g = PathInference.guess(path: f.path)
            let added = tracks[id]?.addedAt ?? now
            tracks[id] = Track(id: id, sourceID: source, path: f.path, title: g.title, artist: g.artist, album: g.album,
                               albumArtist: nil, trackNumber: g.trackNumber, duration: duration, size: f.size,
                               modified: f.modified, addedAt: added, enriched: preEnriched)
        }
        let stale = tracks.values.filter { $0.sourceID == source && !seen.contains($0.id) }.map(\.id)
        for id in stale {
            tracks[id] = nil
            if let f = offline.removeValue(forKey: id) { try? FileManager.default.removeItem(at: AppPaths.offline.appendingPathComponent(f)) }
        }
        if !stale.isEmpty {
            let staleSet = Set(stale)
            for i in playlists.indices { playlists[i].trackIDs.removeAll { staleSet.contains($0) } }
        }
        if let i = sources.firstIndex(where: { $0.id == source }) { sources[i].lastScan = now }
        rebuildIndex()
        scheduleSave()
        return seen.count
    }

    /// Tags read from the file win over the path guess; empty tags are ignored.
    func applyTags(_ tags: MetadataReader.Tags?, to id: String, rebuild: Bool = true) {
        guard var t = tracks[id] else { return }
        if let tags {
            func clean(_ s: String?) -> String? {
                guard let v = s?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
                return v
            }
            if let v = clean(tags.title) { t.title = v }
            if let v = clean(tags.artist) { t.artist = v }
            if let v = clean(tags.album) { t.album = v }
            if let v = clean(tags.albumArtist) { t.albumArtist = v }
            if let n = tags.trackNumber, n > 0 { t.trackNumber = n }
            if let d = tags.duration, d.isFinite, d > 0 { t.duration = d }
        }
        t.enriched = true
        tracks[id] = t
        if rebuild { rebuildIndex() }
        scheduleSave()
    }

    func refreshIndex() { rebuildIndex() }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(named name: String) -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Playlist(name: trimmed.isEmpty ? String(localized: "New Playlist", bundle: .l10n) : trimmed)
        playlists.append(p)
        scheduleSave()
        return p
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { playlists[i].name = trimmed }
        scheduleSave()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        scheduleSave()
    }

    func add(_ trackIDs: [String], to playlist: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        playlists[i].trackIDs.append(contentsOf: trackIDs.filter { tracks[$0] != nil })
        scheduleSave()
    }

    func removeFromPlaylist(_ playlist: UUID, at offsets: IndexSet) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        for o in offsets.sorted(by: >) where playlists[i].trackIDs.indices.contains(o) { playlists[i].trackIDs.remove(at: o) }
        scheduleSave()
    }

    func movePlaylistTracks(_ playlist: UUID, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        var ids = playlists[i].trackIDs
        let moving = from.sorted().map { ids[$0] }
        for o in from.sorted(by: >) { ids.remove(at: o) }
        let dest = to - from.filter { $0 < to }.count
        ids.insert(contentsOf: moving, at: max(0, min(dest, ids.count)))
        playlists[i].trackIDs = ids
        scheduleSave()
    }

    func tracks(in playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap { tracks[$0] } }

    // MARK: Offline

    func setOffline(_ trackID: String, file: String?) {
        if let file { offline[trackID] = file } else if let old = offline.removeValue(forKey: trackID) {
            try? FileManager.default.removeItem(at: AppPaths.offline.appendingPathComponent(old))
        }
        scheduleSave()
    }

    func offlineURL(for trackID: String) -> URL? {
        guard let f = offline[trackID] else { return nil }
        let u = AppPaths.offline.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func offlineBytes(of source: UUID) -> Int64 {
        offline.reduce(Int64(0)) { sum, kv in
            guard tracks[kv.key]?.sourceID == source else { return sum }
            let values = try? AppPaths.offline.appendingPathComponent(kv.value).resourceValues(forKeys: [.fileSizeKey])
            return sum + Int64(values?.fileSize ?? 0)
        }
    }

    /// Clears offline files of one source; returns the bytes freed.
    @discardableResult
    func clearOffline(of source: UUID) -> Int64 {
        let bytes = offlineBytes(of: source)
        for (id, _) in offline where tracks[id]?.sourceID == source { setOffline(id, file: nil) }
        return bytes
    }
}
