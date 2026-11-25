import SwiftUI

/// Everything the highway needs to draw one frame.
struct HighwayFrame {
    struct Note {
        var time: Double
        var lane: Int
        var judged: Judgement?
        var ghost: Bool = false
    }
    struct Burst {
        var lane: Int
        var age: Double      // seconds since the hit
        var judgement: Judgement
    }

    var now: Double
    var lookahead: Double = 2.2
    var notes: [Note]
    var beatLines: [(time: Double, downbeat: Bool)] = []
    var laneFlash: [Double] = Array(repeating: 9, count: 6)   // seconds since last pad press per lane
    var bursts: [Burst] = []
    var colors: [Color] = Palette.lanes
    var mirrored = false
    var showLabels = true
    var hitLineRatio: CGFloat = 0.80
}

struct HighwayGeometry {
    let size: CGSize
    let hitY: CGFloat
    let horizonY: CGFloat
    let nearHalf: CGFloat
    let farHalf: CGFloat
    let lanes = 6
    private let w1: CGFloat = 1 / (1 + 3.2)

    init(size: CGSize, hitLineRatio: CGFloat) {
        self.size = size
        self.hitY = size.height * hitLineRatio
        self.horizonY = size.height * 0.02
        self.nearHalf = size.width * 0.49
        self.farHalf = size.width * 0.12
    }

    /// Normalized perspective scale for depth z (0 = hit line, 1 = horizon, negative = below the line).
    func s(_ z: CGFloat) -> CGFloat {
        let w = 1 / (1 + 3.2 * max(z, -0.2))
        return (w - w1) / (1 - w1)
    }

    func y(_ z: CGFloat) -> CGFloat { horizonY + (hitY - horizonY) * s(z) }
    func halfWidth(_ z: CGFloat) -> CGFloat { farHalf + (nearHalf - farHalf) * s(z) }

    func laneEdges(_ lane: Int, z: CGFloat, mirrored: Bool) -> (CGFloat, CGFloat) {
        let l = mirrored ? lanes - 1 - lane : lane
        let hw = halfWidth(z)
        let cx = size.width / 2
        let left = cx - hw + 2 * hw * CGFloat(l) / CGFloat(lanes)
        let right = cx - hw + 2 * hw * CGFloat(l + 1) / CGFloat(lanes)
        return (left, right)
    }

    func quad(lane: Int, z0: CGFloat, z1: CGFloat, inset: CGFloat, mirrored: Bool) -> Path {
        let (a0, b0) = laneEdges(lane, z: z0, mirrored: mirrored)
        let (a1, b1) = laneEdges(lane, z: z1, mirrored: mirrored)
        let i0 = (b0 - a0) * inset, i1 = (b1 - a1) * inset
        var p = Path()
        p.move(to: CGPoint(x: a0 + i0, y: y(z0)))
        p.addLine(to: CGPoint(x: b0 - i0, y: y(z0)))
        p.addLine(to: CGPoint(x: b1 - i1, y: y(z1)))
        p.addLine(to: CGPoint(x: a1 + i1, y: y(z1)))
        p.closeSubpath()
        return p
    }

    func receptorCenter(lane: Int, mirrored: Bool) -> CGPoint {
        let (a, b) = laneEdges(lane, z: 0, mirrored: mirrored)
        return CGPoint(x: (a + b) / 2, y: hitY)
    }
}

struct HighwayCanvas: View {
    let frame: HighwayFrame

    var body: some View {
        Canvas { g, size in
            HighwayCanvas.draw(frame, in: &g, size: size)
        }
        .accessibilityHidden(true)
    }

    static func draw(_ f: HighwayFrame, in g: inout GraphicsContext, size: CGSize) {
        let geo = HighwayGeometry(size: size, hitLineRatio: f.hitLineRatio)
        let lanes = geo.lanes

        // Lane floors.
        for lane in 0..<lanes {
            let c = f.colors[lane % f.colors.count]
            let floor = geo.quad(lane: lane, z0: -0.2, z1: 1, inset: 0.02, mirrored: f.mirrored)
            g.fill(floor, with: .linearGradient(Gradient(colors: [c.opacity(0.20), c.opacity(0.02)]),
                                                startPoint: CGPoint(x: 0, y: geo.y(-0.2)), endPoint: CGPoint(x: 0, y: geo.horizonY)))
            let flash = f.laneFlash.indices.contains(lane) ? f.laneFlash[lane] : 9
            if flash < 0.18 {
                let a = 0.45 * (1 - flash / 0.18)
                let beam = geo.quad(lane: lane, z0: -0.2, z1: 0.6, inset: 0.04, mirrored: f.mirrored)
                g.fill(beam, with: .linearGradient(Gradient(colors: [c.opacity(a), c.opacity(0)]),
                                                   startPoint: CGPoint(x: 0, y: geo.hitY), endPoint: CGPoint(x: 0, y: geo.y(0.6))))
            }
        }
        // Lane separators.
        for i in 0...lanes {
            var p = Path()
            let hwN = geo.halfWidth(-0.2), hwF = geo.halfWidth(1)
            let cx = size.width / 2
            let xn = cx - hwN + 2 * hwN * CGFloat(i) / CGFloat(lanes)
            let xf = cx - hwF + 2 * hwF * CGFloat(i) / CGFloat(lanes)
            p.move(to: CGPoint(x: xn, y: geo.y(-0.2)))
            p.addLine(to: CGPoint(x: xf, y: geo.horizonY))
            g.stroke(p, with: .color(.white.opacity(i == 0 || i == lanes ? 0.22 : 0.08)), lineWidth: i == 0 || i == lanes ? 1.5 : 1)
        }

        // Beat lines.
        for line in f.beatLines {
            let z = CGFloat((line.time - f.now) / f.lookahead)
            guard z > -0.15 && z < 1 else { continue }
            var p = Path()
            let hw = geo.halfWidth(z)
            p.move(to: CGPoint(x: size.width / 2 - hw, y: geo.y(z)))
            p.addLine(to: CGPoint(x: size.width / 2 + hw, y: geo.y(z)))
            let fade = Double(1 - max(0, z))
            g.stroke(p, with: .color(.white.opacity((line.downbeat ? 0.28 : 0.10) * fade)), lineWidth: line.downbeat ? 1.6 : 1)
        }

        // Notes: glow layer then crisp layer.
        let noteLen: CGFloat = 0.045
        var visible: [(HighwayFrame.Note, CGFloat)] = []
        for n in f.notes {
            if let j = n.judged, j != .miss { continue }
            let z = CGFloat((n.time - f.now) / f.lookahead)
            guard z > -0.2 && z < 1 else { continue }
            visible.append((n, z))
        }
        g.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            for (n, z) in visible where n.judged == nil {
                let c = f.colors[n.lane % f.colors.count]
                layer.fill(geo.quad(lane: n.lane, z0: z, z1: z + noteLen, inset: 0.08, mirrored: f.mirrored),
                           with: .color(c.opacity(0.9 * Double(1 - max(0, z) * 0.7))))
            }
        }
        for (n, z) in visible {
            let c = f.colors[n.lane % f.colors.count]
            let fade = Double(1 - max(0, z) * 0.55)
            let quad = geo.quad(lane: n.lane, z0: z, z1: z + noteLen, inset: 0.08, mirrored: f.mirrored)
            if n.judged == .miss {
                g.fill(quad, with: .color(.white.opacity(0.12 * fade)))
            } else {
                g.fill(quad, with: .color(c.opacity((n.ghost ? 0.55 : 1) * fade)))
                let core = geo.quad(lane: n.lane, z0: z + noteLen * 0.35, z1: z + noteLen * 0.65, inset: 0.2, mirrored: f.mirrored)
                g.fill(core, with: .color(.white.opacity(0.75 * fade)))
            }
        }

        // Hit line.
        var line = Path()
        let hw0 = geo.halfWidth(0)
        line.move(to: CGPoint(x: size.width / 2 - hw0, y: geo.hitY))
        line.addLine(to: CGPoint(x: size.width / 2 + hw0, y: geo.hitY))
        let lineGradient = Gradient(colors: f.mirrored ? f.colors.reversed() : f.colors)
        g.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.stroke(line, with: .linearGradient(lineGradient, startPoint: CGPoint(x: size.width / 2 - hw0, y: 0),
                                                     endPoint: CGPoint(x: size.width / 2 + hw0, y: 0)), lineWidth: 8)
        }
        g.stroke(line, with: .linearGradient(lineGradient, startPoint: CGPoint(x: size.width / 2 - hw0, y: 0),
                                             endPoint: CGPoint(x: size.width / 2 + hw0, y: 0)), lineWidth: 3)

        // Receptors.
        for lane in 0..<lanes {
            let c = f.colors[lane % f.colors.count]
            let center = geo.receptorCenter(lane: lane, mirrored: f.mirrored)
            let (a, b) = geo.laneEdges(lane, z: 0, mirrored: f.mirrored)
            let w = (b - a) * 0.72
            let flash = f.laneFlash.indices.contains(lane) ? f.laneFlash[lane] : 9
            let pulse = flash < 0.15 ? 1 - flash / 0.15 : 0
            let rect = CGRect(x: center.x - w / 2, y: center.y - 9, width: w, height: 18)
            let rr = Path(roundedRect: rect, cornerRadius: 6)
            g.stroke(rr, with: .color(c.opacity(0.55 + 0.45 * pulse)), lineWidth: 2)
            if pulse > 0 { g.fill(rr, with: .color(c.opacity(0.35 * pulse))) }
        }

        // Bursts.
        for b in f.bursts where b.age < 0.45 {
            let c = f.colors[b.lane % f.colors.count]
            let center = geo.receptorCenter(lane: b.lane, mirrored: f.mirrored)
            let p = b.age / 0.45
            let radius = CGFloat(8 + 46 * p)
            let alpha = 1 - p
            g.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.45, width: radius * 2, height: radius * 0.9)),
                     with: .color(c.opacity(alpha * 0.9)), lineWidth: CGFloat(3 * (1 - p) + 0.5))
            let sparks = b.judgement == .perfect ? 12 : 8
            for k in 0..<sparks {
                let ang = Double(k) / Double(sparks) * 2 * .pi + Double(b.lane)
                let d = CGFloat(10 + 60 * p)
                let pt = CGPoint(x: center.x + CGFloat(cos(ang)) * d, y: center.y + CGFloat(sin(ang)) * d * 0.55 - CGFloat(20 * p))
                g.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(.white.opacity(alpha)))
            }
        }
    }
}

/// Decorative autoplaying highway for the home hero (respects Reduce Motion).
struct DemoHighway: View {
    var colors: [Color] = Palette.lanes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pattern: [(Double, Int)] = {
        var out: [(Double, Int)] = []
        let beat = 0.42
        for bar in 0..<4 {
            let b0 = Double(bar) * beat * 4
            for i in 0..<8 { out.append((b0 + Double(i) * beat / 2, 2)) }
            out.append((b0, 0)); out.append((b0 + beat * 2, 0)); out.append((b0 + beat * 2.5, 0))
            out.append((b0 + beat, 1)); out.append((b0 + beat * 3, 1))
            if bar == 3 {
                out.append((b0 + beat * 3.25, 3)); out.append((b0 + beat * 3.5, 3)); out.append((b0 + beat * 3.75, 3))
            }
            if bar == 0 { out.append((b0, 5)) }
            if bar == 2 { out.append((b0 + beat * 2, 4)) }
        }
        return out
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { ctx in
            HighwayCanvas(frame: DemoHighway.frame(at: ctx.date, reduceMotion: reduceMotion, colors: colors))
        }
    }

    static func frame(at date: Date, reduceMotion: Bool, colors: [Color]) -> HighwayFrame {
        let loop = 0.42 * 16
        let t = reduceMotion ? 0.8 : date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
        var notes: [HighwayFrame.Note] = []
        for rep in 0..<2 {
            for (time, lane) in pattern {
                notes.append(.init(time: time + Double(rep) * loop, lane: lane, judged: nil))
            }
        }
        var flash = Array(repeating: 9.0, count: 6)
        var bursts: [HighwayFrame.Burst] = []
        for n in notes where n.time <= t {
            let age = t - n.time
            if age < flash[n.lane] { flash[n.lane] = age }
            if age < 0.45 { bursts.append(.init(lane: n.lane, age: age, judgement: .perfect)) }
        }
        let pending = notes.filter { $0.time > t }
        let beats = (0..<34).map { (time: Double($0) * 0.42, downbeat: $0 % 4 == 0) }
        return HighwayFrame(now: t, lookahead: 1.9, notes: pending, beatLines: beats,
                            laneFlash: flash, bursts: bursts, colors: colors, hitLineRatio: 0.86)
    }
}
