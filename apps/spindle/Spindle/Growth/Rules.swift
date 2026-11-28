import Foundation

/// Free tier limits (PLAN §10). The demo shelf never counts.
struct ProLimits: Equatable {
    static let freeSources = 1
    static let freePlaylists = 2
    static let freeOfflineSongs = 20

    var isPro: Bool

    func canAddSource(existing: [SourceConfig]) -> Bool {
        isPro || existing.filter(\.countsTowardLimit).count < ProLimits.freeSources
    }
    func canAddPlaylist(existing: Int) -> Bool { isPro || existing < ProLimits.freePlaylists }
    /// `downloaded` = finished downloads only (failures never count), `queued` = waiting in the queue.
    func canDownload(downloaded: Int, queued: Int, adding: Int = 1) -> Bool {
        isPro || downloaded + queued + adding <= ProLimits.freeOfflineSongs
    }
    var hasSleepTimer: Bool { isPro }
}

/// When to show the two-step "Enjoying Spindle?" card (PLAN §11).
struct ReviewGate {
    static let minDaysInstalled: Double = 3
    static let minDaysBetween: Double = 30
    static let songsBeforeAsking = 10
    static let bigLibrary = 100

    var installedAt: Date
    var lastAskedAt: Date?
    var completedSongs: Int
    var largestScan: Int

    struct Context { var now: Date; var recentError: Bool; var paywallOpen: Bool; var launchedAt: Date }

    func shouldAsk(_ c: Context) -> Bool {
        if c.recentError || c.paywallOpen { return false }
        if c.now.timeIntervalSince(c.launchedAt) < 5 * 60 && c.now.timeIntervalSince(installedAt) < 5 * 60 { return false }
        if c.now.timeIntervalSince(installedAt) < ReviewGate.minDaysInstalled * 86_400 { return false }
        if let last = lastAskedAt, c.now.timeIntervalSince(last) < ReviewGate.minDaysBetween * 86_400 { return false }
        return completedSongs >= ReviewGate.songsBeforeAsking || largestScan >= ReviewGate.bigLibrary
    }

    /// "Not yet" goes to the support page with the version, never with server details.
    static func feedbackURL(appVersion: String, osVersion: String) -> URL {
        var c = URLComponents(string: "https://256btc.com/support/")!
        c.queryItems = [URLQueryItem(name: "app", value: "spindle"),
                        URLQueryItem(name: "v", value: appVersion),
                        URLQueryItem(name: "ios", value: osVersion)]
        return c.url!
    }
}

/// Persists the review counters in UserDefaults.
final class ReviewTracker {
    private let d: UserDefaults
    init(defaults: UserDefaults = .standard) {
        d = defaults
        if d.object(forKey: "review.installedAt") == nil { d.set(Date(), forKey: "review.installedAt") }
    }
    var gate: ReviewGate {
        ReviewGate(installedAt: d.object(forKey: "review.installedAt") as? Date ?? Date(),
                   lastAskedAt: d.object(forKey: "review.lastAskedAt") as? Date,
                   completedSongs: d.integer(forKey: "review.completedSongs"),
                   largestScan: d.integer(forKey: "review.largestScan"))
    }
    func songCompleted() { d.set(d.integer(forKey: "review.completedSongs") + 1, forKey: "review.completedSongs") }
    func scanned(_ count: Int) { if count > d.integer(forKey: "review.largestScan") { d.set(count, forKey: "review.largestScan") } }
    func asked(now: Date = Date()) { d.set(now, forKey: "review.lastAskedAt") }
}

enum AppInfo {
    /// Filled in once App Store Connect assigns the ID; until then "Rate" uses the system prompt.
    static let appStoreID: String? = nil
    static let privacyURL = URL(string: "https://256btc.com/privacy/spindle/")!
    static let supportURL = URL(string: "https://256btc.com/support/")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var writeReviewURL: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }
}
