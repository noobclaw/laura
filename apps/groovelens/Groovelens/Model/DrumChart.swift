import Foundation

/// The six kit pieces Groovelens charts. Order = lane order on the Stage (left → right).
enum DrumPiece: String, Codable, CaseIterable, Identifiable, Hashable {
    case kick, snare, hihat, tom, ride, crash

    var id: String { rawValue }
    var lane: Int { DrumPiece.allCases.firstIndex(of: self) ?? 0 }

    /// Short HUD label (not translated: these are universal drum abbreviations on the lane).
    var laneLabel: String {
        switch self {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .hihat: return "HAT"
        case .tom: return "TOM"
        case .ride: return "RIDE"
        case .crash: return "CRASH"
        }
    }

    /// Full, translated name.
    var displayName: String {
        switch self {
        case .kick: return String(localized: "Kick")
        case .snare: return String(localized: "Snare")
        case .hihat: return String(localized: "Hi-hat")
        case .tom: return String(localized: "Tom")
        case .ride: return String(localized: "Ride")
        case .crash: return String(localized: "Crash")
        }
    }

    var isCymbal: Bool { self == .hihat || self == .ride || self == .crash }
    var isFoot: Bool { self == .kick }

    /// General MIDI percussion key.
    func midiNote(open: Bool) -> UInt8 {
        switch self {
        case .kick: return 36
        case .snare: return 38
        case .hihat: return open ? 46 : 42
        case .tom: return 45
        case .ride: return 51
        case .crash: return 49
        }
    }

    /// Staff position in half-spaces above the bottom line (E4 = 0), standard drum key.
    var staffPosition: Int {
        switch self {
        case .kick: return 1     // F4 space
        case .tom: return 6      // D5 line (high/mid tom)
        case .snare: return 5    // C5 space
        case .ride: return 8     // F5 line
        case .hihat: return 9    // G5 above the staff
        case .crash: return 10   // A5 ledger line
        }
    }
}

struct DrumHit: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// Seconds in the source recording (snapped onto the beat grid).
    var time: Double
    var piece: DrumPiece
    /// 0...1
    var velocity: Float
    var isOpen: Bool = false
    var isGhost: Bool = false
    var bar: Int
    /// Position inside the bar, in grid ticks (DrumChart.ticksPerBeat per beat).
    var tick: Int
}

enum SectionKind: String, Codable, CaseIterable {
    case intro, verse, chorus, bridge, outro, part

    var title: String {
        switch self {
        case .intro: return String(localized: "Intro")
        case .verse: return String(localized: "Verse")
        case .chorus: return String(localized: "Chorus")
        case .bridge: return String(localized: "Bridge")
        case .outro: return String(localized: "Outro")
        case .part: return String(localized: "Part")
        }
    }
}

struct ChartSection: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: SectionKind
    /// 1-based ordinal among sections of the same kind ("Verse 2").
    var ordinal: Int
    var startBar: Int
    /// Exclusive.
    var endBar: Int

    var label: String { ordinal > 1 ? "\(kind.title) \(ordinal)" : kind.title }
    var barCount: Int { endBar - startBar }
}

struct DrumChart: Codable, Hashable {
    static let ticksPerBeat = 12
    static let currentVersion = 1

    var version: Int = DrumChart.currentVersion
    var duration: Double
    /// Beat onsets in seconds, monotonically increasing, covering the whole song.
    var beatTimes: [Double]
    var beatsPerBar: Int
    /// Index in `beatTimes` of the first downbeat (bar 0, beat 0).
    var downbeatOffset: Int
    var tempo: Double
    /// 0.5 = straight, ~0.66 = full triplet swing.
    var swing: Double
    var hits: [DrumHit]
    var sections: [ChartSection]
    /// Bar indices detected as fills.
    var fillBars: [Int]

    var ticksPerBar: Int { beatsPerBar * DrumChart.ticksPerBeat }

    var barCount: Int {
        let usable = beatTimes.count - downbeatOffset
        return max(1, Int((Double(usable) / Double(beatsPerBar)).rounded(.up)))
    }

    var meterLabel: String { "\(beatsPerBar)/4" }

    /// Seconds at (bar, tick), interpolating/extrapolating along the beat grid.
    func time(bar: Int, tick: Int) -> Double {
        let beatFloat = Double(bar * beatsPerBar + downbeatOffset) + Double(tick) / Double(DrumChart.ticksPerBeat)
        return time(atBeat: beatFloat)
    }

    func time(atBeat beat: Double) -> Double {
        guard beatTimes.count >= 2 else { return beat * 60 / max(tempo, 1) }
        let i = Int(floor(beat))
        let frac = beat - Double(i)
        if i < 0 {
            let period = beatTimes[1] - beatTimes[0]
            return beatTimes[0] + beat * period
        }
        if i >= beatTimes.count - 1 {
            let n = beatTimes.count
            let period = beatTimes[n - 1] - beatTimes[n - 2]
            return beatTimes[n - 1] + (beat - Double(n - 1)) * period
        }
        return beatTimes[i] + frac * (beatTimes[i + 1] - beatTimes[i])
    }

    func barStart(_ bar: Int) -> Double { time(bar: bar, tick: 0) }

    func bar(at time: Double) -> Int {
        var lo = 0, hi = barCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if barStart(mid + 1) <= time { lo = mid + 1 } else { hi = mid }
        }
        return min(max(lo, 0), barCount - 1)
    }

    func hits(inBars range: Range<Int>) -> [DrumHit] {
        hits.filter { range.contains($0.bar) }
    }

    func section(containing bar: Int) -> ChartSection? {
        sections.first { bar >= $0.startBar && bar < $0.endBar }
    }

    /// 16-cell visual fingerprint of the most typical bar (piece lane index or -1).
    func fingerprint() -> [Int] {
        var counts: [String: (Int, [Int])] = [:]
        let barsUsed = Set(hits.map(\.bar))
        for b in barsUsed {
            let cells = cellPattern(bar: b)
            let key = cells.map(String.init).joined(separator: ",")
            let prev = counts[key]?.0 ?? 0
            counts[key] = (prev + 1, cells)
        }
        let best = counts.values.max { lhs, rhs in
            let ln = lhs.1.filter { $0 >= 0 }.count, rn = rhs.1.filter { $0 >= 0 }.count
            return lhs.0 * 4 + ln < rhs.0 * 4 + rn
        }
        return best?.1 ?? Array(repeating: -1, count: 16)
    }

    func cellPattern(bar: Int) -> [Int] {
        var cells = Array(repeating: -1, count: 16)
        let priority: [DrumPiece] = [.snare, .kick, .crash, .tom, .ride, .hihat]
        for h in hits where h.bar == bar {
            let cell = min(15, h.tick * 16 / max(ticksPerBar, 1))
            let current = cells[cell]
            if current < 0 {
                cells[cell] = h.piece.lane
            } else {
                let currentPiece = DrumPiece.allCases[current]
                if (priority.firstIndex(of: h.piece) ?? 9) < (priority.firstIndex(of: currentPiece) ?? 9) {
                    cells[cell] = h.piece.lane
                }
            }
        }
        return cells
    }
}
