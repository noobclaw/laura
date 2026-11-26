import SwiftUI
import CoreMotion

/// Shared device tilt, smoothed, for liquid that stays level while the phone moves.
@MainActor
@Observable
final class TiltSensor {
    static let shared = TiltSensor()

    /// Clockwise rotation (radians, canvas convention) that keeps a liquid surface level with the world.
    private(set) var angle: Double = 0
    /// How fast the tilt is changing; makes the surface slosh.
    private(set) var agitation: Double = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // Device rotated counter-clockwise by θ ⇒ gravity = (−sin θ, −cos θ); the surface turns clockwise by θ on screen.
            let target = max(-0.55, min(0.55, atan2(-g.x, -g.y)))
            let next = self.angle + (target - self.angle) * 0.18
            self.agitation = min(1, self.agitation * 0.92 + abs(next - self.angle) * 6)
            self.angle = next
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

/// Draws stacked liquid (base at the bottom) into `body`, level with the world, with a moving surface.
enum LiquidRenderer {
    /// `layers`: (colour, share) bottom-first. `fill` 0…1 of the body's height.
    static func draw(in ctx: inout GraphicsContext, body: Path, layers: [(Color, Double)], fill: Double,
                     angle: Double, time: Double, agitation: Double, shimmer: Bool) {
        let rect = body.boundingRect
        let total = max(layers.reduce(0) { $0 + $1.1 }, 0.0001)
        let liquidH = rect.height * min(max(fill, 0), 1)
        guard liquidH > 0.5 else { return }
        let level = rect.maxY - liquidH
        let span = rect.width * 3

        ctx.drawLayer { layer in
            layer.clip(to: body)
            layer.translateBy(x: rect.midX, y: level)
            layer.rotate(by: .radians(angle))

            // Surface wave: gentle at rest, bigger while the phone moves.
            let amp = 1.2 + agitation * 5
            func surface(_ x: CGFloat) -> CGFloat {
                amp * sin(Double(x) / 18 + time * 2.4) * 0.6 + amp * sin(Double(x) / 7 - time * 3.1) * 0.4
            }

            // Layers top-down from the surface; the base runs off the bottom (clipped).
            var y: CGFloat = 0
            let ordered = Array(layers.reversed())
            for (i, item) in ordered.enumerated() {
                let h = i == ordered.count - 1 ? rect.height * 3 : liquidH * item.1 / total
                var p = Path()
                let steps = 40
                for s in 0...steps {
                    let x = -span / 2 + span * CGFloat(s) / CGFloat(steps)
                    let yy = y + (i == 0 ? surface(x) : surface(x) * 0.25)
                    if s == 0 { p.move(to: CGPoint(x: x, y: yy)) } else { p.addLine(to: CGPoint(x: x, y: yy)) }
                }
                p.addLine(to: CGPoint(x: span / 2, y: y + h + 2))
                p.addLine(to: CGPoint(x: -span / 2, y: y + h + 2))
                p.closeSubpath()
                layer.fill(p, with: .color(item.0))
                y += h
            }
            // Meniscus highlight.
            var m = Path()
            for s in 0...40 {
                let x = -span / 2 + span * CGFloat(s) / 40
                let pt = CGPoint(x: x, y: surface(x))
                if s == 0 { m.move(to: pt) } else { m.addLine(to: pt) }
            }
            layer.stroke(m, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
        }

        if shimmer {
            // A band of light sweeps across the glass every few seconds.
            let period = 4.5
            let phase = (time.truncatingRemainder(dividingBy: period)) / period
            let x = rect.minX - rect.width * 0.6 + rect.width * 2.2 * phase
            ctx.drawLayer { layer in
                layer.clip(to: body)
                var band = Path()
                band.move(to: CGPoint(x: x, y: rect.minY))
                band.addLine(to: CGPoint(x: x + rect.width * 0.22, y: rect.minY))
                band.addLine(to: CGPoint(x: x - rect.width * 0.18, y: rect.maxY))
                band.addLine(to: CGPoint(x: x - rect.width * 0.40, y: rect.maxY))
                band.closeSubpath()
                layer.fill(band, with: .color(.white.opacity(Theme.isNoir ? 0.20 : 0.28)))
            }
        }
    }
}

/// A short burst of perfume mist from a nozzle: particles drift up and outward, tinted by the layers.
struct MistBurst: View {
    let start: Date
    let colors: [Color]
    var duration: Double = 1.5

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t >= 0, t < duration, !colors.isEmpty else { return }
                let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.85)
                var rng = SeededRandom(seed: UInt64(start.timeIntervalSince1970 * 10) & 0xFFFF)
                for i in 0..<70 {
                    let delay = Double(rng.next() % 300) / 1000
                    let life = t - delay
                    guard life > 0 else { continue }
                    let p = life / (duration - 0.3)
                    guard p < 1 else { continue }
                    let ang = (-100.0 + Double(Int(rng.next() % 80) - 40)) * .pi / 180
                    let speed = 35 + Double(rng.next() % 80)
                    let ease = 1 - pow(1 - p, 2.2)
                    let x = origin.x + CGFloat(cos(ang) * speed * ease)
                    let y = origin.y + CGFloat(sin(ang) * speed * ease) - CGFloat(p * 10)
                    let r = CGFloat(1.2 + Double(rng.next() % 30) / 10) * CGFloat(1 + p * 1.6)
                    let color = colors[i % colors.count]
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity((1 - p) * 0.75)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A lab beaker that fills layer by layer while weighing; the next target is a dashed line.
struct BeakerView: View {
    /// Weighed so far, bottom first.
    let layers: [(Color, Double)]
    /// Grams of the step being weighed now.
    let pending: Double
    let pendingColor: Color
    let capacity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltSensor.shared
    @State private var from: Double = 0
    @State private var to: Double = 0
    @State private var changed = Date.distantPast

    private var target: Double {
        guard capacity > 0 else { return 0 }
        return min(1, layers.reduce(0) { $0 + $1.1 } / capacity)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
            let now = tl.date
            let p = min(1, now.timeIntervalSince(changed) / 0.7)
            let eased = 1 - pow(1 - p, 3)
            let fill = reduceMotion ? to : from + (to - from) * eased
            Canvas { ctx, size in
                let r = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let lip = r.height * 0.06
                var body = Path()
                body.move(to: CGPoint(x: r.minX, y: r.minY + lip))
                body.addLine(to: CGPoint(x: r.minX, y: r.maxY - 12))
                body.addQuadCurve(to: CGPoint(x: r.minX + 12, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
                body.addLine(to: CGPoint(x: r.maxX - 12, y: r.maxY))
                body.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - 12), control: CGPoint(x: r.maxX, y: r.maxY))
                body.addLine(to: CGPoint(x: r.maxX, y: r.minY + lip))
                body.closeSubpath()
                ctx.fill(body, with: .color(Theme.isNoir ? Color.white.opacity(0.05) : Theme.card))
                var c = ctx
                LiquidRenderer.draw(in: &c, body: body, layers: layers.isEmpty ? [(pendingColor, 1)] : layers,
                                    fill: layers.isEmpty ? 0 : fill, angle: reduceMotion ? 0 : tilt.angle,
                                    time: now.timeIntervalSinceReferenceDate, agitation: tilt.agitation, shimmer: false)
                // Target line for the current step.
                if capacity > 0, pending > 0 {
                    let level = min(1, (layers.reduce(0) { $0 + $1.1 } + pending) / capacity)
                    let y = r.maxY - (r.height - lip) * level
                    var line = Path(); line.move(to: CGPoint(x: r.minX + 4, y: y)); line.addLine(to: CGPoint(x: r.maxX - 4, y: y))
                    ctx.stroke(line, with: .color(pendingColor), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                // Graduations.
                for i in 1..<5 {
                    let y = r.maxY - (r.height - lip) * CGFloat(i) / 5
                    var t = Path(); t.move(to: CGPoint(x: r.minX, y: y)); t.addLine(to: CGPoint(x: r.minX + 10, y: y))
                    ctx.stroke(t, with: .color(Theme.inkSoft.opacity(0.6)), lineWidth: 1)
                }
                ctx.stroke(body, with: .color(Theme.isNoir ? Theme.amber : Theme.ink), lineWidth: 1.6)
                // Spout.
                var spout = Path()
                spout.move(to: CGPoint(x: r.minX, y: r.minY + lip))
                spout.addLine(to: CGPoint(x: r.minX - 6, y: r.minY))
                ctx.stroke(spout, with: .color(Theme.isNoir ? Theme.amber : Theme.ink), lineWidth: 1.6)
            }
        }
        .onAppear { tilt.start(); from = target; to = target }
        .onDisappear { tilt.stop() }
        .onChange(of: target) { old, new in
            from = old
            to = new
            changed = Date()
        }
        .accessibilityHidden(true)
    }
}
