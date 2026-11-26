import XCTest
@testable import Groovelens

final class CoreTests: XCTestCase {
    func testJudgementWindows() {
        XCTAssertEqual(Judgement.from(offset: 0.02), .perfect)
        XCTAssertEqual(Judgement.from(offset: -0.06), .great)
        XCTAssertEqual(Judgement.from(offset: 0.1), .good)
        XCTAssertEqual(Judgement.from(offset: 0.2), .miss)
    }

    func testGrades() {
        XCTAssertEqual(Grade.from(accuracy: 0.96), .s)
        XCTAssertEqual(Grade.from(accuracy: 0.9), .a)
        XCTAssertTrue(Grade.s > Grade.a)
    }

    func testLevelCurveIsMonotonic() {
        var last = -1
        for l in 1...Levels.maxLevel {
            let x = Levels.xpToReach(l)
            XCTAssertGreaterThan(x, last)
            XCTAssertEqual(Levels.level(forXP: x), l)
            last = x
        }
    }

    func testVLQ() {
        XCTAssertEqual(MIDIExporter.vlq(0), [0x00])
        XCTAssertEqual(MIDIExporter.vlq(0x7F), [0x7F])
        XCTAssertEqual(MIDIExporter.vlq(0x80), [0x81, 0x00])
        XCTAssertEqual(MIDIExporter.vlq(0x3FFF), [0xFF, 0x7F])
    }

    func testMusicXMLDecompose() {
        for n in 1...60 {
            XCTAssertEqual(MusicXMLExporter.decompose(n).reduce(0) { $0 + $1.0 }, n)
        }
    }

    /// 120 BPM click track: the beat tracker should land within 2 BPM.
    func testBeatTrackerOnClick() throws {
        let sr = 22_050.0
        let seconds = 20.0
        var samples = [Float](repeating: 0, count: Int(sr * seconds))
        var t = 0.5
        while t < seconds - 0.1 {
            let start = Int(t * sr)
            for i in 0..<400 where start + i < samples.count {
                samples[start + i] = Float(sin(Double(i) * 0.9) * exp(-Double(i) / 80))
            }
            t += 0.5
        }
        let result = try HPSS.separate(samples, sampleRate: sr) { _ in }
        let raw = SpectralDrumTranscriber().transcribe(result.features)
        let grid = BeatTracker.track(result.features, duration: seconds)
        XCTAssertFalse(raw.isEmpty)
        XCTAssertEqual(grid.tempo, 120, accuracy: 2)
    }
}

// MARK: - In-app language and end-to-end accuracy

final class LanguageTests: XCTestCase {
    @MainActor
    func testInAppLanguageSwitchChangesLookups() {
        defer { LocalizedBundle.use("en") }
        LocalizedBundle.use("ja")
        XCTAssertEqual(String(localized: "Settings"), "設定")
        XCTAssertEqual(Bundle.main.localizedString(forKey: "Settings", value: nil, table: nil), "設定")
        LocalizedBundle.use("de")
        XCTAssertEqual(String(localized: "Settings"), "Einstellungen")
        LocalizedBundle.use("zh-Hant")
        XCTAssertEqual(String(localized: "Settings"), "設定")
        XCTAssertEqual(String(localized: "Delete"), "刪除")
        LocalizedBundle.use("en")
        XCTAssertEqual(String(localized: "Settings"), "Settings")
    }

    func testLanguageCodesNormalize() {
        XCTAssertEqual(AppLanguage.normalize("zh-Hant-TW"), "zh-Hant")
        XCTAssertEqual(AppLanguage.normalize("zh-HK"), "zh-Hant")
        XCTAssertEqual(AppLanguage.normalize("zh-CN"), "zh-Hans")
        XCTAssertEqual(AppLanguage.normalize("pt-PT"), "pt-BR")
        XCTAssertEqual(AppLanguage.normalize("de-AT"), "de")
        XCTAssertEqual(AppLanguage.normalize("ru"), "en")
    }
}

final class EndToEndAccuracyTests: XCTestCase {
    /// Full pipeline on a synthesized mix (drums + chords) with a known answer.
    func testTranscriptionAccuracyOnSyntheticMix() throws {
        let sr = 22_050.0, bpm = 112.0, bars = 16
        let truth = DemoAudio.rockPattern(bars: bars, bpm: bpm)
        let duration = 0.5 + Double(bars * 4) * 60 / bpm + 1.5
        let mix = DemoAudio.render(truth, duration: duration, sampleRate: sr)
        let hpss = try HPSS.separate(mix, sampleRate: sr) { _ in }
        let raw = SpectralDrumTranscriber().transcribe(hpss.features)
        let grid = BeatTracker.track(hpss.features, duration: duration)
        let chart = ChartBuilder.build(raw: raw, grid: grid, duration: duration)

        print(String(format: "ACCURACY tempo %.1f (truth %.0f), meter %d/4, hits %d (truth %d)", chart.tempo, bpm, chart.beatsPerBar, chart.hits.count, truth.count))
        var f1s: [DrumPiece: Double] = [:]
        for piece in [DrumPiece.kick, .snare, .hihat] {
            let t = truth.filter { $0.piece == piece }.map(\.time)
            let d = chart.hits.filter { $0.piece == piece }.map(\.time)
            var used = Set<Int>(), tp = 0
            for x in t {
                if let j = d.indices.filter({ !used.contains($0) && abs(d[$0] - x) <= 0.05 }).min(by: { abs(d[$0] - x) < abs(d[$1] - x) }) {
                    used.insert(j); tp += 1
                }
            }
            let recall = t.isEmpty ? 1 : Double(tp) / Double(t.count)
            let precision = d.isEmpty ? 0 : Double(tp) / Double(d.count)
            let f1 = recall + precision == 0 ? 0 : 2 * recall * precision / (recall + precision)
            f1s[piece] = f1
            print(String(format: "ACCURACY %@ recall %.2f precision %.2f F1 %.2f (truth %d, found %d)", piece.rawValue, recall, precision, f1, t.count, d.count))
        }
        XCTAssertEqual(chart.tempo, bpm, accuracy: 2)
        XCTAssertEqual(chart.beatsPerBar, 4)
        XCTAssertGreaterThan(f1s[.kick] ?? 0, 0.7)
        XCTAssertGreaterThan(f1s[.snare] ?? 0, 0.6)
        XCTAssertGreaterThan(f1s[.hihat] ?? 0, 0.5)
    }
}
