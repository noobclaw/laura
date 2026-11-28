import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// AVPlayer wrapper with the "never stops" rules: resumes after interruptions iOS allows,
/// rebuilds a stuck stream at the same position, pauses when headphones are pulled.
@MainActor
@Observable
final class PlayerEngine {
    enum Status: Equatable { case idle, loading, playing, paused, reconnecting }

    private(set) var queue = PlayQueue()
    private(set) var status: Status = .idle
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var sleep: SleepTimer = .off
    /// One-line message shown briefly over the mini player.
    var notice: String?

    var current: Track? { queue.current }
    var isPlaying: Bool { status == .playing || status == .loading || status == .reconnecting }

    @ObservationIgnored var resolveURL: @MainActor (Track) -> URL? = { _ in nil }
    @ObservationIgnored var artwork: @MainActor (Track) -> UIImage? = { _ in nil }
    @ObservationIgnored var onSongCompleted: @MainActor () -> Void = {}

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failObserver: NSObjectProtocol?
    @ObservationIgnored private var itemStatus: NSKeyValueObservation?
    @ObservationIgnored private var watchdog = StallWatchdog()
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var sessionReady = false
    @ObservationIgnored private var skipsInARow = 0

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let info = n.userInfo
            MainActor.assumeIsolated { self?.handleRouteChange(info) }
        }
        configureRemoteCommands()
    }

    // MARK: Public controls

    func play(_ tracks: [Track], startAt: Int = 0, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        let mode = queue.repeatMode
        queue = PlayQueue(tracks: tracks, startAt: startAt, shuffle: shuffle)
        queue.repeatMode = mode
        skipsInARow = 0
        load(queue.current, at: 0, autoplay: true)
    }

    func togglePlay() {
        guard queue.current != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard queue.current != nil else { return }
        activateSession()
        wantsToPlay = true
        if player.currentItem == nil { load(queue.current, at: currentTime, autoplay: true); return }
        player.play()
        status = .playing
        updateNowPlaying()
    }

    func pause() {
        wantsToPlay = false
        player.pause()
        if queue.current != nil { status = .paused }
        updateNowPlaying()
    }

    func next() {
        guard let t = queue.next(wrap: true) else { return }
        load(t, at: 0, autoplay: true)
    }

    func previous() {
        switch queue.previous(elapsed: currentTime) {
        case .restart: seek(to: 0)
        case .moved: load(queue.current, at: 0, autoplay: true)
        }
    }

    func seek(to seconds: Double) {
        let t = max(0, min(seconds, duration > 0 ? duration - 0.5 : seconds))
        currentTime = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        queue.repeatMode = all[(all.firstIndex(of: queue.repeatMode)! + 1) % all.count]
    }

    func toggleShuffle() { queue.setShuffle(!queue.shuffled) }

    func playNext(_ track: Track) {
        if queue.isEmpty { play([track]); return }
        queue.playNext(track)
        notice = String(localized: "Plays next", bundle: .l10n)
    }

    func jump(toUpcoming offset: Int) {
        queue.jump(toOrderIndex: queue.position + 1 + offset)
        load(queue.current, at: 0, autoplay: true)
    }

    func moveUpcoming(from: IndexSet, to: Int) {
        guard let f = from.first else { return }
        queue.moveUpcoming(from: f, to: to)
    }

    func removeUpcoming(at offsets: IndexSet) {
        for o in offsets.sorted(by: >) { queue.removeUpcoming(at: o) }
    }

    func setSleep(minutes: Int?) {
        if let minutes { sleep = .minutes(minutes, fireAt: Date().addingTimeInterval(Double(minutes) * 60)) } else { sleep = .off }
    }
    func setSleepEndOfTrack() { sleep = .endOfTrack }

    /// A source was removed: drop its songs; stop if the current one belonged to it.
    func removeTracks(of source: UUID) {
        let currentGone = queue.current?.sourceID == source
        queue.removeTracks { $0.sourceID == source }
        if currentGone { stop() }
    }

    func stop() {
        wantsToPlay = false
        player.replaceCurrentItem(with: nil)
        status = .idle
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Loading

    private func load(_ track: Track?, at time: Double, autoplay: Bool) {
        guard let track else { stop(); return }
        watchdog.trackChanged()
        currentTime = time
        duration = track.duration ?? 0
        guard track.isPlayable, let url = resolveURL(track) else {
            skipUnplayable()
            return
        }
        activateSession()
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        if time > 0 { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)) }
        wantsToPlay = autoplay
        if autoplay {
            player.play()
            status = .loading
        } else {
            status = .paused
        }
        updateNowPlaying()
    }

    private func skipUnplayable() {
        notice = String(localized: "Skipped a song this iPhone can’t play", bundle: .l10n)
        skipsInARow += 1
        if skipsInARow > queue.tracks.count { stop(); return }
        if let t = queue.next(wrap: queue.repeatMode == .all) { load(t, at: 0, autoplay: true) } else { stop() }
    }

    private func observe(_ item: AVPlayerItem) {
        let nc = NotificationCenter.default
        if let endObserver { nc.removeObserver(endObserver) }
        if let failObserver { nc.removeObserver(failObserver) }
        endObserver = nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        failObserver = nc.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnect() }
        }
        itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            let ready = item.status == .readyToPlay
            let secs = item.duration.seconds
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if ready {
                        self.skipsInARow = 0
                        if secs.isFinite && secs > 0 { self.duration = secs }
                        self.updateNowPlaying()
                    } else if failed {
                        self.skipUnplayable()
                    }
                }
            }
        }
    }

    private func finished() {
        onSongCompleted()
        if sleep == .endOfTrack { sleep = .off; pause(); seek(to: 0); return }
        if let t = queue.advanceAfterFinish() {
            load(t, at: 0, autoplay: true)
        } else {
            pause()
            seek(to: 0)
        }
    }

    /// Rebuilds the item at the same position (stuck or failed stream).
    private func reconnect() {
        guard let t = queue.current else { return }
        let at = currentTime
        status = .reconnecting
        load(t, at: at, autoplay: true)
        status = .reconnecting
    }

    private func tick() {
        let t = player.currentTime().seconds
        if t.isFinite { currentTime = t }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        if wantsToPlay {
            switch player.timeControlStatus {
            case .playing: status = .playing
            case .waitingToPlayAtSpecifiedRate: if status != .reconnecting { status = .loading }
            default: break
            }
        }
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        switch watchdog.update(waiting: waiting, wantsToPlay: wantsToPlay, now: Date()) {
        case .wait: break
        case .reconnect: reconnect()
        case .skip:
            notice = String(localized: "This song keeps stalling, so Spindle moved on.", bundle: .l10n)
            next()
        }
        if sleep.isDue(now: Date()) { fadeOutAndPause() }
    }

    private func fadeOutAndPause() {
        sleep = .off
        Task { @MainActor in
            for step in stride(from: 1.0, through: 0.0, by: -0.1) {
                player.volume = Float(step)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            pause()
            player.volume = 1
        }
    }

    // MARK: Audio session

    private func activateSession() {
        guard !sessionReady else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? s.setActive(true)
        sessionReady = true
    }

    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if wantsToPlay { status = .paused }
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if AudioSessionPolicy.shouldResume(after: opts, wasPlaying: wantsToPlay) {
                try? AVAudioSession.sharedInstance().setActive(true)
                player.volume = 1
                player.play()
                status = .playing
            } else {
                wantsToPlay = false
                status = .paused
            }
            updateNowPlaying()
        @unknown default: break
        }
    }

    private func handleRouteChange(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if AudioSessionPolicy.shouldPause(for: reason) { pause() }
    }

    // MARK: Lock screen

    private func configureRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.togglePlay() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = queue.current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let image = artwork(t) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
