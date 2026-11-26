import AVFoundation
import Foundation

/// Synthesizes a mixed track (drums + sustained chords) from a known drum pattern.
/// Used by the end-to-end accuracy test and by the UI-test demo song, so both exercise the real pipeline.
enum DemoAudio {
    struct Note {
        let time: Double
        let piece: DrumPiece
    }

    /// Rock groove at `bpm`: kick 1 & 3 (+ "and" of 3), snare 2 & 4, closed hi-hat 8ths, crash on bar 1,
    /// and a 16th-note snare/tom fill in every 4th bar.
    static func rockPattern(bars: Int, bpm: Double = 112, lead: Double = 0.5) -> [Note] {
        let beat = 60 / bpm
        var out: [Note] = []
        for bar in 0..<bars {
            let b0 = lead + Double(bar * 4) * beat
            if bar % 4 == 3 {
                for b in 0..<2 {
                    out.append(Note(time: b0 + Double(b) * beat, piece: b == 0 ? .kick : .snare))
                    out.append(Note(time: b0 + Double(b) * beat, piece: .hihat))
                    out.append(Note(time: b0 + (Double(b) + 0.5) * beat, piece: .hihat))
                }
                for s in 8..<16 {
                    out.append(Note(time: b0 + Double(s) * beat / 4, piece: s < 12 ? .snare : .tom))
                }
                continue
            }
            for b in 0..<4 {
                let t = b0 + Double(b) * beat
                out.append(Note(time: t, piece: b % 2 == 0 ? .kick : .snare))
                out.append(Note(time: t, piece: (b == 0 && bar % 4 == 0) ? .crash : .hihat))
                out.append(Note(time: t + beat / 2, piece: .hihat))
                if b == 2 { out.append(Note(time: t + beat / 2, piece: .kick)) }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Mono Float32 samples. `backing` adds sustained chords (harmonic content HPSS should remove).
    static func render(_ notes: [Note], duration: Double, sampleRate: Double = 22_050, backing: Bool = true, seed: UInt64 = 42) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng = seed
        func noise() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: rng >> 1) % 2_000_000) / 1_000_000 - 1
        }
        func add(_ start: Int, _ len: Int, _ f: (Int) -> Float) {
            for i in 0..<len where start + i < n && start + i >= 0 { out[start + i] += f(i) }
        }
        for note in notes {
            let s = Int(note.time * sampleRate)
            let sr = Float(sampleRate)
            switch note.piece {
            case .kick:
                var phase: Float = 0
                add(s, Int(0.25 * sampleRate)) { i in
                    let t = Float(i) / sr
                    let f = 45 + 90 * exp(-t * 30)
                    phase += 2 * .pi * f / sr
                    return 0.9 * sin(phase) * exp(-t * 14)
                }
            case .snare:
                add(s, Int(0.18 * sampleRate)) { i in
                    let t = Float(i) / sr
                    return 0.45 * noise() * exp(-t * 22) + 0.35 * sin(2 * .pi * 190 * t) * exp(-t * 30)
                }
            case .hihat:
                var prev: Float = 0
                add(s, Int(0.05 * sampleRate)) { i in
                    let t = Float(i) / sr
                    let x = noise(); let hp = x - prev; prev = x
                    return 0.22 * hp * exp(-t * 90)
                }
            case .tom:
                var phase: Float = 0
                add(s, Int(0.3 * sampleRate)) { i in
                    let t = Float(i) / sr
                    phase += 2 * .pi * (110 + 40 * exp(-t * 20)) / sr
                    return 0.6 * sin(phase) * exp(-t * 10) + 0.08 * noise() * exp(-t * 40)
                }
            case .ride:
                var prev: Float = 0
                add(s, Int(0.4 * sampleRate)) { i in
                    let t = Float(i) / sr
                    let x = noise(); let hp = x - prev; prev = x
                    return 0.12 * hp * exp(-t * 8) + 0.05 * sin(2 * .pi * 3_300 * t) * exp(-t * 6)
                }
            case .crash:
                var prev: Float = 0
                add(s, Int(1.2 * sampleRate)) { i in
                    let t = Float(i) / sr
                    let x = noise(); let hp = x - prev; prev = x
                    return 0.3 * hp * exp(-t * 3)
                }
            }
        }
        if backing {
            // Sustained triads changing every 2 seconds (harmonic, horizontal in the spectrogram).
            let chords: [[Float]] = [[220, 277.2, 329.6], [196, 246.9, 293.7], [174.6, 220, 261.6], [196, 246.9, 293.7]]
            for i in 0..<n {
                let t = Float(i) / Float(sampleRate)
                let c = chords[Int(t / 2) % chords.count]
                var v: Float = 0
                for f in c { v += sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t) }
                out[i] += 0.06 * v
            }
        }
        let peak = out.map(abs).max() ?? 1
        if peak > 0.98 { for i in 0..<n { out[i] *= 0.98 / peak } }
        return out
    }

    /// Writes a 16-bit WAV (readable by AVAssetReader, like any user file).
    static func writeWAV(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }

    /// Creates the demo WAV in tmp (UI tests and screenshots).
    static func makeDemoFile() throws -> URL {
        let bars = 16, bpm = 112.0
        let notes = rockPattern(bars: bars, bpm: bpm)
        let duration = 0.5 + Double(bars * 4) * 60 / bpm + 1.5
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Demo Groove.wav")
        try? FileManager.default.removeItem(at: url)
        try writeWAV(render(notes, duration: duration), sampleRate: 22_050, to: url)
        return url
    }
}
