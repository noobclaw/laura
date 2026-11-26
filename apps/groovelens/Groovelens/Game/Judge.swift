import Foundation
import Observation

enum PlayMode: String, Codable, CaseIterable, Identifiable {
    case tap, kit, watch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tap: return String(localized: "Tap", bundle: .l10n)
        case .kit: return String(localized: "Kit", bundle: .l10n)
        case .watch: return String(localized: "Watch", bundle: .l10n)
        }
    }
    var subtitle: String {
        switch self {
        case .tap: return String(localized: "Play the pads on screen", bundle: .l10n)
        case .kit: return String(localized: "Play your real kit — the mic scores you", bundle: .l10n)
        case .watch: return String(localized: "Just watch and listen", bundle: .l10n)
        }
    }
    var symbol: String {
        switch self {
        case .tap: return "hand.tap.fill"
        case .kit: return "mic.fill"
        case .watch: return "eye.fill"
        }
    }
}

enum Judgement: String, Codable {
    case perfect, great, good, miss

    static let perfectWindow = 0.035
    static let greatWindow = 0.070
    static let goodWindow = 0.120

    static func from(offset: Double) -> Judgement {
        let a = abs(offset)
        if a <= perfectWindow { return .perfect }
        if a <= greatWindow { return .great }
        if a <= goodWindow { return .good }
        return .miss
    }

    var points: Double {
        switch self {
        case .perfect: return 1
        case .great: return 0.75
        case .good: return 0.4
        case .miss: return 0
        }
    }

    var xpWeight: Int {
        switch self {
        case .perfect: return 3
        case .great: return 2
        case .good: return 1
        case .miss: return 0
        }
    }

    var title: String {
        switch self {
        case .perfect: return String(localized: "PERFECT", bundle: .l10n)
        case .great: return String(localized: "GREAT", bundle: .l10n)
        case .good: return String(localized: "GOOD", bundle: .l10n)
        case .miss: return String(localized: "MISS", bundle: .l10n)
        }
    }
}

enum Grade: String, Codable, CaseIterable, Comparable {
    case s = "S", a = "A", b = "B", c = "C", d = "D"

    static func from(accuracy: Double) -> Grade {
        if accuracy >= 0.95 { return .s }
        if accuracy >= 0.88 { return .a }
        if accuracy >= 0.75 { return .b }
        if accuracy >= 0.60 { return .c }
        return .d
    }

    static func stars(accuracy: Double) -> Int {
        if accuracy >= 0.92 { return 3 }
        if accuracy >= 0.80 { return 2 }
        if accuracy >= 0.60 { return 1 }
        return 0
    }

    private var rank: Int { Grade.allCases.firstIndex(of: self) ?? 0 }
    /// S is "greatest".
    static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rank > rhs.rank }
}

/// One playable note on the Stage. In Kit mode simultaneous notes form one target.
struct GameNote: Identifiable {
    let id: UUID
    let time: Double
    let piece: DrumPiece
    let bar: Int
    let velocity: Float
    var judgement: Judgement?
    var offset: Double = 0
}

struct BarTiming: Identifiable {
    let bar: Int
    var id: Int { bar }
    /// Mean signed offset in seconds (negative = early).
    var meanOffset: Double
    var accuracy: Double
    var notes: Int
}

struct JudgementEvent: Identifiable {
    let id = UUID()
    let judgement: Judgement
    let lane: Int?
    let at: Date
    let offset: Double
}

/// Scores a run of the Stage.
@Observable
final class Judge {
    private(set) var notes: [GameNote]
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var counts: [Judgement: Int] = [:]
    private(set) var lastEvent: JudgementEvent?
    @ObservationIgnored private var nextMissIndex = 0
    let mode: PlayMode

    init(chart: DrumChart, bars: Range<Int>, mode: PlayMode) {
        self.mode = mode
        self.notes = chart.hits
            .filter { bars.contains($0.bar) }
            .map { GameNote(id: $0.id, time: $0.time, piece: $0.piece, bar: $0.bar, velocity: $0.velocity) }
            .sorted { $0.time < $1.time }
    }

    var judgedCount: Int { counts.values.reduce(0, +) }

    var accuracy: Double {
        let judged = notes.filter { $0.judgement != nil }
        guard !judged.isEmpty else { return 0 }
        return judged.reduce(0) { $0 + ($1.judgement?.points ?? 0) } / Double(judged.count)
    }

    var finalAccuracy: Double {
        guard !notes.isEmpty else { return 0 }
        return notes.reduce(0) { $0 + ($1.judgement?.points ?? 0) } / Double(notes.count)
    }

    /// Tap mode: a pad was hit at song time `t`.
    @discardableResult
    func tap(lane: Int, at t: Double) -> Judgement? {
        var best: Int?
        var bestDist = Judgement.goodWindow
        for i in notes.indices where notes[i].judgement == nil && notes[i].piece.lane == lane {
            let d = abs(notes[i].time - t)
            if d <= bestDist { bestDist = d; best = i }
            if notes[i].time - t > Judgement.goodWindow { break }
        }
        guard let i = best else { return nil }
        return record(index: i, offset: t - notes[i].time, lane: lane)
    }

    /// Kit mode: the microphone heard a stroke at song time `t`. Judges every note on that instant.
    /// Returns the judgement and the lanes it landed on.
    @discardableResult
    func micHit(at t: Double) -> (Judgement, [Int])? {
        var best: Int?
        var bestDist = Judgement.goodWindow
        for i in notes.indices where notes[i].judgement == nil {
            let d = abs(notes[i].time - t)
            if d <= bestDist { bestDist = d; best = i }
            if notes[i].time - t > Judgement.goodWindow { break }
        }
        guard let i = best else { return nil }
        let target = notes[i].time
        let offset = t - target
        var result: Judgement = .miss
        var lanes: [Int] = []
        for j in notes.indices where notes[j].judgement == nil && abs(notes[j].time - target) < 0.012 {
            result = record(index: j, offset: offset, lane: notes[j].piece.lane)
            lanes.append(notes[j].piece.lane)
        }
        return (result, lanes)
    }

    /// Marks notes that slipped past the window. Call every frame.
    func sweepMisses(now t: Double) {
        guard mode != .watch else { return }
        while nextMissIndex < notes.count {
            let n = notes[nextMissIndex]
            if n.judgement != nil { nextMissIndex += 1; continue }
            if t - n.time > Judgement.goodWindow {
                _ = record(index: nextMissIndex, offset: t - n.time, lane: n.piece.lane, forced: .miss)
                nextMissIndex += 1
            } else {
                break
            }
        }
    }

    /// `forced` lets the sweeper record a miss; an offset exactly on the Good edge would otherwise grade as Good.
    private func record(index i: Int, offset: Double, lane: Int?, forced: Judgement? = nil) -> Judgement {
        let j = forced ?? Judgement.from(offset: offset)
        notes[i].judgement = j
        notes[i].offset = offset
        counts[j, default: 0] += 1
        if j == .miss {
            combo = 0
        } else {
            combo += 1
            maxCombo = max(maxCombo, combo)
        }
        lastEvent = JudgementEvent(judgement: j, lane: lane, at: .now, offset: offset)
        return j
    }

    func barTimings() -> [BarTiming] {
        let grouped = Dictionary(grouping: notes.filter { $0.judgement != nil }, by: \.bar)
        return grouped.keys.sorted().map { bar in
            let ns = grouped[bar] ?? []
            let hits = ns.filter { $0.judgement != .miss }
            let mean = hits.isEmpty ? 0 : hits.reduce(0) { $0 + $1.offset } / Double(hits.count)
            let acc = ns.reduce(0) { $0 + ($1.judgement?.points ?? 0) } / Double(max(ns.count, 1))
            return BarTiming(bar: bar, meanOffset: mean, accuracy: acc, notes: ns.count)
        }
    }

    func xp(speed: Double, firstClear: Bool) -> Int {
        let base = notes.reduce(0) { $0 + ($1.judgement?.xpWeight ?? 0) }
        let speedFactor = 0.5 + 0.5 * min(1, speed)
        var xp = Int(Double(base) * speedFactor)
        xp += Int(finalAccuracy * 100)
        if firstClear && finalAccuracy >= 0.6 { xp += 50 }
        return max(5, xp)
    }
}
