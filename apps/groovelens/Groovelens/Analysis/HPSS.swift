import Accelerate
import Foundation

/// Frequency bands used for onset features (Hz).
enum Band: Int, CaseIterable {
    case sub, low, mid, high, air
    var range: ClosedRange<Double> {
        switch self {
        case .sub: return 30...120
        case .low: return 120...500
        case .mid: return 500...2_500
        case .high: return 2_500...7_000
        case .air: return 7_000...11_000
        }
    }
}

/// Per-frame features computed from the percussive spectrum.
struct PercussiveFeatures {
    let frameRate: Double
    let hopSeconds: Double
    /// [band][frame] summed power of the percussive spectrum.
    var energy: [[Float]]
    /// [band][frame] half-wave rectified log-magnitude flux.
    var flux: [[Float]]
    var frameCount: Int { energy.first?.count ?? 0 }
}

struct HPSSResult {
    var drums: [Float]
    var drumless: [Float]
    var features: PercussiveFeatures
}

/// Real FFT of size n with vDSP (packed format).
final class RealFFT {
    let n: Int
    let half: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    init(n: Int) {
        self.n = n
        self.half = n / 2
        self.log2n = vDSP_Length(log2(Double(n)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Forward transform of a real frame. Outputs half+1 bins (DC..Nyquist) into re/im.
    func forward(_ input: UnsafePointer<Float>, re: UnsafeMutablePointer<Float>, im: UnsafeMutablePointer<Float>) {
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                    vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // vDSP scales forward by 2.
                re[0] = rp[0] * 0.5
                im[0] = 0
                re[half] = ip[0] * 0.5
                im[half] = 0
                for k in 1..<half {
                    re[k] = rp[k] * 0.5
                    im[k] = ip[k] * 0.5
                }
            }
        }
    }

    /// Inverse transform from half+1 bins to a real frame of n samples (unnormalized → divided by n).
    func inverse(re: UnsafePointer<Float>, im: UnsafePointer<Float>, output: UnsafeMutablePointer<Float>) {
        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        realp[0] = re[0]
        imagp[0] = re[half]
        for k in 1..<half {
            realp[k] = re[k]
            imagp[k] = im[k]
        }
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                output.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                    vDSP_ztoc(&split, 1, cp, 2, vDSP_Length(half))
                }
            }
        }
        var scale = 1 / Float(n)
        vDSP_vsmul(output, 1, &scale, output, 1, vDSP_Length(n))
    }
}

/// Harmonic/percussive source separation by median filtering (Fitzgerald 2010),
/// processed in bounded-memory blocks. Also emits the percussive onset features.
enum HPSS {
    static let fftSize = 2048
    static let hop = 512
    static let timeKernel = 13   // frames (≈300 ms) — smooths across time → harmonic
    static let freqKernel = 13   // bins (≈140 Hz) — smooths across frequency → percussive

    static func separate(_ signal: [Float], sampleRate: Double, progress: (Double) -> Void) throws -> HPSSResult {
        let n = fftSize, hop = hop
        let bins = n / 2 + 1
        let pad = n / 2
        // Centered frames: pad both ends.
        var x = [Float](repeating: 0, count: pad)
        x.append(contentsOf: signal)
        x.append(contentsOf: [Float](repeating: 0, count: n + pad))
        let frameCount = max(1, (x.count - n) / hop + 1)

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        // Hann analysis + Hann synthesis at 75 % overlap sums to 1.5.
        let olaGain: Float = 1 / 1.5

        let fft = RealFFT(n: n)
        var drums = [Float](repeating: 0, count: x.count)
        var drumless = [Float](repeating: 0, count: x.count)

        let bandBins: [Range<Int>] = Band.allCases.map { b in
            let lo = Int((b.range.lowerBound * Double(n) / sampleRate).rounded())
            let hi = min(bins, Int((b.range.upperBound * Double(n) / sampleRate).rounded()) + 1)
            return max(1, lo)..<max(lo + 1, hi)
        }
        var energy = Array(repeating: [Float](repeating: 0, count: frameCount), count: Band.allCases.count)
        var flux = Array(repeating: [Float](repeating: 0, count: frameCount), count: Band.allCases.count)
        var prevLog = [Float](repeating: 0, count: bins)

        let block = 384
        let margin = timeKernel / 2
        let halfF = freqKernel / 2

        var frameBuf = [Float](repeating: 0, count: n)
        var outBuf = [Float](repeating: 0, count: n)
        var scratch = [Float](repeating: 0, count: max(timeKernel, freqKernel))

        var b0 = 0
        while b0 < frameCount {
            try Task.checkCancellation()
            let b1 = min(frameCount, b0 + block)
            let s0 = max(0, b0 - margin), s1 = min(frameCount, b1 + margin)
            let span = s1 - s0
            var re = [Float](repeating: 0, count: span * bins)
            var im = [Float](repeating: 0, count: span * bins)
            var mag = [Float](repeating: 0, count: span * bins)

            for f in s0..<s1 {
                let offset = f * hop
                for i in 0..<n { frameBuf[i] = x[offset + i] * window[i] }
                let row = (f - s0) * bins
                re.withUnsafeMutableBufferPointer { rp in
                    im.withUnsafeMutableBufferPointer { ip in
                        frameBuf.withUnsafeBufferPointer { fp in
                            fft.forward(fp.baseAddress!, re: rp.baseAddress! + row, im: ip.baseAddress! + row)
                        }
                    }
                }
                for k in 0..<bins {
                    let r = re[row + k], i = im[row + k]
                    mag[row + k] = (r * r + i * i).squareRoot()
                }
            }

            var pRe = [Float](repeating: 0, count: bins)
            var pIm = [Float](repeating: 0, count: bins)
            var hRe = [Float](repeating: 0, count: bins)
            var hIm = [Float](repeating: 0, count: bins)

            for f in b0..<b1 {
                let row = (f - s0) * bins
                for k in 0..<bins {
                    // Harmonic: median over time.
                    var c = 0
                    let t0 = max(s0, f - margin), t1 = min(s1 - 1, f + margin)
                    for t in t0...t1 { scratch[c] = mag[(t - s0) * bins + k]; c += 1 }
                    let h = median(&scratch, count: c)
                    // Percussive: median over frequency.
                    c = 0
                    let k0 = max(0, k - halfF), k1 = min(bins - 1, k + halfF)
                    for kk in k0...k1 { scratch[c] = mag[row + kk]; c += 1 }
                    let p = median(&scratch, count: c)
                    let h2 = h * h, p2 = p * p
                    let mp = p2 / (h2 + p2 + 1e-12)
                    pRe[k] = re[row + k] * mp
                    pIm[k] = im[row + k] * mp
                    hRe[k] = re[row + k] * (1 - mp)
                    hIm[k] = im[row + k] * (1 - mp)

                    // Features on the percussive magnitude.
                    let pm = mag[row + k] * mp
                    let lg = log1pf(pm * 100)
                    let d = lg - prevLog[k]
                    prevLog[k] = lg
                    for (bi, r) in bandBins.enumerated() where r.contains(k) {
                        energy[bi][f] += pm * pm
                        if d > 0 { flux[bi][f] += d }
                    }
                }

                let offset = f * hop
                pRe.withUnsafeBufferPointer { rp in
                    pIm.withUnsafeBufferPointer { ip in
                        outBuf.withUnsafeMutableBufferPointer { op in
                            fft.inverse(re: rp.baseAddress!, im: ip.baseAddress!, output: op.baseAddress!)
                        }
                    }
                }
                for i in 0..<n { drums[offset + i] += outBuf[i] * window[i] * olaGain }
                hRe.withUnsafeBufferPointer { rp in
                    hIm.withUnsafeBufferPointer { ip in
                        outBuf.withUnsafeMutableBufferPointer { op in
                            fft.inverse(re: rp.baseAddress!, im: ip.baseAddress!, output: op.baseAddress!)
                        }
                    }
                }
                for i in 0..<n { drumless[offset + i] += outBuf[i] * window[i] * olaGain }
            }
            progress(Double(b1) / Double(frameCount))
            try Task.checkCancellation()
            b0 = b1
        }

        // Normalize flux by band width so bands are comparable.
        for (bi, r) in bandBins.enumerated() {
            let w = Float(max(1, r.count))
            for f in 0..<frameCount { flux[bi][f] /= w; energy[bi][f] /= w }
        }

        let trimmedDrums = Array(drums[pad..<min(drums.count, pad + signal.count)])
        let trimmedDrumless = Array(drumless[pad..<min(drumless.count, pad + signal.count)])
        let features = PercussiveFeatures(frameRate: sampleRate / Double(hop), hopSeconds: Double(hop) / sampleRate, energy: energy, flux: flux)
        return HPSSResult(drums: normalized(trimmedDrums), drumless: normalized(trimmedDrumless), features: features)
    }

    /// In-place partial selection median for tiny windows.
    @inline(__always)
    static func median(_ a: inout [Float], count: Int) -> Float {
        // Insertion sort on the first `count` items.
        if count <= 1 { return count == 1 ? a[0] : 0 }
        for i in 1..<count {
            let v = a[i]
            var j = i - 1
            while j >= 0 && a[j] > v { a[j + 1] = a[j]; j -= 1 }
            a[j + 1] = v
        }
        return a[count / 2]
    }

    static func normalized(_ s: [Float]) -> [Float] {
        var peak: Float = 0
        vDSP_maxmgv(s, 1, &peak, vDSP_Length(s.count))
        guard peak > 1e-6 else { return s }
        var scale = min(1 / peak * 0.89, 8)
        var out = [Float](repeating: 0, count: s.count)
        vDSP_vsmul(s, 1, &scale, &out, 1, vDSP_Length(s.count))
        return out
    }
}
