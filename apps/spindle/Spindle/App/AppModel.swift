import Foundation
import Observation
import StoreKit
import SwiftUI
import UIKit

/// Ties library, sources, player, offline downloads, Pro and the review prompt together.
@MainActor
@Observable
final class AppModel {
    let library: LibraryStore
    let player = PlayerEngine()
    let pro = ProStore()
    let language = AppLanguage()

    /// Sheet routing.
    var paywall: ProReason?
    var showReviewCard = false
    var showNowPlaying = false
    var toast: String?

    /// Offline download queue (track ids), in order.
    private(set) var downloadQueue: [String] = []
    private(set) var downloading: String?
    private(set) var downloadFailures = 0

    @ObservationIgnored private var clients: [UUID: WebDAVClient] = [:]
    @ObservationIgnored private var folderRoots: [UUID: URL] = [:]
    @ObservationIgnored private var scanTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let review = ReviewTracker()
    @ObservationIgnored private let launchedAt = Date()
    @ObservationIgnored private var lastErrorAt: Date?
    @ObservationIgnored private let artworkCache = NSCache<NSString, UIImage>()
    /// Replaced in tests.
    @ObservationIgnored var requestReviewAction: @MainActor () -> Void = {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }

    static let isUITest = ProcessInfo.processInfo.arguments.contains("-UITour")

    init(library: LibraryStore = LibraryStore()) {
        self.library = library
        if ProcessInfo.processInfo.arguments.contains("-UITourReset") { AppModel.resetAllData() }
        library.load()
        if library.sources.isEmpty && !UserDefaults.standard.bool(forKey: "demo.removed") { addDemoSource() }
        // UI tests: a saved server that is never reached, so the free source slot is taken.
        if ProcessInfo.processInfo.arguments.contains("-UITourFakeSource"), !library.sources.contains(where: { $0.kind == .webdav }) {
            library.addSource(SourceConfig(kind: .webdav, name: "Test NAS", address: "http://127.0.0.1:9/music/", username: "test"))
        }
        for s in library.sources { openSource(s) }
        player.resolveURL = { [weak self] t in self?.playURL(for: t) }
        player.artwork = { [weak self] t in self?.artworkImage(albumKey: t.albumKey) }
        player.onSongCompleted = { [weak self] in
            self?.review.songCompleted()
            self?.maybeAskForReview()
        }
        // Warm up: check servers (this also registers WebDAV credentials for streaming) and finish tag reading.
        Task { await self.refreshOnLaunch() }
    }

    static func resetAllData() {
        try? FileManager.default.removeItem(at: AppPaths.root)
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
    }

    // MARK: Sources

    var userSources: [SourceConfig] { library.sources.filter(\.countsTowardLimit) }

    func canAddSource() -> Bool { pro.limits.canAddSource(existing: library.sources) }

    /// Opens the paywall instead when the free source is used.
    func requestAddSource() -> Bool {
        if canAddSource() { return true }
        paywall = .sources
        return false
    }

    private func addDemoSource() {
        let s = SourceConfig(kind: .demo, name: "Demo shelf")
        library.addSource(s)
    }

    func restoreDemo() {
        UserDefaults.standard.set(false, forKey: "demo.removed")
        guard !library.sources.contains(where: { $0.kind == .demo }) else { return }
        addDemoSource()
        if let s = library.sources.last { openSource(s); scan(s) }
    }

    func addWebDAV(name: String, address: URL, username: String, password: String) {
        let s = SourceConfig(kind: .webdav, name: name.isEmpty ? (address.host ?? "WebDAV") : name,
                             address: address.absoluteString, username: username)
        if !password.isEmpty { Keychain.setPassword(password, for: s.id) }
        library.addSource(s)
        openSource(s)
        scan(s)
    }

    func addFolder(_ url: URL) {
        do {
            let bookmark = try FolderSource.bookmark(for: url)
            let s = SourceConfig(kind: .folder, name: url.lastPathComponent, bookmark: bookmark)
            library.addSource(s)
            openSource(s)
            scan(s)
        } catch {
            toast = SourceError.folderUnavailable.errorDescription
        }
    }

    func removeSource(_ s: SourceConfig) {
        scanTasks[s.id]?.cancel()
        scanTasks[s.id] = nil
        downloadQueue.removeAll { library.tracks[$0]?.sourceID == s.id }
        player.removeTracks(of: s.id)
        library.removeSource(s.id)
        Keychain.remove(for: s.id)
        clients[s.id] = nil
        if let root = folderRoots.removeValue(forKey: s.id) { root.stopAccessingSecurityScopedResource() }
        if s.kind == .demo { UserDefaults.standard.set(true, forKey: "demo.removed") }
    }

    func client(for s: SourceConfig) -> WebDAVClient? {
        if let c = clients[s.id] { return c }
        guard s.kind == .webdav, let a = s.address, let url = URL(string: a) else { return nil }
        let c = WebDAVClient(base: url, username: s.username, password: Keychain.password(for: s.id))
        clients[s.id] = c
        return c
    }

    private func openSource(_ s: SourceConfig) {
        switch s.kind {
        case .folder:
            if folderRoots[s.id] == nil, let b = s.bookmark, let url = FolderSource.resolve(b) {
                _ = url.startAccessingSecurityScopedResource()
                folderRoots[s.id] = url
            }
        case .webdav: _ = client(for: s)
        case .demo: break
        }
    }

    /// Tests a WebDAV address before saving: number of folders and songs at the top level.
    static func testConnection(address: URL, username: String, password: String) async -> Result<(Int, Int), SourceError> {
        let c = WebDAVClient(base: address, username: username, password: password)
        do { return .success(try await c.probe()) } catch { return .failure(SourceError.from(error)) }
    }

    private func refreshOnLaunch() async {
        for s in library.sources {
            if s.kind == .demo, library.count(of: s.id) == 0 || !DemoLibrary.pieces.allSatisfy({ FileManager.default.fileExists(atPath: AppPaths.demo.appendingPathComponent(DemoLibrary.relativePath($0)).path) }) {
                scan(s)
            } else if s.kind == .webdav, let c = client(for: s) {
                _ = try? await c.probe()
                enrich(s)
            } else if s.kind == .folder {
                enrich(s)
            }
        }
    }

    // MARK: Scanning

    func scan(_ s: SourceConfig) {
        scanTasks[s.id]?.cancel()
        library.scanStates[s.id] = .scanning(found: 0)
        scanTasks[s.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let files = try await self.list(s)
                guard !Task.isCancelled, self.library.sources.contains(where: { $0.id == s.id }) else { return }
                let count = self.library.merge(source: s.id, files: files, preEnriched: s.kind == .demo,
                                               duration: s.kind == .demo ? DemoLibrary.seconds : nil)
                self.review.scanned(count)
                self.library.scanStates[s.id] = .idle
                self.enrich(s)
                self.maybeAskForReview()
            } catch is CancellationError {
                return
            } catch {
                self.lastErrorAt = Date()
                self.library.scanStates[s.id] = .failed(SourceError.from(error).errorDescription ?? "")
            }
        }
    }

    private func list(_ s: SourceConfig) async throws -> [LibraryStore.ScannedFile] {
        let id = s.id
        switch s.kind {
        case .demo:
            let paths = await Task.detached(priority: .userInitiated) { DemoLibrary.ensureFiles() }.value
            return paths.map { LibraryStore.ScannedFile(path: $0, size: nil, modified: nil) }
        case .webdav:
            guard let c = client(for: s) else { throw SourceError.badAddress }
            let entries = try await c.walk { n in
                Task { @MainActor [weak self] in self?.library.scanStates[id] = .scanning(found: n) }
            }
            return entries.map { LibraryStore.ScannedFile(path: $0.relativePath, size: $0.size, modified: $0.modified) }
        case .folder:
            guard let root = folderRoots[s.id] else { throw SourceError.folderUnavailable }
            let files = try await Task.detached(priority: .userInitiated) {
                try FolderSource.scan(root: root) { n in
                    Task { @MainActor [weak self] in self?.library.scanStates[id] = .scanning(found: n) }
                }
            }.value
            return files.map { LibraryStore.ScannedFile(path: $0.relativePath, size: $0.size, modified: $0.modified) }
        }
    }

    /// Reads tags and artwork in the background, two files at a time, saving as it goes.
    func enrich(_ s: SourceConfig) {
        let pending = library.tracks(of: s.id).filter { !$0.enriched && $0.isPlayable }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !pending.isEmpty, scanTasks[s.id] == nil || library.scanStates[s.id] == .idle else { return }
        let total = pending.count
        library.scanStates[s.id] = .enriching(done: 0, total: total)
        scanTasks[s.id] = Task { [weak self] in
            guard let self else { return }
            var done = 0
            var idx = 0
            while idx < pending.count {
                if Task.isCancelled { return }
                let batch = Array(pending[idx..<min(idx + 2, pending.count)])
                idx += batch.count
                var results: [(Track, MetadataReader.Tags?)] = []
                for t in batch {
                    guard let url = self.playURL(for: t) else { results.append((t, nil)); continue }
                    results.append((t, await MetadataReader.read(url)))
                }
                for (t, tags) in results {
                    self.library.applyTags(tags, to: t.id, rebuild: false)
                    if let art = tags?.artwork, let updated = self.library.tracks[t.id] {
                        ArtworkStore.save(art, albumKey: updated.albumKey)
                    }
                }
                done += batch.count
                if done % 20 == 0 || done == total { self.library.refreshIndex() }
                self.library.scanStates[s.id] = done == total ? .idle : .enriching(done: done, total: total)
            }
            self.library.refreshIndex()
            self.scanTasks[s.id] = nil
        }
    }

    // MARK: URLs and artwork

    func playURL(for t: Track) -> URL? {
        if let local = library.offlineURL(for: t.id) { return local }
        guard let s = library.sources.first(where: { $0.id == t.sourceID }) else { return nil }
        switch s.kind {
        case .demo: return AppPaths.demo.appendingPathComponent(t.path)
        case .folder: return folderRoots[s.id]?.appendingPathComponent(t.path)
        case .webdav: return client(for: s)?.url(for: t.path)
        }
    }

    func artworkImage(albumKey: String) -> UIImage? {
        if let img = artworkCache.object(forKey: albumKey as NSString) { return img }
        let url = ArtworkStore.url(for: albumKey)
        guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return nil }
        artworkCache.setObject(img, forKey: albumKey as NSString)
        return img
    }

    // MARK: Offline

    var offlineCount: Int { library.offline.count }

    func isOffline(_ t: Track) -> Bool { library.offline[t.id] != nil }
    func isQueuedForDownload(_ t: Track) -> Bool { downloadQueue.contains(t.id) || downloading == t.id }

    /// Queues songs for offline; opens the paywall when the free 20 are used.
    func download(_ tracks: [Track]) {
        let wanted = tracks.filter { $0.isPlayable && !isOffline($0) && !isQueuedForDownload($0) }
        guard !wanted.isEmpty else { return }
        let queued = downloadQueue.count + (downloading == nil ? 0 : 1)
        if !pro.limits.canDownload(downloaded: offlineCount, queued: queued, adding: wanted.count) {
            let room = max(0, ProLimits.freeOfflineSongs - offlineCount - queued)
            downloadQueue.append(contentsOf: wanted.prefix(room).map(\.id))
            paywall = .offline
        } else {
            downloadQueue.append(contentsOf: wanted.map(\.id))
        }
        runDownloads()
    }

    private func runDownloads() {
        guard downloading == nil, !downloadQueue.isEmpty else { return }
        let id = downloadQueue.removeFirst()
        guard let t = library.tracks[id], let s = library.sources.first(where: { $0.id == t.sourceID }) else { runDownloads(); return }
        downloading = id
        Task { [weak self] in
            guard let self else { return }
            let name = ArtworkStore.fileName(for: id).replacingOccurrences(of: ".img", with: "") + "." + AudioFormats.ext(t.path)
            let dest = AppPaths.offline.appendingPathComponent(name)
            do {
                switch s.kind {
                case .webdav:
                    guard let c = self.client(for: s) else { throw SourceError.badAddress }
                    try await c.download(t.path, to: dest)
                case .demo, .folder:
                    guard let src = self.playURL(for: t) else { throw SourceError.folderUnavailable }
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: src, to: dest)
                }
                if self.library.tracks[id] != nil { self.library.setOffline(id, file: name) }
            } catch {
                self.downloadFailures += 1
                self.lastErrorAt = Date()
                self.toast = String(localized: "A song couldn’t be downloaded: \(SourceError.from(error).errorDescription ?? "")", bundle: .l10n)
            }
            self.downloading = nil
            self.runDownloads()
        }
    }

    func removeDownload(_ t: Track) { library.setOffline(t.id, file: nil) }

    // MARK: Playlists

    func createPlaylist(named name: String) -> Playlist? {
        guard pro.limits.canAddPlaylist(existing: library.playlists.count) else {
            paywall = .playlists
            return nil
        }
        return library.createPlaylist(named: name)
    }

    // MARK: Sleep timer

    func requestSleepTimer() -> Bool {
        if pro.limits.hasSleepTimer { return true }
        paywall = .sleepTimer
        return false
    }

    // MARK: Review prompt

    func maybeAskForReview(now: Date = Date()) {
        let ctx = ReviewGate.Context(now: now, recentError: lastErrorAt.map { now.timeIntervalSince($0) < 120 } ?? false,
                                     paywallOpen: paywall != nil, launchedAt: launchedAt)
        guard !AppModel.isUITest, review.gate.shouldAsk(ctx) else { return }
        review.asked(now: now)
        showReviewCard = true
    }

    func reviewLoved() {
        showReviewCard = false
        requestReviewAction()
    }

    func reviewNotYet() {
        showReviewCard = false
        let url = ReviewGate.feedbackURL(appVersion: AppInfo.version, osVersion: UIDevice.current.systemVersion)
        UIApplication.shared.open(url)
    }

    func rateFromSettings() {
        if let url = AppInfo.writeReviewURL { UIApplication.shared.open(url) } else { reviewLoved() }
    }
}
