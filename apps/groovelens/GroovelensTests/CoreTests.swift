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
