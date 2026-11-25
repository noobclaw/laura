import XCTest
@testable import Groovelens

// MARK: - Fixtures

enum Fixture {
    /// 120 BPM, 4/4, beats every 0.5 s starting at 0.
    static func beats(count: Int, period: Double = 0.5, start: Double = 0) -> [Double] {
        (0..<count).map { start + Double($0) * period }
    }

    /// A rock groove: kick on 1 & 3, snare on 2 & 4, closed hi-hat 8ths. `fillBar` gets 16th toms+snare instead.
    static func rockRaw(bars: Int, period: Double = 0.5, fillBar: Int? = nil, jitter: Double = 0) -> [RawHit] {
        var out: [RawHit] = []
        var seed: UInt64 = 7
        func j() -> Double {
            guard jitter > 0 else { return 0 }
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 2 * jitter
        }
        for bar in 0..<bars {
            let b0 = Double(bar * 4) * period
            if bar == fillBar {
                for s in 0..<16 {
                    let t = b0 + Double(s) * period / 4
                    out.append(RawHit(time: t + j(), piece: s % 2 == 0 ? .snare : .tom, velocity: 0.8, isOpen: false))
                }
                out.append(RawHit(time: b0 + j(), piece: .kick, velocity: 0.9, isOpen: false))
                continue
            }
            for beat in 0..<4 {
                let t = b0 + Double(beat) * period
                out.append(RawHit(time: t + j(), piece: beat % 2 == 0 ? .kick : .snare, velocity: 0.9, isOpen: false))
                out.append(RawHit(time: t + j(), piece: .hihat, velocity: 0.6, isOpen: false))
                out.append(RawHit(time: t + period / 2 + j(), piece: .hihat, velocity: 0.5, isOpen: false))
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    static func rockChart(bars: Int = 32, fillBar: Int? = 15, jitter: Double = 0) -> DrumChart {
        let raw = rockRaw(bars: bars, fillBar: fillBar, jitter: jitter)
        let beats = beats(count: bars * 4 + 1)
        return ChartBuilder.build(raw: raw, grid: BeatGrid(beatTimes: beats, tempo: 120), duration: Double(bars * 4) * 0.5)
    }

    static func simpleChart(_ hits: [DrumHit], beats: Int = 16) -> DrumChart {
        DrumChart(duration: Double(beats) * 0.5, beatTimes: Fixture.beats(count: beats + 1), beatsPerBar: 4, downbeatOffset: 0,
                  tempo: 120, swing: 0.5, hits: hits, sections: [], fillBars: [])
    }

    static func hit(_ piece: DrumPiece, bar: Int, tick: Int) -> DrumHit {
        DrumHit(time: Double(bar * 4) * 0.5 + Double(tick) / 12 * 0.5, piece: piece, velocity: 0.8, bar: bar, tick: tick)
    }
}

// MARK: - Chart building

final class ChartBuilderTests: XCTestCase {
    func testMeterAndDownbeat() {
        let chart = Fixture.rockChart()
        XCTAssertEqual(chart.beatsPerBar, 4)
        XCTAssertEqual(chart.downbeatOffset, 0)
        XCTAssertEqual(chart.barCount, 33)   // 129 beats → 33 bars (last one partial)
    }

    func testQuantizesTheGrooveExactly() {
        let chart = Fixture.rockChart(fillBar: nil)
        let bar3 = chart.hits.filter { $0.bar == 3 }
        XCTAssertEqual(Set(bar3.filter { $0.piece == .kick }.map(\.tick)), [0, 24])
        XCTAssertEqual(Set(bar3.filter { $0.piece == .snare }.map(\.tick)), [12, 36])
        XCTAssertEqual(Set(bar3.filter { $0.piece == .hihat }.map(\.tick)), Set(stride(from: 0, to: 48, by: 6)))
        XCTAssertEqual(chart.hits.count, 32 * 12)
    }

    func testQuantizerSnapsJitteredHits() {
        let chart = Fixture.rockChart(fillBar: nil, jitter: 0.02)   // ±20 ms human timing
        for h in chart.hits where h.piece == .kick {
            XCTAssertTrue([0, 24].contains(h.tick), "kick landed on tick \(h.tick)")
        }
        XCTAssertEqual(chart.hits.count, 32 * 12)
    }

    func testNoDuplicateHitsOnTheSameTick() {
        let chart = Fixture.rockChart()
        let keys = chart.hits.map { "\($0.piece)-\($0.bar)-\($0.tick)" }
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testHitsAreSortedAndInsideTheirBar() {
        let chart = Fixture.rockChart()
        XCTAssertEqual(chart.hits.map(\.time), chart.hits.map(\.time).sorted())
        for h in chart.hits {
            XCTAssertGreaterThanOrEqual(h.tick, 0)
            XCTAssertLessThan(h.tick, chart.ticksPerBar)
            XCTAssertEqual(h.time, chart.time(bar: h.bar, tick: h.tick), accuracy: 1e-9)
        }
    }

    func testDetectsTheFillBar() {
        let chart = Fixture.rockChart(fillBar: 15)
        XCTAssertTrue(chart.fillBars.contains(15), "fills: \(chart.fillBars)")
        XCTAssertFalse(chart.fillBars.contains(14))
        XCTAssertLessThanOrEqual(chart.fillBars.count, 2)
    }

    func testSectionsCoverTheSongWithoutGaps() {
        let chart = Fixture.rockChart()
        XCTAssertFalse(chart.sections.isEmpty)
        XCTAssertEqual(chart.sections.first?.startBar, 0)
        XCTAssertEqual(chart.sections.last?.endBar, chart.barCount)
        for (a, b) in zip(chart.sections, chart.sections.dropFirst()) {
            XCTAssertEqual(a.endBar, b.startBar)
            XCTAssertLessThan(a.startBar, a.endBar)
        }
    }

    func testTripletsAreRecognized() {
        var raw: [RawHit] = []
        for beat in 0..<64 {
            for k in 0..<3 { raw.append(RawHit(time: Double(beat) * 0.5 + Double(k) * 0.5 / 3, piece: .ride, velocity: 0.6, isOpen: false)) }
            if beat % 2 == 0 { raw.append(RawHit(time: Double(beat) * 0.5, piece: .kick, velocity: 0.9, isOpen: false)) }
            else { raw.append(RawHit(time: Double(beat) * 0.5, piece: .snare, velocity: 0.9, isOpen: false)) }
        }
        let chart = ChartBuilder.build(raw: raw, grid: BeatGrid(beatTimes: Fixture.beats(count: 65), tempo: 120), duration: 32)
        let rideTicks = Set(chart.hits.filter { $0.piece == .ride }.map { $0.tick % 12 })
        XCTAssertEqual(rideTicks, [0, 4, 8])
    }
}

// MARK: - Chart time mapping

final class DrumChartTests: XCTestCase {
    func testTimeMappingIsMonotonicAndInvertible() {
        let chart = Fixture.rockChart()
        var last = -Double.infinity
        for bar in 0..<chart.barCount {
            for tick in stride(from: 0, to: chart.ticksPerBar, by: 3) {
                let t = chart.time(bar: bar, tick: tick)
                XCTAssertGreaterThan(t, last)
                last = t
            }
            XCTAssertEqual(chart.bar(at: chart.barStart(bar) + 0.01), bar)
        }
    }

    func testExtrapolatesBeforeAndAfterTheGrid() {
        let chart = Fixture.simpleChart([], beats: 8)
        XCTAssertEqual(chart.time(atBeat: -1), -0.5, accuracy: 1e-9)
        XCTAssertEqual(chart.time(atBeat: 10), 5.0, accuracy: 1e-9)
    }

    func testFingerprintHasSixteenCells() {
        let chart = Fixture.rockChart()
        XCTAssertEqual(chart.fingerprint().count, 16)
    }

    func testChartRoundTripsThroughJSON() throws {
        let chart = Fixture.rockChart()
        let data = try JSONEncoder().encode(chart)
        let back = try JSONDecoder().decode(DrumChart.self, from: data)
        XCTAssertEqual(back, chart)
    }
}

// MARK: - Judge

final class JudgeTests: XCTestCase {
    private func judge(_ hits: [DrumHit], mode: PlayMode = .tap) -> Judge {
        Judge(chart: Fixture.simpleChart(hits), bars: 0..<4, mode: mode)
    }

    func testTapOnTimeIsPerfect() {
        let j = judge([Fixture.hit(.snare, bar: 0, tick: 12)])
        XCTAssertEqual(j.tap(lane: DrumPiece.snare.lane, at: 0.5 + 0.01), .perfect)
        XCTAssertEqual(j.combo, 1)
        XCTAssertEqual(j.finalAccuracy, 1, accuracy: 1e-9)
    }

    func testWrongLaneIsIgnored() {
        let j = judge([Fixture.hit(.snare, bar: 0, tick: 12)])
        XCTAssertNil(j.tap(lane: DrumPiece.kick.lane, at: 0.5))
        XCTAssertEqual(j.judgedCount, 0)
    }

    func testEarlyAndLateWindows() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.kick, bar: 1, tick: 0), Fixture.hit(.kick, bar: 2, tick: 0)])
        XCTAssertEqual(j.tap(lane: 0, at: -0.05), .great)
        XCTAssertEqual(j.tap(lane: 0, at: 2.0 + 0.1), .good)
        XCTAssertNil(j.tap(lane: 0, at: 4.0 + 0.2))           // outside every window
        XCTAssertEqual(j.notes[0].offset, -0.05, accuracy: 1e-9)
    }

    func testANoteCanOnlyBeHitOnce() {
        let j = judge([Fixture.hit(.snare, bar: 0, tick: 12)])
        XCTAssertNotNil(j.tap(lane: 1, at: 0.5))
        XCTAssertNil(j.tap(lane: 1, at: 0.51))
        XCTAssertEqual(j.judgedCount, 1)
    }

    func testSweepMarksMissesAndBreaksCombo() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.kick, bar: 0, tick: 12), Fixture.hit(.kick, bar: 0, tick: 24)])
        j.tap(lane: 0, at: 0)
        j.tap(lane: 0, at: 0.5)
        XCTAssertEqual(j.combo, 2)
        j.sweepMisses(now: 1.0 + Judgement.goodWindow + 0.01)
        XCTAssertEqual(j.combo, 0)
        XCTAssertEqual(j.maxCombo, 2)
        XCTAssertEqual(j.counts[.miss], 1)
        XCTAssertEqual(j.finalAccuracy, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testUnplayedNotesCountAgainstFinalAccuracy() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.kick, bar: 1, tick: 0)])
        j.tap(lane: 0, at: 0)
        XCTAssertEqual(j.accuracy, 1, accuracy: 1e-9)          // live: only judged notes
        XCTAssertEqual(j.finalAccuracy, 0.5, accuracy: 1e-9)   // final: every note
    }

    func testWatchModeNeverSweeps() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0)], mode: .watch)
        j.sweepMisses(now: 100)
        XCTAssertEqual(j.judgedCount, 0)
    }

    func testMicHitJudgesEverythingOnThatInstant() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.hihat, bar: 0, tick: 0), Fixture.hit(.snare, bar: 0, tick: 12)], mode: .kit)
        let r = j.micHit(at: 0.02)
        XCTAssertEqual(r?.0, .perfect)
        XCTAssertEqual(Set(r?.1 ?? []), [DrumPiece.kick.lane, DrumPiece.hihat.lane])
        XCTAssertEqual(j.judgedCount, 2)
        XCTAssertNil(j.micHit(at: 0.25))   // between notes, nothing within a window
    }

    func testBarTimingsReportRushing() {
        let j = judge([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.kick, bar: 0, tick: 24)])
        j.tap(lane: 0, at: -0.03)
        j.tap(lane: 0, at: 1.0 - 0.03)
        let t = j.barTimings()
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].meanOffset, -0.03, accuracy: 1e-9)
    }

    func testOnlyTheSelectedBarsArePlayable() {
        let chart = Fixture.simpleChart([Fixture.hit(.kick, bar: 0, tick: 0), Fixture.hit(.kick, bar: 2, tick: 0)])
        let j = Judge(chart: chart, bars: 2..<3, mode: .tap)
        XCTAssertEqual(j.notes.count, 1)
        XCTAssertEqual(j.notes.first?.bar, 2)
    }

    func testXPRewardsSpeedAndFirstClear() {
        let hits = (0..<4).map { Fixture.hit(.kick, bar: $0, tick: 0) }
        let full = judge(hits), slow = judge(hits)
        for (i, h) in hits.enumerated() { full.tap(lane: 0, at: h.time); slow.tap(lane: 0, at: h.time); _ = i }
        XCTAssertGreaterThan(full.xp(speed: 1, firstClear: false), slow.xp(speed: 0.5, firstClear: false))
        XCTAssertEqual(full.xp(speed: 1, firstClear: true) - full.xp(speed: 1, firstClear: false), 50)
    }
}

// MARK: - Progression

final class ProfileTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "groovelens.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func run(_ p: PlayerProfile, accuracy: Double = 0.9, combo: Int = 10, mode: PlayMode = .tap,
                     fill: Bool = false, seconds: Double = 60, xp: Int = 50) -> PlayerProfile.RunReport {
        p.record(.init(songID: UUID(), sectionLabel: nil, isFill: fill, accuracy: accuracy, grade: Grade.from(accuracy: accuracy),
                       maxCombo: combo, speed: 1, mode: mode, seconds: seconds, runXP: xp))
    }

    func testFirstRunStartsAStreakAndGivesXP() {
        let p = PlayerProfile(defaults: defaults)
        let r = run(p)
        XCTAssertEqual(p.streak, 1)
        XCTAssertGreaterThanOrEqual(p.xp, 50)
        XCTAssertTrue(r.newAchievements.contains { $0.id == "first_clear" })
        XCTAssertEqual(p.completedRuns, 1)
    }

    func testSecondRunSameDayDoesNotGrowTheStreak() {
        let p = PlayerProfile(defaults: defaults)
        _ = run(p); _ = run(p)
        XCTAssertEqual(p.streak, 1)
    }

    func testAchievementsUnlockOnce() {
        let p = PlayerProfile(defaults: defaults)
        let a = run(p, combo: 60)
        let b = run(p, combo: 60)
        XCTAssertTrue(a.newAchievements.contains { $0.id == "combo_50" })
        XCTAssertFalse(b.newAchievements.contains { $0.id == "combo_50" })
    }

    func testReviewIsAskedOnTheThirdRunOnly() {
        let p = PlayerProfile(defaults: defaults)
        XCTAssertFalse(run(p).shouldAskForReview)
        XCTAssertFalse(run(p).shouldAskForReview)
        XCTAssertTrue(run(p).shouldAskForReview)
        XCTAssertFalse(run(p).shouldAskForReview)
    }

    func testWatchRunsNeverAskForReview() {
        let p = PlayerProfile(defaults: defaults)
        for _ in 0..<5 { XCTAssertFalse(run(p, mode: .watch).shouldAskForReview) }
    }

    func testProfilePersists() {
        let p = PlayerProfile(defaults: defaults)
        _ = run(p, xp: 300)
        p.leftHanded = true
        p.latencyOffset = 0.042
        let q = PlayerProfile(defaults: defaults)
        XCTAssertEqual(q.xp, p.xp)
        XCTAssertTrue(q.leftHanded)
        XCTAssertEqual(q.latencyOffset, 0.042, accuracy: 1e-9)
    }

    func testDailyQuestsAreStableAndComplete() {
        let p = PlayerProfile(defaults: defaults)
        p.ensureQuests(songs: []) { _ in nil }
        let first = p.quests.map(\.kind)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(Set(first).count, 3)
        p.ensureQuests(songs: []) { _ in nil }
        XCTAssertEqual(p.quests.map(\.kind), first)   // same day → same quests
        // Practice-minutes quest completes after enough time.
        if p.quests.contains(where: { $0.kind == .practiceMinutes }) {
            let r = run(p, seconds: 6 * 60)
            XCTAssertTrue(r.completedQuests.contains { $0.kind == .practiceMinutes })
            XCTAssertGreaterThan(r.questXP, 0)
        }
    }

    func testSkinsUnlockByLevel() {
        let p = PlayerProfile(defaults: defaults)
        XCTAssertTrue(p.isUnlocked(.neon, pro: false))
        XCTAssertFalse(p.isUnlocked(.arcade, pro: false))
        XCTAssertTrue(p.isUnlocked(.arcade, pro: true))
    }

    func testFreeSongAllowance() {
        let p = PlayerProfile(defaults: defaults)
        for _ in 0..<3 { p.registerAnalysisStarted() }
        XCTAssertEqual(p.analysesStarted, 3)
        XCTAssertFalse(3 < ProStore.freeSongLimit)
    }
}

// MARK: - Exporters

final class ExporterTests: XCTestCase {
    func testMIDIStructure() {
        let chart = Fixture.rockChart(bars: 4, fillBar: nil)
        let bytes = [UInt8](MIDIExporter.data(chart, title: "Test"))
        XCTAssertEqual(Array(bytes[0..<4]), Array("MThd".utf8))
        XCTAssertEqual(Array(bytes[8..<10]), [0, 0])            // format 0
        XCTAssertEqual(Array(bytes[12..<14]), [0x01, 0xE0])     // 480 ppq
        XCTAssertEqual(Array(bytes[14..<18]), Array("MTrk".utf8))
        let len = Int(bytes[18]) << 24 | Int(bytes[19]) << 16 | Int(bytes[20]) << 8 | Int(bytes[21])
        XCTAssertEqual(len, bytes.count - 22)
        XCTAssertEqual(Array(bytes.suffix(3)), [0xFF, 0x2F, 0x00])
        XCTAssertEqual(bytes.filter { $0 == 0x99 }.count, chart.hits.count)   // one note-on per hit (channel 10)
    }

    func testMusicXMLIsWellFormedAndBarsAddUp() throws {
        let chart = Fixture.rockChart(bars: 8, fillBar: 5)
        let xml = MusicXMLExporter.xml(chart, title: "Rock & Roll <test>")
        let parser = XMLParser(data: Data(xml.utf8))
        parser.shouldResolveExternalEntities = false
        let collector = MeasureCollector()
        parser.delegate = collector
        XCTAssertTrue(parser.parse(), "\(parser.parserError?.localizedDescription ?? "")")
        XCTAssertEqual(collector.measures.count, chart.barCount)
        for m in collector.measures {
            for (voice, total) in m where voice != 0 {
                XCTAssertEqual(total, chart.ticksPerBar, "voice \(voice) sums to \(total)")
            }
        }
    }

    func testSafeFileName() {
        XCTAssertEqual(ChartExporter.safeName("AC/DC: Back?"), "AC-DC- Back-")
        XCTAssertEqual(ChartExporter.safeName("   "), "Groovelens chart")
    }
}

/// Sums non-chord note durations per voice per measure.
private final class MeasureCollector: NSObject, XMLParserDelegate {
    var measures: [[Int: Int]] = []
    private var inNote = false, isChord = false
    private var duration = 0, voice = 0
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "measure": measures.append([:])
        case "note": inNote = true; isChord = false; duration = 0; voice = 0
        case "chord": if inNote { isChord = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "duration": if inNote { duration = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        case "voice": if inNote { voice = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        case "note":
            inNote = false
            if !isChord, !measures.isEmpty { measures[measures.count - 1][voice, default: 0] += duration }
        default: break
        }
    }
}
