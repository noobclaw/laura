import Foundation

/// A raw detected stroke before beat-grid quantization.
struct RawHit {
    var time: Double
    var piece: DrumPiece
    var velocity: Float
    var isOpen: Bool
}

/// Converts percussive features into drum strokes (classical DSP v1).
/// The protocol lets a Core ML transcriber replace this later without touching the rest.
protocol DrumTranscriber {
    func transcribe(_ features: PercussiveFeatures) -> [RawHit]
}

struct SpectralDrumTranscriber: DrumTranscriber {
    func transcribe(_ features: PercussiveFeatures) -> [RawHit] {
        let F = features.frameCount
        guard F > 8 else { return [] }
        let fr = features.frameRate
        let bands = Band.allCases.count

        // Normalize flux and energy per band by a robust peak (95th percentile).
        var fluxN = features.flux
        var energyN = features.energy
        for b in 0..<bands {
            let pf = max(percentile(fluxN[b], 0.97), 1e-6)
            let pe = max(percentile(energyN[b], 0.97), 1e-9)
            for f in 0..<F { fluxN[b][f] /= pf; energyN[b][f] /= pe }
        }

        // Peaks per band.
        let minGaps = [4, 3, 3, 3, 3]
        var peaks: [(frame: Int, band: Int, value: Float)] = []
        for b in 0..<bands {
            peaks.append(contentsOf: pickPeaks(fluxN[b], minGap: minGaps[b], delta: 0.10).map { ($0.0, b, $0.1) })
        }
        peaks.sort { $0.frame < $1.frame }

        // Cluster peaks across bands into events (±2 frames ≈ 46 ms).
        var events: [[(frame: Int, band: Int, value: Float)]] = []
        for p in peaks {
            if var last = events.last, let first = last.first, p.frame - first.frame <= 2 {
                last.append(p)
                events[events.count - 1] = last
            } else {
                events.append([p])
            }
        }

        let d6 = max(1, Int((0.15 * fr).rounded()))
        let d17 = max(2, Int((0.40 * fr).rounded()))
        var hits: [RawHit] = []

        for ev in events {
            let f = ev.map(\.frame).min() ?? 0
            var fx = [Float](repeating: 0, count: bands)
            for p in ev { fx[p.band] = max(fx[p.band], p.value) }
            func attack(_ b: Int) -> Float {
                var m: Float = 0
                for i in f...min(F - 1, f + 2) { m = max(m, energyN[b][i]) }
                return m
            }
            func decay(_ b: Int, _ d: Int) -> Float {
                let a = attack(b)
                guard a > 1e-6 else { return 0 }
                return energyN[b][min(F - 1, f + d)] / a
            }
            let eSub = attack(Band.sub.rawValue), eLow = attack(Band.low.rawValue)
            let eHigh = attack(Band.high.rawValue), eAir = attack(Band.air.rawValue)
            let time = Double(f) / fr
            var produced: Set<DrumPiece> = []

            // Kick: sub-band onset that dominates the low end.
            let subShare = eSub / max(eSub + eLow, 1e-6)
            if fx[Band.sub.rawValue] > 0.22 && eSub > 0.10 && subShare > 0.42 {
                hits.append(RawHit(time: time, piece: .kick, velocity: clampVel(fx[Band.sub.rawValue]), isOpen: false))
                produced.insert(.kick)
            }

            // Snare: broadband noise burst with a body, short decay.
            let body = max(fx[Band.low.rawValue], fx[Band.mid.rawValue])
            let highDecay = decay(Band.high.rawValue, d6)
            if fx[Band.high.rawValue] > 0.20 && body > 0.14 && highDecay < 0.5 {
                hits.append(RawHit(time: time, piece: .snare, velocity: clampVel(fx[Band.high.rawValue]), isOpen: false))
                produced.insert(.snare)
            } else if fx[Band.low.rawValue] > 0.30 && eHigh < 0.35 * max(eLow, 1e-6) && !produced.contains(.kick) {
                // Tom: pitched low-mid onset without much noise.
                hits.append(RawHit(time: time, piece: .tom, velocity: clampVel(fx[Band.low.rawValue]), isOpen: false))
                produced.insert(.tom)
            }

            // Cymbals and hi-hat from the air band.
            let airFlux = fx[Band.air.rawValue]
            let snareMasksAir = produced.contains(.snare) && airFlux < fx[Band.high.rawValue] * 1.2
            if airFlux > 0.18 && !snareMasksAir {
                let a6 = decay(Band.air.rawValue, d6)
                let a17 = decay(Band.air.rawValue, d17)
                if eAir > 0.55 && a17 > 0.33 {
                    hits.append(RawHit(time: time, piece: .crash, velocity: clampVel(airFlux), isOpen: false))
                } else if a6 > 0.5 {
                    if eHigh > eAir * 0.8 && a17 > 0.28 {
                        hits.append(RawHit(time: time, piece: .ride, velocity: clampVel(airFlux), isOpen: false))
                    } else {
                        hits.append(RawHit(time: time, piece: .hihat, velocity: clampVel(airFlux), isOpen: true))
                    }
                } else {
                    hits.append(RawHit(time: time, piece: .hihat, velocity: clampVel(airFlux), isOpen: false))
                }
            }
        }
        return hits
    }

    private func clampVel(_ v: Float) -> Float { min(1, max(0.05, v * 0.85)) }
}

// MARK: - Shared signal helpers

func percentile(_ a: [Float], _ q: Double) -> Float {
    guard !a.isEmpty else { return 0 }
    let s = a.sorted()
    let i = min(s.count - 1, max(0, Int(Double(s.count - 1) * q)))
    return s[i]
}

/// Adaptive-threshold peak picking on a normalized novelty curve.
func pickPeaks(_ x: [Float], minGap: Int, delta: Float, window: Int = 8) -> [(Int, Float)] {
    let n = x.count
    guard n > 4 else { return [] }
    // Running mean via prefix sums.
    var prefix = [Float](repeating: 0, count: n + 1)
    for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
    var out: [(Int, Float)] = []
    var last = -minGap - 1
    for i in 2..<(n - 2) {
        let v = x[i]
        guard v >= x[i - 1], v >= x[i + 1], v >= x[i - 2], v >= x[i + 2] else { continue }
        let a = max(0, i - window), b = min(n, i + window + 1)
        let mean = (prefix[b] - prefix[a]) / Float(b - a)
        guard v > mean + delta else { continue }
        if i - last >= minGap {
            out.append((i, v))
            last = i
        } else if let l = out.last, v > l.1 {
            out[out.count - 1] = (i, v)
            last = i
        }
    }
    return out
}

// MARK: - Beat tracking (Ellis 2007 dynamic programming)

struct BeatGrid {
    var beatTimes: [Double]
    var tempo: Double
}

enum BeatTracker {
    static func onsetEnvelope(_ features: PercussiveFeatures) -> [Float] {
        let F = features.frameCount
        let weights: [Float] = [1.0, 0.8, 0.6, 1.0, 0.6]
        var env = [Float](repeating: 0, count: F)
        for b in 0..<Band.allCases.count {
            let p = max(percentile(features.flux[b], 0.97), 1e-6)
            for f in 0..<F { env[f] += weights[b] * features.flux[b][f] / p }
        }
        return env
    }

    static func estimateTempo(_ env: [Float], frameRate fr: Double) -> Double {
        let n = env.count
        let mean = env.reduce(0, +) / Float(max(n, 1))
        let x = env.map { $0 - mean }
        let minLag = Int(fr * 60 / 200), maxLag = min(n - 1, Int(fr * 60 / 50))
        guard maxLag > minLag + 2 else { return 120 }
        let prior = fr * 60 / 115
        var best = minLag
        var bestScore = -Double.infinity
        var scores = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...maxLag {
            var s: Float = 0
            var i = 0
            while i + lag < n { s += x[i] * x[i + lag]; i += 1 }
            let w = exp(-0.5 * pow(log2(Double(lag) / prior) / 0.9, 2))
            let score = Double(s) / Double(n - lag) * w
            scores[lag] = score
            if score > bestScore { bestScore = score; best = lag }
        }
        // Parabolic refinement.
        var lag = Double(best)
        if best > minLag && best < maxLag {
            let a = scores[best - 1], b = scores[best], c = scores[best + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { lag += 0.5 * (a - c) / denom }
        }
        var bpm = 60 * fr / lag
        while bpm < 70 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return bpm
    }

    static func track(_ features: PercussiveFeatures, duration: Double, tightness: Double = 100) -> BeatGrid {
        let fr = features.frameRate
        var env = onsetEnvelope(features)
        let n = env.count
        let bpm = estimateTempo(env, frameRate: fr)
        guard n > 8 else { return BeatGrid(beatTimes: stride(from: 0, to: duration, by: 60 / bpm).map { $0 }, tempo: bpm) }

        // Standardize.
        let mean = env.reduce(0, +) / Float(n)
        var varSum: Float = 0
        for v in env { varSum += (v - mean) * (v - mean) }
        let sd = max((varSum / Float(n)).squareRoot(), 1e-6)
        env = env.map { ($0 - mean) / sd }

        let period = fr * 60 / bpm
        var score = [Double](repeating: 0, count: n)
        var back = [Int](repeating: -1, count: n)
        let lo = Int((period * 0.5).rounded()), hi = Int((period * 2).rounded())
        for t in 0..<n {
            var bestPrev = -1
            var bestVal = -Double.infinity
            if t - lo >= 0 {
                for prev in max(0, t - hi)...(t - lo) {
                    let r = Double(t - prev) / period
                    let v = score[prev] - tightness * pow(log(r), 2)
                    if v > bestVal { bestVal = v; bestPrev = prev }
                }
            }
            let local = Double(env[t])
            if bestPrev >= 0 && bestVal > 0 {
                score[t] = local + bestVal
                back[t] = bestPrev
            } else {
                score[t] = local
            }
        }
        // Best final beat inside the last period.
        let tailStart = max(0, n - Int(period.rounded()) - 1)
        var last = tailStart
        for t in tailStart..<n where score[t] > score[last] { last = t }
        var frames: [Int] = []
        var cur = last
        while cur >= 0 {
            frames.append(cur)
            cur = back[cur]
        }
        frames.reverse()
        var times = frames.map { Double($0) / fr }
        if times.count < 2 {
            times = stride(from: 0, to: duration, by: 60 / bpm).map { $0 }
        }
        // Extend the grid to cover the whole song.
        let p0 = times.count >= 2 ? times[1] - times[0] : 60 / bpm
        while let first = times.first, first - p0 >= 0 {
            times.insert(first - p0, at: 0)
        }
        let n2 = times.count
        let p1 = n2 >= 2 ? times[n2 - 1] - times[n2 - 2] : 60 / bpm
        while let lastT = times.last, lastT + p1 < duration + p1 {
            times.append(lastT + p1)
        }
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }.sorted()
        let medianInterval = intervals.isEmpty ? 60 / bpm : intervals[intervals.count / 2]
        return BeatGrid(beatTimes: times, tempo: 60 / medianInterval)
    }
}

// MARK: - Meter, quantization, sections

enum ChartBuilder {
    static func build(raw: [RawHit], grid: BeatGrid, duration: Double) -> DrumChart {
        let beats = grid.beatTimes
        let (beatsPerBar, phase) = detectMeter(raw: raw, beats: beats)

        var chart = DrumChart(duration: duration, beatTimes: beats, beatsPerBar: beatsPerBar, downbeatOffset: phase,
                              tempo: grid.tempo, swing: 0.5, hits: [], sections: [], fillBars: [])
        chart.swing = detectSwing(raw: raw, beats: beats)
        chart.hits = quantize(raw: raw, chart: chart)
        chart.fillBars = detectFills(chart)
        chart.sections = detectSections(chart)
        return chart
    }

    static func beatIndex(for t: Double, beats: [Double]) -> Int {
        var lo = 0, hi = beats.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if beats[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    static func strength(of piece: DrumPiece, near t: Double, in raw: [RawHit], tolerance: Double = 0.07) -> Float {
        var m: Float = 0
        for h in raw where h.piece == piece && abs(h.time - t) <= tolerance { m = max(m, h.velocity) }
        return m
    }

    static func detectMeter(raw: [RawHit], beats: [Double]) -> (Int, Int) {
        guard beats.count >= 12 else { return (4, 0) }
        let kicks = beats.map { strength(of: .kick, near: $0, in: raw) }
        let snares = beats.map { strength(of: .snare, near: $0, in: raw) }
        func score(bpb: Int, phase: Int) -> Float {
            var on: Float = 0, off: Float = 0, onN: Float = 0, offN: Float = 0
            var back: Float = 0, backN: Float = 0
            for (i, k) in kicks.enumerated() {
                let pos = ((i - phase) % bpb + bpb) % bpb
                if pos == 0 { on += k; onN += 1 } else { off += k; offN += 1 }
                if bpb == 4 && (pos == 1 || pos == 3) { back += snares[i]; backN += 1 }
                if bpb == 3 && (pos == 1 || pos == 2) { back += snares[i] * 0.5; backN += 1 }
            }
            let kickContrast = on / max(onN, 1) - off / max(offN, 1)
            return kickContrast + 0.6 * back / max(backN, 1)
        }
        var best4 = (score: -Float.infinity, phase: 0)
        for p in 0..<4 { let s = score(bpb: 4, phase: p); if s > best4.score { best4 = (s, p) } }
        var best3 = (score: -Float.infinity, phase: 0)
        for p in 0..<3 { let s = score(bpb: 3, phase: p); if s > best3.score { best3 = (s, p) } }
        if best3.score > best4.score * 1.3 && best3.score > 0.1 { return (3, best3.phase) }
        return (4, best4.phase)
    }

    static func detectSwing(raw: [RawHit], beats: [Double]) -> Double {
        var fracs: [Double] = []
        for h in raw where h.piece == .hihat || h.piece == .ride {
            let i = beatIndex(for: h.time, beats: beats)
            guard i + 1 < beats.count else { continue }
            let f = (h.time - beats[i]) / (beats[i + 1] - beats[i])
            if f > 0.4 && f < 0.8 { fracs.append(f) }
        }
        guard fracs.count >= 16 else { return 0.5 }
        fracs.sort()
        let m = fracs[fracs.count / 2]
        return m > 0.58 ? m : 0.5
    }

    static func quantize(raw: [RawHit], chart: DrumChart) -> [DrumHit] {
        let beats = chart.beatTimes
        let tpb = DrumChart.ticksPerBeat
        let straight = [0, 3, 6, 9, 12]
        let triplet = [0, 4, 8, 12]
        // Group by beat to choose straight vs triplet per beat.
        var byBeat: [Int: [RawHit]] = [:]
        for h in raw { byBeat[beatIndex(for: h.time, beats: beats), default: []].append(h) }

        var seen = Set<String>()
        var out: [DrumHit] = []
        for (bi, group) in byBeat {
            guard bi + 1 < beats.count else { continue }
            let span = beats[bi + 1] - beats[bi]
            let fracs = group.map { ($0.time - beats[bi]) / span * Double(tpb) }
            func err(_ grid: [Int]) -> Double {
                fracs.reduce(0) { acc, f in acc + (grid.map { abs(Double($0) - f) }.min() ?? 0) }
            }
            let useTriplet = err(triplet) < err(straight) * 0.75 && chart.swing <= 0.58
            for (h, f) in zip(group, fracs) {
                var tick: Int
                if chart.swing > 0.58 {
                    // Swung 8ths are written straight: the late off-beat maps to tick 6.
                    let swingPos = chart.swing * Double(tpb)
                    let candidates: [(pos: Double, tick: Int)] = [(0, 0), (swingPos, 6), (Double(tpb), tpb)]
                    tick = candidates.min { abs($0.pos - f) < abs($1.pos - f) }?.tick ?? 0
                } else {
                    let grid = useTriplet ? triplet : straight
                    tick = grid.min { abs(Double($0) - f) < abs(Double($1) - f) } ?? 0
                }
                var beat = bi
                if tick >= tpb { tick -= tpb; beat += 1 }
                let rel = beat - chart.downbeatOffset
                guard rel >= 0 else { continue }
                let bar = rel / chart.beatsPerBar
                let barTick = (rel % chart.beatsPerBar) * tpb + tick
                let key = "\(h.piece.rawValue)-\(bar)-\(barTick)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let ghost = h.piece == .snare && h.velocity < 0.28
                out.append(DrumHit(time: chart.time(bar: bar, tick: barTick), piece: h.piece, velocity: h.velocity,
                                   isOpen: h.isOpen, isGhost: ghost, bar: bar, tick: barTick))
            }
        }
        return out.sorted { $0.time == $1.time ? $0.piece.lane < $1.piece.lane : $0.time < $1.time }
    }

    static func barVector(_ chart: DrumChart, bar: Int) -> [Float] {
        var v = [Float](repeating: 0, count: 16 * DrumPiece.allCases.count)
        for h in chart.hits where h.bar == bar {
            let cell = min(15, h.tick * 16 / max(chart.ticksPerBar, 1))
            v[cell * DrumPiece.allCases.count + h.piece.lane] = 1
        }
        return v
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        guard na > 0, nb > 0 else { return na == nb ? 1 : 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    static func detectFills(_ chart: DrumChart) -> [Int] {
        let bars = chart.barCount
        guard bars >= 4 else { return [] }
        var density = [Int](repeating: 0, count: bars)
        var toms = [Int](repeating: 0, count: bars)
        for h in chart.hits where h.bar < bars {
            if h.piece == .snare || h.piece == .tom { density[h.bar] += 1 }
            if h.piece == .tom { toms[h.bar] += 1 }
        }
        let sortedD = density.sorted()
        let med = max(1, sortedD[sortedD.count / 2])
        var fills: [Int] = []
        for b in 1..<bars {
            let sim = cosine(barVector(chart, bar: b), barVector(chart, bar: b - 1))
            let busy = Double(density[b]) > Double(med) * 1.6 || toms[b] >= 3
            if busy && sim < 0.6 { fills.append(b) }
        }
        return fills
    }

    static func detectSections(_ chart: DrumChart) -> [ChartSection] {
        let bars = chart.barCount
        guard bars > 0 else { return [] }
        let fills = Set(chart.fillBars)
        let vectors = (0..<bars).map { barVector(chart, bar: $0) }

        // Greedy clustering of grooves.
        var centroids: [[Float]] = []
        var counts: [Int] = []
        var labels = [Int](repeating: -1, count: bars)
        for b in 0..<bars where !fills.contains(b) {
            let v = vectors[b]
            if v.allSatisfy({ $0 == 0 }) { continue }
            var best = -1
            var bestSim: Float = 0.72
            for (ci, c) in centroids.enumerated() {
                let s = cosine(v, c)
                if s > bestSim { bestSim = s; best = ci }
            }
            if best < 0 {
                centroids.append(v); counts.append(1); labels[b] = centroids.count - 1
            } else {
                let k = Float(counts[best])
                centroids[best] = zip(centroids[best], v).map { ($0 * k + $1) / (k + 1) }
                counts[best] += 1
                labels[b] = best
            }
        }
        // Fill gaps (fills / empty bars) with the previous label.
        var lastLabel = labels.first { $0 >= 0 } ?? 0
        for b in 0..<bars {
            if labels[b] < 0 { labels[b] = lastLabel } else { lastLabel = labels[b] }
        }
        // Smooth: majority over 4-bar windows aligned to phrases.
        var phraseLabels: [Int] = []
        var b = 0
        while b < bars {
            let window = labels[b..<min(bars, b + 4)]
            var freq: [Int: Int] = [:]
            for l in window { freq[l, default: 0] += 1 }
            let maj = freq.max { $0.value < $1.value }?.key ?? 0
            phraseLabels.append(maj)
            b += 4
        }
        // Runs.
        var runs: [(label: Int, start: Int, end: Int)] = []
        for (i, l) in phraseLabels.enumerated() {
            let s = i * 4, e = min(bars, s + 4)
            if let last = runs.last, last.label == l {
                runs[runs.count - 1].end = e
            } else {
                runs.append((l, s, e))
            }
        }
        // Name clusters.
        let barsPerCluster = Dictionary(grouping: runs, by: { $0.label }).mapValues { $0.reduce(0) { $0 + ($1.end - $1.start) } }
        let verseCluster = barsPerCluster.max { $0.value < $1.value }?.key ?? 0
        func cymbalEnergy(_ label: Int) -> Float {
            guard label < centroids.count else { return 0 }
            let c = centroids[label]
            var s: Float = 0
            for cell in 0..<16 {
                s += c[cell * 6 + DrumPiece.ride.lane] + 2 * c[cell * 6 + DrumPiece.crash.lane]
            }
            return s
        }
        let others = barsPerCluster.keys.filter { $0 != verseCluster }
        let chorusCluster = others.max { cymbalEnergy($0) < cymbalEnergy($1) }

        let totalHits = Float(max(chart.hits.count, 1))
        let avgPerBar = totalHits / Float(bars)
        func density(_ s: Int, _ e: Int) -> Float {
            Float(chart.hits.filter { $0.bar >= s && $0.bar < e }.count) / Float(max(e - s, 1))
        }

        var ordinals: [SectionKind: Int] = [:]
        var sections: [ChartSection] = []
        for (i, r) in runs.enumerated() {
            var kind: SectionKind
            if runs.count == 1 {
                kind = .part
            } else if r.label == verseCluster {
                kind = .verse
            } else if r.label == chorusCluster {
                kind = .chorus
            } else {
                kind = .bridge
            }
            let sparse = density(r.start, r.end) < avgPerBar * 0.5
            if i == 0 && sparse && runs.count > 1 { kind = .intro }
            if i == runs.count - 1 && sparse && runs.count > 2 { kind = .outro }
            ordinals[kind, default: 0] += 1
            sections.append(ChartSection(kind: kind, ordinal: ordinals[kind]!, startBar: r.start, endBar: r.end))
        }
        // Single-groove songs: split into 8-bar parts so looping still works.
        if sections.count == 1 && bars > 8 {
            sections = stride(from: 0, to: bars, by: 8).enumerated().map { i, s in
                ChartSection(kind: .part, ordinal: i + 1, startBar: s, endBar: min(bars, s + 8))
            }
        }
        return sections
    }
}
