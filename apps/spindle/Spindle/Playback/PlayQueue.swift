import AVFoundation
import Foundation

enum RepeatMode: String, Codable, CaseIterable { case off, all, one }

/// The order songs play in. Pure value type so every rule is unit-tested.
struct PlayQueue: Equatable {
    private(set) var tracks: [Track] = []
    /// Play order as indices into `tracks` (shuffled or not).
    private(set) var order: [Int] = []
    private(set) var position: Int = 0
    var repeatMode: RepeatMode = .off
    private(set) var shuffled = false

    var current: Track? { order.indices.contains(position) ? tracks[order[position]] : nil }
    var upcoming: [Track] { position + 1 < order.count ? order[(position + 1)...].map { tracks[$0] } : [] }
    var isEmpty: Bool { tracks.isEmpty }

    init() {}

    init(tracks: [Track], startAt: Int = 0, shuffle: Bool = false) {
        self.tracks = tracks
        self.order = Array(tracks.indices)
        self.position = max(0, min(startAt, max(tracks.count - 1, 0)))
        if shuffle { setShuffle(true) }
    }

    /// Shuffling keeps the current song first, then every other song once (no repeats within a round).
    mutating func setShuffle(_ on: Bool, using rng: inout some RandomNumberGenerator) {
        guard !tracks.isEmpty else { shuffled = on; return }
        let currentIndex = order.indices.contains(position) ? order[position] : 0
        if on {
            var rest = tracks.indices.filter { $0 != currentIndex }
            rest.shuffle(using: &rng)
            order = [currentIndex] + rest
            position = 0
        } else {
            order = Array(tracks.indices)
            position = currentIndex
        }
        shuffled = on
    }

    mutating func setShuffle(_ on: Bool) {
        var rng = SystemRandomNumberGenerator()
        setShuffle(on, using: &rng)
    }

    /// What plays after the current song ends on its own. nil = stop.
    mutating func advanceAfterFinish() -> Track? {
        if repeatMode == .one { return current }
        return next(wrap: repeatMode == .all)
    }

    /// The Next button: always moves on; wraps around at the end.
    mutating func next(wrap: Bool = true) -> Track? {
        guard !order.isEmpty else { return nil }
        if position + 1 < order.count {
            position += 1
        } else if wrap {
            position = 0
        } else {
            return nil
        }
        return current
    }

    /// The Previous button: restarts the song if more than 3 s in, otherwise goes back one.
    enum PreviousAction: Equatable { case restart, moved }
    mutating func previous(elapsed: Double) -> PreviousAction {
        if elapsed > 3 || position == 0 { return .restart }
        position -= 1
        return .moved
    }

    mutating func jump(toOrderIndex i: Int) {
        guard order.indices.contains(i) else { return }
        position = i
    }

    /// Moves an upcoming song (offsets relative to `upcoming`).
    mutating func moveUpcoming(from: Int, to: Int) {
        let a = position + 1 + from, b = position + 1 + to
        guard order.indices.contains(a), b >= position + 1, b <= order.count else { return }
        let item = order.remove(at: a)
        order.insert(item, at: min(b > a ? b - 1 : b, order.count))
    }

    mutating func removeUpcoming(at offset: Int) {
        let a = position + 1 + offset
        guard order.indices.contains(a) else { return }
        order.remove(at: a)
    }

    mutating func playNext(_ track: Track) {
        tracks.append(track)
        order.insert(tracks.count - 1, at: min(position + 1, order.count))
    }

    /// Drops songs that belong to a removed source.
    mutating func removeTracks(where shouldRemove: (Track) -> Bool) {
        let cur = current
        var kept: [Track] = []
        for t in tracks where !shouldRemove(t) { kept.append(t) }
        let newOrder = order.map { tracks[$0] }.filter { !shouldRemove($0) }
        tracks = kept
        order = newOrder.compactMap { t in kept.firstIndex(where: { $0.id == t.id }) }
        if let cur, let i = order.firstIndex(where: { tracks[$0].id == cur.id }) { position = i } else { position = 0 }
    }
}

/// Decides when a stream has been stuck long enough to rebuild it.
struct StallWatchdog: Equatable {
    static let limit: TimeInterval = 8
    static let maxRetriesPerTrack = 3
    private(set) var waitingSince: Date?
    private(set) var retries = 0

    enum Decision: Equatable { case wait, reconnect, skip }

    mutating func update(waiting: Bool, wantsToPlay: Bool, now: Date) -> Decision {
        guard waiting && wantsToPlay else { waitingSince = nil; return .wait }
        guard let since = waitingSince else { waitingSince = now; return .wait }
        guard now.timeIntervalSince(since) > StallWatchdog.limit else { return .wait }
        waitingSince = now
        retries += 1
        return retries > StallWatchdog.maxRetriesPerTrack ? .skip : .reconnect
    }

    mutating func trackChanged() { waitingSince = nil; retries = 0 }
}

/// Audio session rules: resume after an interruption only when iOS says so, pause when headphones go away.
enum AudioSessionPolicy {
    static func shouldResume(after options: AVAudioSession.InterruptionOptions, wasPlaying: Bool) -> Bool {
        wasPlaying && options.contains(.shouldResume)
    }
    static func shouldPause(for reason: AVAudioSession.RouteChangeReason) -> Bool {
        reason == .oldDeviceUnavailable
    }
}

/// Sleep timer: minutes, or stop at the end of the current song.
enum SleepTimer: Equatable {
    case off
    case minutes(Int, fireAt: Date)
    case endOfTrack

    static let choices = [15, 30, 45, 60]

    func isDue(now: Date) -> Bool {
        if case .minutes(_, let at) = self { return now >= at }
        return false
    }
}
