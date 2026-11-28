import AVFoundation
import SwiftUI
import XCTest
@testable import Spindle

/// Unit tests. Each name starts with the TEST-CASES.md id(s) it proves, e.g. test_TC_LIB_01_….
final class CoreTests: XCTestCase {

    // MARK: Fixtures

    static let root = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response><D:href>/music/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/music/Miles%20Davis/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/music/%E5%91%A8%E6%9D%B0%E5%80%AB/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/music/@eaDir/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/music/loose%20track.mp3</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>4200000</D:getcontentlength><D:getlastmodified>Tue, 03 Feb 2026 10:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response>
      <D:response><D:href>/music/cover.jpg</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>12000</D:getcontentlength></D:prop></D:propstat></D:response>
    </D:multistatus>
    """

    static let album = """
    <?xml version="1.0"?>
    <d:multistatus xmlns:d="DAV:" xmlns:lp1="DAV:">
      <d:response><d:href>http://nas.local:5005/music/Miles%20Davis/Kind%20of%20Blue/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
      <d:response><d:href>http://nas.local:5005/music/Miles%20Davis/Kind%20of%20Blue/01%20So%20What.flac</d:href><d:propstat><d:prop><d:resourcetype/><lp1:getcontentlength>31415926</lp1:getcontentlength><lp1:getlastmodified>Mon, 02 Mar 2026 08:30:00 GMT</lp1:getlastmodified></d:prop></d:propstat></d:response>
      <d:response><d:href>/music/Miles%20Davis/Kind%20of%20Blue/02%20-%20Freddie%20Freeloader%20%23live.mp3</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>9000000</d:getcontentlength></d:prop></d:propstat></d:response>
      <d:response><d:href>/music/Miles%20Davis/Kind%20of%20Blue/notes.txt</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
    </d:multistatus>
    """

    let base = URL(string: "http://nas.local:5005/music/")!

    func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func track(_ path: String, source: UUID = UUID(), number: Int? = nil, title: String? = nil, artist: String = "A", album: String = "B",
               added: Date = Date(), duration: Double? = 10) -> Track {
        Track(id: Track.makeID(source: source, path: path), sourceID: source, path: path, title: title ?? path, artist: artist, album: album,
              albumArtist: nil, trackNumber: number, duration: duration, size: 1, modified: nil, addedAt: added, enriched: true)
    }

    // MARK: Sources

    func test_TC_SRC_01_parsesRootListing() {
        let e = PropfindParser.parse(Data(Self.root.utf8), base: base, request: base)
        let paths = e.map(\.relativePath)
        XCTAssertEqual(Set(paths), ["Miles Davis", "周杰倫", "loose track.mp3", "cover.jpg"])
        XCTAssertFalse(paths.contains(""), "the listed folder itself is excluded")
        XCTAssertFalse(paths.contains("@eaDir"), "Synology metadata folders are skipped")
        XCTAssertTrue(e.first { $0.relativePath == "Miles Davis" }!.isCollection)
        let music = e.filter { !$0.isCollection && AudioFormats.isAudio($0.relativePath) }
        XCTAssertEqual(music.map(\.relativePath), ["loose track.mp3"])
    }

    func test_TC_SRC_02_parsesSizesDatesAbsoluteHrefs() {
        let folder = URL(string: "http://nas.local:5005/music/Miles%20Davis/Kind%20of%20Blue/")!
        let e = PropfindParser.parse(Data(Self.album.utf8), base: base, request: folder)
        XCTAssertEqual(e.count, 3)
        let so = e.first { $0.relativePath.hasSuffix("So What.flac") }!
        XCTAssertEqual(so.relativePath, "Miles Davis/Kind of Blue/01 So What.flac")
        XCTAssertEqual(so.size, 31_415_926)
        XCTAssertNotNil(so.modified)
        XCTAssertTrue(e.contains { $0.relativePath == "Miles Davis/Kind of Blue/02 - Freddie Freeloader #live.mp3" })
    }

    func test_TC_SRC_03_normalizesAddresses() {
        XCTAssertEqual(WebDAVAddress.normalize("nas.local:5006/music")?.absoluteString, "http://nas.local:5006/music/")
        XCTAssertEqual(WebDAVAddress.normalize("https://nas.example.com:5006")?.absoluteString, "https://nas.example.com:5006/")
        XCTAssertEqual(WebDAVAddress.normalize("  192.168.1.20 :5005/music ")?.absoluteString, "http://192.168.1.20:5005/music/")
        XCTAssertNil(WebDAVAddress.normalize(""))
        XCTAssertNil(WebDAVAddress.normalize("ftp://nas/music"))
        XCTAssertNotNil(SourceError.badAddress.errorDescription)
    }

    func test_TC_SRC_05_TC_ERR_01_mapsErrors() {
        XCTAssertEqual(SourceError.from(status: 401), .unauthorized)
        XCTAssertEqual(SourceError.from(status: 403), .forbidden)
        XCTAssertEqual(SourceError.from(status: 404), .notFound)
        XCTAssertEqual(SourceError.from(status: 405), .notWebDAV)
        XCTAssertNil(SourceError.from(status: 207))
        XCTAssertEqual(SourceError.from(URLError(.timedOut)), .timeout)
        XCTAssertEqual(SourceError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(SourceError.from(URLError(.serverCertificateUntrusted)), .untrustedCertificate)
        let all: [SourceError] = [.badAddress, .unauthorized, .forbidden, .notFound, .notWebDAV, .timeout, .untrustedCertificate,
                                  .offline, .localNetworkDenied, .folderUnavailable, .server(500)]
        let texts = all.compactMap(\.errorDescription)
        XCTAssertEqual(texts.count, all.count)
        XCTAssertEqual(Set(texts).count, all.count, "every error has its own message")
        XCTAssertTrue(SourceError.unauthorized.errorDescription!.contains("password"))
    }

    func test_TC_SRC_07_scansFolderRecursively() throws {
        let dir = tempDir()
        let sub = dir.appendingPathComponent("Artist/Album", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["01 One.mp3", "02 Two.flac"] { try Data([0]).write(to: sub.appendingPathComponent(name)) }
        try Data([0]).write(to: dir.appendingPathComponent("loose.m4a"))
        try Data([0]).write(to: dir.appendingPathComponent("readme.txt"))
        let files = try FolderSource.scan(root: dir)
        XCTAssertEqual(Set(files.map(\.relativePath)), ["Artist/Album/01 One.mp3", "Artist/Album/02 Two.flac", "loose.m4a"])
    }

    func test_TC_SRC_08_TC_SRC_09_TC_IAP_05_TC_IAP_07_freeLimits() {
        let demo = SourceConfig(kind: .demo, name: "Demo")
        let nas = SourceConfig(kind: .webdav, name: "NAS")
        let free = ProLimits(isPro: false), pro = ProLimits(isPro: true)
        XCTAssertTrue(free.canAddSource(existing: [demo]), "the demo shelf doesn't count")
        XCTAssertFalse(free.canAddSource(existing: [demo, nas]))
        XCTAssertTrue(free.canAddSource(existing: [demo]), "removing the only source gives the slot back")
        XCTAssertTrue(pro.canAddSource(existing: [demo, nas, nas]))
        XCTAssertTrue(free.canAddPlaylist(existing: 1))
        XCTAssertFalse(free.canAddPlaylist(existing: 2))
        XCTAssertTrue(pro.canAddPlaylist(existing: 50))
        XCTAssertTrue(free.canDownload(downloaded: 19, queued: 0))
        XCTAssertFalse(free.canDownload(downloaded: 20, queued: 0))
        XCTAssertFalse(free.canDownload(downloaded: 10, queued: 5, adding: 6))
        XCTAssertTrue(pro.canDownload(downloaded: 500, queued: 10, adding: 100))
        XCTAssertFalse(free.hasSleepTimer)
        XCTAssertTrue(pro.hasSleepTimer)
        // After a refund the flag is false again: existing sources stay, new ones need Pro.
        XCTAssertFalse(ProLimits(isPro: false).canAddSource(existing: [nas, SourceConfig(kind: .folder, name: "F")]))
    }

    @MainActor
    func test_TC_SRC_10_passwordOnlyInKeychain() throws {
        let dir = tempDir()
        let store = LibraryStore(directory: dir, autosave: false)
        let s = SourceConfig(kind: .webdav, name: "NAS", address: "http://nas.local:5005/music/", username: "listener")
        let secret = "s3cret-\(UUID().uuidString)"
        Keychain.setPassword(secret, for: s.id)
        store.addSource(s)
        store.saveNow()
        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(json.contains(secret))
        let defaults = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }.joined()
        XCTAssertFalse(defaults.contains(secret))
        XCTAssertEqual(Keychain.password(for: s.id), secret)
        Keychain.remove(for: s.id)
        XCTAssertNil(Keychain.password(for: s.id))
    }

    @MainActor
    func test_TC_SRC_11_TC_LIFE_01_sourcesDoNotMix() {
        let store = LibraryStore(directory: tempDir(), autosave: false)
        let a = SourceConfig(kind: .webdav, name: "A"), b = SourceConfig(kind: .folder, name: "B")
        store.addSource(a); store.addSource(b)
        store.merge(source: a.id, files: [.init(path: "X/Y/01 One.mp3"), .init(path: "X/Y/02 Two.mp3")])
        store.merge(source: b.id, files: [.init(path: "Z/W/01 Three.mp3")])
        XCTAssertEqual(store.count(of: a.id), 2)
        XCTAssertEqual(store.count(of: b.id), 1)
        store.removeSource(a.id)
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertTrue(store.tracks.values.allSatisfy { $0.sourceID == b.id })
    }

    // MARK: Library

    func test_TC_LIB_01_infersFromPath() {
        let g = PathInference.guess(path: "Miles Davis/Kind of Blue/01 So What.flac")
        XCTAssertEqual(g, .init(artist: "Miles Davis", album: "Kind of Blue", trackNumber: 1, title: "So What"))
        let deep = PathInference.guess(path: "Music/Jazz/Miles Davis/Kind of Blue/CD1/1-04 All Blues.m4a")
        XCTAssertEqual(deep, .init(artist: "Miles Davis", album: "Kind of Blue", trackNumber: 4, title: "All Blues"))
    }

    func test_TC_LIB_02_infersWithMissingLevels() {
        XCTAssertEqual(PathInference.guess(path: "Kind of Blue/02 - Freddie Freeloader.mp3"),
                       .init(artist: Unknown.artist, album: "Kind of Blue", trackNumber: 2, title: "Freddie Freeloader"))
        XCTAssertEqual(PathInference.guess(path: "03. Blue in Green.m4a"),
                       .init(artist: Unknown.artist, album: Unknown.album, trackNumber: 3, title: "Blue in Green"))
        XCTAssertEqual(PathInference.guess(path: "song.mp3"), .init(artist: Unknown.artist, album: Unknown.album, trackNumber: nil, title: "song"))
        XCTAssertEqual(PathInference.guess(path: "Prince/1999.mp3").title, "1999", "a year is not a track number")
        XCTAssertEqual(PathInference.guess(path: "Portishead - Dummy/04 Glory_Box.flac").artist, "Portishead")
    }

    func test_TC_LIB_03_mergesSameAlbumAcrossFolders() {
        let s = UUID()
        let t = [track("a/x.mp3", source: s, number: 2, artist: "Ella", album: "Songbook"),
                 track("b/y.mp3", source: s, number: 1, artist: "ella", album: "SONGBOOK"),
                 track("c/z.mp3", source: s, number: 1, artist: "Other", album: "Songbook")]
        let idx = LibraryIndex(tracks: t)
        XCTAssertEqual(idx.albums.count, 2)
        XCTAssertEqual(idx.albums.first { $0.artist.lowercased() == "ella" }?.tracks.count, 2)
    }

    func test_TC_LIB_04_ordersAlbumsAndTracks() {
        let s = UUID()
        let idx = LibraryIndex(tracks: [track("z/2.mp3", source: s, number: 2, album: "Zebra"),
                                        track("z/1.mp3", source: s, number: 1, album: "Zebra"),
                                        track("a/10.mp3", source: s, number: 10, album: "Apple"),
                                        track("a/9.mp3", source: s, number: 9, album: "Apple")])
        XCTAssertEqual(idx.albums.map(\.title), ["Apple", "Zebra"])
        XCTAssertEqual(idx.albums[0].tracks.map(\.trackNumber), [9, 10])
    }

    func test_TC_LIB_05_searchesAllFields() {
        let s = UUID()
        let idx = LibraryIndex(tracks: [track("1.mp3", source: s, title: "Low Tide", artist: "Ensemble", album: "Harbor"),
                                        track("2.mp3", source: s, title: "Other", artist: "Béla Fleck", album: "Tales"),
                                        track("3.mp3", source: s, title: "Third", artist: "X", album: "Tidewater")])
        let r = idx.search("tide")
        XCTAssertEqual(Set(r.tracks.map(\.title)), ["Low Tide", "Third"])
        XCTAssertEqual(idx.search("bela").tracks.map(\.title), ["Other"], "diacritics ignored")
        XCTAssertEqual(idx.search("ENSEMBLE").artists.map(\.name), ["Ensemble"])
        XCTAssertTrue(idx.search("   ").isEmpty)
    }

    func test_TC_LIB_07_recentlyAdded() {
        let s = UUID()
        var list: [Track] = []
        for i in 0..<15 { list.append(track("\(i).mp3", source: s, album: "Album \(i)", added: Date(timeIntervalSince1970: Double(i) * 100))) }
        let r = LibraryIndex(tracks: list).recentlyAdded()
        XCTAssertEqual(r.count, 12)
        XCTAssertEqual(r.first?.title, "Album 14")
    }

    @MainActor
    func test_TC_LIB_08_savesAndLoadsAtomically() throws {
        let dir = tempDir()
        let a = LibraryStore(directory: dir, autosave: false)
        let s = SourceConfig(kind: .webdav, name: "NAS")
        a.addSource(s)
        a.merge(source: s.id, files: [.init(path: "A/B/01 One.mp3", size: 5)])
        let p = a.createPlaylist(named: "Road")
        a.add(Array(a.tracks.keys), to: p.id)
        a.saveNow()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: a.fileURL)) as? [String: Any]
        XCTAssertEqual(raw?["schemaVersion"] as? Int, LibrarySnapshot.currentSchema)
        let b = LibraryStore(directory: dir, autosave: false)
        b.load()
        XCTAssertEqual(b.sources, a.sources)
        XCTAssertEqual(b.tracks, a.tracks)
        XCTAssertEqual(b.playlists.first?.trackIDs.count, 1)
    }

    @MainActor
    func test_TC_LIB_09_recoversFromDamagedFile() throws {
        let dir = tempDir()
        let a = LibraryStore(directory: dir, autosave: false)
        a.addSource(SourceConfig(kind: .webdav, name: "Good"))
        a.saveNow()
        let b = LibraryStore(directory: dir, autosave: false)   // second launch: backs up the good file on save
        b.load()
        b.addSource(SourceConfig(kind: .folder, name: "Second"))
        b.saveNow()
        try Data("{ not json".utf8).write(to: b.fileURL)
        let c = LibraryStore(directory: dir, autosave: false)
        c.load()
        XCTAssertEqual(c.sources.map(\.name), ["Good"], "restored from the backup")
        XCTAssertNotNil(c.loadMessage)

        let empty = tempDir()
        try Data("garbage".utf8).write(to: empty.appendingPathComponent("library.json"))
        let d = LibraryStore(directory: empty, autosave: false)
        d.load()
        XCTAssertTrue(d.sources.isEmpty)
        XCTAssertNotNil(d.loadMessage)
    }

    func test_TC_LIB_10_artworkStoredOncePerAlbum() throws {
        let dir = tempDir()
        let key = Album.key(title: "Kind of Blue", artist: "Miles Davis")
        XCTAssertTrue(ArtworkStore.save(Data([1, 2, 3]), albumKey: key, in: dir))
        XCTAssertFalse(ArtworkStore.save(Data([9, 9]), albumKey: key, in: dir))
        XCTAssertTrue(ArtworkStore.has(key, in: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
        XCTAssertEqual(try Data(contentsOf: ArtworkStore.url(for: key, in: dir)), Data([1, 2, 3]))
        XCTAssertFalse(AppPaths.artwork.path.contains("/Caches/"), "artwork must not live in Caches")
    }

    func test_TC_LIB_11_playableFormats() {
        for ok in ["a.mp3", "a.M4A", "a.flac", "a.wav", "a.aiff", "a.caf", "a.alac"] { XCTAssertTrue(AudioFormats.isPlayable(ok), ok) }
        for bad in ["a.wma", "a.ape", "a.ogg", "a.dsf"] {
            XCTAssertTrue(AudioFormats.isAudio(bad), bad)
            XCTAssertFalse(AudioFormats.isPlayable(bad), bad)
        }
        XCTAssertFalse(AudioFormats.isAudio("cover.jpg"))
    }

    @MainActor
    func test_TC_LIB_12_tagsOverrideGuesses() {
        let store = LibraryStore(directory: tempDir(), autosave: false)
        let s = SourceConfig(kind: .webdav, name: "NAS")
        store.addSource(s)
        store.merge(source: s.id, files: [.init(path: "Unknown/Folder/03 track.mp3")])
        let id = store.tracks.keys.first!
        store.applyTags(.init(title: "Blue in Green", artist: "Miles Davis", album: "Kind of Blue", albumArtist: nil, trackNumber: 3,
                              duration: 337, artwork: nil), to: id)
        XCTAssertEqual(store.tracks[id]?.title, "Blue in Green")
        XCTAssertEqual(store.tracks[id]?.album, "Kind of Blue")
        XCTAssertEqual(store.tracks[id]?.duration, 337)
        XCTAssertTrue(store.tracks[id]!.enriched)
        store.merge(source: s.id, files: [.init(path: "Unknown/Folder/04 other.mp3")])
        let other = store.tracks.values.first { $0.path.hasSuffix("04 other.mp3") }!.id
        store.applyTags(.init(title: "  ", artist: nil, album: nil, albumArtist: nil, trackNumber: nil, duration: nil, artwork: nil), to: other)
        XCTAssertEqual(store.tracks[other]?.title, "other", "empty tags keep the path guess")
    }

    // MARK: Demo shelf and hero

    func test_TC_HOME_06_demoShelfGenerates() throws {
        let dir = tempDir()
        let paths = DemoLibrary.ensureFiles(in: dir)
        XCTAssertEqual(paths.count, 8)
        for p in paths {
            let f = try AVAudioFile(forReading: dir.appendingPathComponent(p))
            let seconds = Double(f.length) / f.fileFormat.sampleRate
            XCTAssertTrue((18...22).contains(seconds), "\(p): \(seconds)")
        }
        XCTAssertEqual(Set(paths.map { PathInference.guess(path: $0).album }), ["Harbor Lights", "Copper Sky"])
    }

    func test_TC_HOME_04_spindleThickness() {
        let h = SpindleStack.thicknesses(counts: [100, 300, 0], total: 100, minimum: 4)
        XCTAssertEqual(h[0], 25, accuracy: 0.01)
        XCTAssertEqual(h[1], 75, accuracy: 0.01)
        XCTAssertEqual(h[2], 4, "never thinner than the minimum")
    }

    // MARK: Playback rules

    func test_TC_PLY_01_queueNextPrevious() {
        let s = UUID()
        let list = (1...5).map { track("\($0).mp3", source: s, number: $0) }
        var q = PlayQueue(tracks: list, startAt: 2)
        XCTAssertEqual(q.current?.trackNumber, 3)
        XCTAssertEqual(q.upcoming.map(\.trackNumber), [4, 5])
        XCTAssertEqual(q.next()?.trackNumber, 4)
        XCTAssertEqual(q.previous(elapsed: 5), .restart, "more than 3 s in: restart")
        XCTAssertEqual(q.current?.trackNumber, 4)
        XCTAssertEqual(q.previous(elapsed: 1), .moved)
        XCTAssertEqual(q.current?.trackNumber, 3)
        q.playNext(track("x.mp3", source: s, number: 99))
        XCTAssertEqual(q.upcoming.first?.trackNumber, 99)
    }

    func test_TC_PLY_02_shuffleNoRepeats() {
        let s = UUID()
        let list = (1...20).map { track("\($0).mp3", source: s, number: $0) }
        var q = PlayQueue(tracks: list, startAt: 7)
        var rng = SeededRNG(seed: 42)
        q.setShuffle(true, using: &rng)
        XCTAssertEqual(q.current?.trackNumber, 8, "the current song stays first")
        var seen = [q.current!.trackNumber!]
        while let t = q.next(wrap: false) { seen.append(t.trackNumber!) }
        XCTAssertEqual(seen.count, 20)
        XCTAssertEqual(Set(seen).count, 20)
        q.setShuffle(false)
        XCTAssertFalse(q.shuffled)
    }

    func test_TC_PLY_14_repeatModes() {
        let s = UUID()
        let list = (1...3).map { track("\($0).mp3", source: s, number: $0) }
        var q = PlayQueue(tracks: list, startAt: 2)
        q.repeatMode = .off
        XCTAssertNil(q.advanceAfterFinish(), "stops at the end")
        q = PlayQueue(tracks: list, startAt: 2)
        q.repeatMode = .all
        XCTAssertEqual(q.advanceAfterFinish()?.trackNumber, 1)
        q.repeatMode = .one
        XCTAssertEqual(q.advanceAfterFinish()?.trackNumber, 1)
        XCTAssertEqual(q.advanceAfterFinish()?.trackNumber, 1)
    }

    func test_TC_PLY_04_TC_PLY_05_sessionPolicy() {
        XCTAssertTrue(AudioSessionPolicy.shouldResume(after: [.shouldResume], wasPlaying: true))
        XCTAssertFalse(AudioSessionPolicy.shouldResume(after: [], wasPlaying: true))
        XCTAssertFalse(AudioSessionPolicy.shouldResume(after: [.shouldResume], wasPlaying: false))
        XCTAssertTrue(AudioSessionPolicy.shouldPause(for: .oldDeviceUnavailable))
        XCTAssertFalse(AudioSessionPolicy.shouldPause(for: .newDeviceAvailable))
    }

    func test_TC_PLY_06_stallWatchdog() {
        var w = StallWatchdog()
        let t0 = Date()
        XCTAssertEqual(w.update(waiting: true, wantsToPlay: true, now: t0), .wait)
        XCTAssertEqual(w.update(waiting: true, wantsToPlay: true, now: t0.addingTimeInterval(5)), .wait)
        XCTAssertEqual(w.update(waiting: true, wantsToPlay: true, now: t0.addingTimeInterval(8.5)), .reconnect)
        XCTAssertEqual(w.update(waiting: false, wantsToPlay: true, now: t0.addingTimeInterval(9)), .wait, "recovered")
        XCTAssertEqual(w.update(waiting: true, wantsToPlay: false, now: t0.addingTimeInterval(30)), .wait, "paused on purpose")
        var t = t0
        var decisions: [StallWatchdog.Decision] = []
        for _ in 0..<5 {
            _ = w.update(waiting: true, wantsToPlay: true, now: t)
            t = t.addingTimeInterval(9)
            decisions.append(w.update(waiting: true, wantsToPlay: true, now: t))
            t = t.addingTimeInterval(1)
        }
        XCTAssertTrue(decisions.contains(.skip), "gives up after \(StallWatchdog.maxRetriesPerTrack) reconnects")
        w.trackChanged()
        XCTAssertEqual(w.retries, 0)
    }

    @MainActor
    func test_TC_PLY_07_skipsUnplayable() {
        let s = UUID()
        let engine = PlayerEngine()
        engine.resolveURL = { _ in nil }
        engine.play([track("a.wma", source: s), track("b.ape", source: s)])
        XCTAssertNotNil(engine.notice)
        XCTAssertEqual(engine.status, .idle, "stops instead of looping over songs it can't play")
    }

    func test_TC_PLY_09_sleepTimer() {
        let now = Date()
        XCTAssertFalse(SleepTimer.minutes(15, fireAt: now.addingTimeInterval(900)).isDue(now: now))
        XCTAssertTrue(SleepTimer.minutes(15, fireAt: now.addingTimeInterval(900)).isDue(now: now.addingTimeInterval(901)))
        XCTAssertFalse(SleepTimer.endOfTrack.isDue(now: now))
        XCTAssertFalse(SleepTimer.off.isDue(now: now))
        XCTAssertEqual(SleepTimer.choices, [15, 30, 45, 60])
    }

    // MARK: Offline and playlists

    @MainActor
    func test_TC_OFF_02_TC_OFF_06_offlineFilesWinAndClear() throws {
        let store = LibraryStore(directory: tempDir(), autosave: false)
        let s = SourceConfig(kind: .webdav, name: "NAS")
        store.addSource(s)
        store.merge(source: s.id, files: [.init(path: "A/B/01 One.mp3")])
        let id = store.tracks.keys.first!
        XCTAssertNil(store.offlineURL(for: id))
        let name = "test-\(UUID().uuidString).mp3"
        try Data(repeating: 7, count: 2048).write(to: AppPaths.offline.appendingPathComponent(name))
        store.setOffline(id, file: name)
        XCTAssertEqual(store.offlineURL(for: id)?.lastPathComponent, name)
        XCTAssertEqual(store.offlineBytes(of: s.id), 2048)
        XCTAssertEqual(store.clearOffline(of: s.id), 2048)
        XCTAssertNil(store.offlineURL(for: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AppPaths.offline.appendingPathComponent(name).path))
    }

    func test_TC_OFF_04_TC_OFF_05_offlineLimitCountsFinishedOnly() {
        let free = ProLimits(isPro: false)
        // 18 finished + 1 failed (not counted) + 1 queued -> one more still fits.
        XCTAssertTrue(free.canDownload(downloaded: 18, queued: 1, adding: 1))
        XCTAssertFalse(free.canDownload(downloaded: 20, queued: 0, adding: 1))
    }

    @MainActor
    func test_TC_PL_01_TC_PL_03_TC_PL_04_playlists() {
        let store = LibraryStore(directory: tempDir(), autosave: false)
        let s = SourceConfig(kind: .webdav, name: "NAS")
        store.addSource(s)
        store.merge(source: s.id, files: ["1", "2", "3"].map { .init(path: "A/B/0\($0) T\($0).mp3") })
        let ids = store.tracks.values.sorted { $0.path < $1.path }.map(\.id)
        let p = store.createPlaylist(named: "  Drive  ")
        XCTAssertEqual(p.name, "Drive")
        store.add(ids, to: p.id)
        XCTAssertEqual(store.tracks(in: store.playlists[0]).map(\.id), ids)
        store.removeFromPlaylist(p.id, at: [1])
        XCTAssertEqual(store.playlists[0].trackIDs, [ids[0], ids[2]])
        XCTAssertEqual(store.tracks.count, 3, "removing from a playlist keeps the song")
        store.movePlaylistTracks(p.id, from: [1], to: 0)
        XCTAssertEqual(store.playlists[0].trackIDs, [ids[2], ids[0]])
        store.removeSource(s.id)
        XCTAssertTrue(store.playlists[0].trackIDs.isEmpty, "songs of a removed source leave playlists")
        store.deletePlaylist(p.id)
        XCTAssertTrue(store.playlists.isEmpty)
    }

    // MARK: Pro, review, share

    func test_TC_IAP_01_paywallHeadlines() {
        let reasons: [ProReason] = [.sources, .playlists, .offline, .sleepTimer, .settings]
        let titles = reasons.map(\.headline)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(titles).count, reasons.count, "each entry point says why the sheet opened")
        XCTAssertEqual(ProStore.productID, "com.noobclaw.spindle.pro_unlock")
    }

    func gate(installedDaysAgo: Double, songs: Int = 0, scan: Int = 0, lastAskedDaysAgo: Double? = nil, now: Date) -> ReviewGate {
        ReviewGate(installedAt: now.addingTimeInterval(-installedDaysAgo * 86_400),
                   lastAskedAt: lastAskedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }, completedSongs: songs, largestScan: scan)
    }

    func test_TC_RVW_01_TC_RVW_02_TC_RVW_03_reviewTiming() {
        let now = Date()
        let ctx = ReviewGate.Context(now: now, recentError: false, paywallOpen: false, launchedAt: now.addingTimeInterval(-3600))
        XCTAssertTrue(gate(installedDaysAgo: 4, songs: 10, now: now).shouldAsk(ctx))
        XCTAssertTrue(gate(installedDaysAgo: 4, scan: 150, now: now).shouldAsk(ctx))
        XCTAssertFalse(gate(installedDaysAgo: 4, songs: 9, now: now).shouldAsk(ctx))
        XCTAssertFalse(gate(installedDaysAgo: 2, songs: 50, now: now).shouldAsk(ctx), "installed under 3 days")
        XCTAssertFalse(gate(installedDaysAgo: 40, songs: 50, lastAskedDaysAgo: 10, now: now).shouldAsk(ctx), "asked within 30 days")
        XCTAssertTrue(gate(installedDaysAgo: 40, songs: 50, lastAskedDaysAgo: 31, now: now).shouldAsk(ctx))
        var err = ctx; err.recentError = true
        XCTAssertFalse(gate(installedDaysAgo: 4, songs: 10, now: now).shouldAsk(err))
        var pay = ctx; pay.paywallOpen = true
        XCTAssertFalse(gate(installedDaysAgo: 4, songs: 10, now: now).shouldAsk(pay))
    }

    func test_TC_RVW_05_feedbackLinkHasNoServerDetails() {
        let url = ReviewGate.feedbackURL(appVersion: "1.2.3", osVersion: "26.1")
        XCTAssertEqual(url.host, "256btc.com")
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("v=1.2.3") && q.contains("ios=26.1") && q.contains("app=spindle"))
        XCTAssertFalse(q.contains("nas") || q.contains("@"))
    }

    @MainActor
    func test_TC_RVW_04_loveItRequestsSystemReview() {
        let model = AppModel(library: LibraryStore(directory: tempDir(), autosave: false))
        var calls = 0
        model.requestReviewAction = { calls += 1 }
        model.showReviewCard = true
        model.reviewLoved()
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.showReviewCard)
    }

    @MainActor
    func test_TC_SHR_01_TC_SHR_02_shareCards() {
        let stats = ShareCards.ShelfStats(sources: 3, albums: 120, songs: 2418)
        let text = ShareCards.shelfText(stats).joined(separator: " ")
        for secret in ["nas.local", "http", "/music", "192.168", "Living Room NAS"] { XCTAssertFalse(text.contains(secret), secret) }
        let s = UUID()
        let img = ShareCards.render(Text(verbatim: "x").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black))
        XCTAssertEqual(img.size.width * img.scale, 1080, accuracy: 1)
        XCTAssertEqual(img.size.height * img.scale, 1350, accuracy: 1)
        _ = s
    }

    func test_TC_LIFE_02_extremeNames() {
        let long = String(repeating: "Very long title ", count: 20)
        let g = PathInference.guess(path: "A/B/01 \(long).mp3")
        XCTAssertTrue(g.title.hasPrefix("Very long title"))
        let idx = LibraryIndex(tracks: [])
        XCTAssertTrue(idx.albums.isEmpty)
        XCTAssertTrue(idx.search("x").isEmpty)
        XCTAssertEqual(PathInference.guess(path: "").title, "")
    }
}

/// Deterministic RNG for shuffle tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
