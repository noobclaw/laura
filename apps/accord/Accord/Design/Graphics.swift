import SwiftUI
import Charts

// MARK: - Flacon

/// A square perfume bottle: cap, neck, rounded body. Used for the shelf and the lock screen.
struct FlaconShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let capW = w * 0.42, capH = h * 0.18
        let neckW = w * 0.22, neckH = h * 0.08
        p.addRoundedRect(in: CGRect(x: r.midX - capW / 2, y: r.minY, width: capW, height: capH), cornerSize: CGSize(width: w * 0.06, height: w * 0.06))
        p.addRect(CGRect(x: r.midX - neckW / 2, y: r.minY + capH, width: neckW, height: neckH))
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + capH + neckH, width: w, height: h - capH - neckH),
                         cornerSize: CGSize(width: w * 0.22, height: w * 0.22), style: .continuous)
        return p
    }

    /// The body only, for clipping the liquid.
    static func body(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let top = h * 0.26
        return Path(roundedRect: CGRect(x: r.minX, y: r.minY + top, width: w, height: h - top),
                    cornerSize: CGSize(width: w * 0.22, height: w * 0.22), style: .continuous)
    }
}

/// Bottle filled with the formula's three layers, bottom to top: base, heart, top.
/// The liquid stays level as the phone tilts, its surface ripples, and light sweeps across the glass.
struct FlaconView: View {
    /// Shares of top / heart / base (any scale).
    let layers: [Double]
    var fill: Double = 0.78
    /// Off for still renders (share card, tests) and when Reduce Motion is on.
    var live = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = TiltSensor.shared

    var body: some View {
        let animate = live && !reduceMotion
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    canvas(time: tl.date.timeIntervalSinceReferenceDate, angle: tilt.angle, agitation: tilt.agitation, shimmer: true)
                }
                .onAppear { tilt.start() }
                .onDisappear { tilt.stop() }
            } else {
                canvas(time: 0, angle: 0, agitation: 0, shimmer: false)
            }
        }
        .aspectRatio(0.74, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func canvas(time: Double, angle: Double, agitation: Double, shimmer: Bool) -> some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let body = FlaconShape.body(in: r)
            ctx.fill(body, with: .color(Theme.isNoir ? Color.white.opacity(0.06) : Theme.card))
            let stack: [(Color, Double)] = [
                (Theme.color(Tier.Layer.base), layers[safe: 2] ?? 0),
                (Theme.color(Tier.Layer.heart), layers[safe: 1] ?? 0),
                (Theme.color(Tier.Layer.top), layers[safe: 0] ?? 0),
            ]
            var c = ctx
            LiquidRenderer.draw(in: &c, body: body, layers: stack, fill: fill, angle: angle, time: time,
                                agitation: agitation, shimmer: shimmer)
            // Static glass highlight on the left edge.
            let bodyRect = body.boundingRect
            let hl = CGRect(x: bodyRect.minX + bodyRect.width * 0.1, y: bodyRect.minY + bodyRect.height * 0.12,
                            width: bodyRect.width * 0.07, height: bodyRect.height * 0.62)
            ctx.fill(Path(roundedRect: hl, cornerRadius: hl.width / 2), with: .color(.white.opacity(0.32)))
            let outline = Theme.isNoir ? Theme.amber : Theme.ink
            ctx.stroke(FlaconShape().path(in: r), with: .color(outline), lineWidth: Theme.isNoir ? 1.2 : 1.6)
            let capRect = CGRect(x: r.midX - r.width * 0.21, y: r.minY, width: r.width * 0.42, height: r.height * 0.18)
            if Theme.isNoir {
                ctx.fill(Path(roundedRect: capRect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: r.width * 0.05),
                         with: .linearGradient(Gradient(colors: [Color(UIColor(hex: 0xF1D79A)), Color(UIColor(hex: 0x9C7A35))]),
                                               startPoint: CGPoint(x: capRect.minX, y: capRect.minY), endPoint: CGPoint(x: capRect.maxX, y: capRect.maxY)))
            } else {
                ctx.fill(Path(roundedRect: capRect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: r.width * 0.05), with: .color(Theme.amber))
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Evaporation timeline (signature graphic)

/// Stacked stream of what is left on skin over 24 hours, by layer. Drag to scrub through time.
/// Scent mist rises off the curve, densest at the hour you are looking at, tinted by what is still there.
struct EvaporationChart: View {
    let mix: MixResult
    @Binding var hour: Double
    var live = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let curve = EvaporationCurve(mix)
        GeometryReader { geo in
            let width = geo.size.width
            Group {
                if live && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        chart(curve, time: tl.date.timeIntervalSinceReferenceDate, mist: true)
                    }
                } else {
                    chart(curve, time: 0, mist: false)
                }
            }
            .contentShape(Rectangle())
            // Simultaneous, so a vertical swipe over the chart still scrolls the bench.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { g in
                let t = min(max(g.location.x / max(width, 1), 0), 1)
                let newHour = (Double(t) * Double(t)) * 24
                if Int(newHour) != Int(hour) { Haptics.select() }
                hour = newHour
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Evaporation timeline"))
        .accessibilityValue(Text(verbatim: Fmt.hours(hour)))
        .accessibilityAdjustableAction { dir in
            hour = dir == .increment ? min(24, hour + 1) : max(0, hour - 1)
        }
    }

    private static func noise(_ k: Double) -> Double {
        let v = sin(k * 12.9898) * 43758.5453
        return v - floor(v)
    }

    private func chart(_ curve: EvaporationCurve, time: Double, mist: Bool) -> some View {
        Canvas { ctx, size in
            let peak = max(curve.initial, 0.0001)
            let n = EvaporationCurve.hours.count
            // Square-root time axis: early hours get more room because that's where the top notes live.
            func xt(_ h: Double) -> CGFloat { CGFloat(sqrt(h / 24)) * size.width }
            let plotH = size.height - 18
            for h in [0.0, 1, 4, 8, 24] {
                let gx = xt(h)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: gx, y: 0)); p.addLine(to: CGPoint(x: gx, y: plotH)) },
                           with: .color(Theme.hair), lineWidth: 0.5)
            }
            var lower = Array(repeating: CGFloat(0), count: n)
            for layer in [Tier.Layer.base, .heart, .top] {
                var upper = lower
                for i in 0..<n {
                    upper[i] = lower[i] + CGFloat(curve.samples[i][layer.rawValue] / peak) * plotH
                }
                var p = Path()
                p.move(to: CGPoint(x: xt(EvaporationCurve.hours[0]), y: plotH - upper[0]))
                for i in 1..<n { p.addLine(to: CGPoint(x: xt(EvaporationCurve.hours[i]), y: plotH - upper[i])) }
                for i in stride(from: n - 1, through: 0, by: -1) { p.addLine(to: CGPoint(x: xt(EvaporationCurve.hours[i]), y: plotH - lower[i])) }
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(Gradient(colors: [Theme.color(layer), Theme.color(layer).opacity(0.78)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: plotH)))
                lower = upper
            }

            if mist {
                let scrubX = xt(hour)
                for k in 0..<56 {
                    let kk = Double(k)
                    let f = EvaporationChart.noise(kk + 1)
                    let x = CGFloat(f) * size.width
                    let h = Double(x / max(size.width, 1)); let hr = h * h * 24
                    let i = min(n - 1, max(0, Int(hr / 0.25)))
                    let sample = curve.samples[i]
                    let sum = sample.reduce(0, +)
                    guard sum > 0 else { continue }
                    let top = plotH - CGFloat(sum / peak) * plotH
                    let period = 2.6 + EvaporationChart.noise(kk + 7) * 2.4
                    let phase = (time / period + EvaporationChart.noise(kk + 3)).truncatingRemainder(dividingBy: 1)
                    let near = max(0, 1 - abs(x - scrubX) / (size.width * 0.14))
                    let intensity = sum / peak
                    let alpha = (1 - phase) * (0.18 + 0.7 * near) * min(1, intensity * 1.4)
                    guard alpha > 0.02 else { continue }
                    let drift = CGFloat(sin(time * 1.3 + kk) * 5 * phase)
                    let y = top - CGFloat(phase) * (26 + 16 * CGFloat(near))
                    let r = CGFloat(1.1 + EvaporationChart.noise(kk + 11) * 2.2) * CGFloat(1 + phase)
                    // Colour by what is left at that hour.
                    let pick = EvaporationChart.noise(kk + 5) * sum
                    let layer: Tier.Layer = pick < sample[2] ? .base : (pick < sample[2] + sample[1] ? .heart : .top)
                    ctx.fill(Path(ellipseIn: CGRect(x: x + drift - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.color(layer).opacity(alpha)))
                }
            }

            let sx = xt(hour)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: sx, y: 0)); p.addLine(to: CGPoint(x: sx, y: plotH)) },
                       with: .color(Theme.ink), lineWidth: 1.2)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - 5, y: plotH - 5, width: 10, height: 10)), with: .color(Theme.amber))
            for h in [0.0, 1, 4, 8, 24] {
                let label = h == 0 ? "0" : Fmt.number(h, maxDecimals: 0) + "h"
                ctx.draw(Text(verbatim: label).font(.caption2).foregroundStyle(Theme.inkSoft),
                         at: CGPoint(x: min(max(xt(h), 8), size.width - 10), y: size.height - 6))
            }
        }
    }
}

// MARK: - Pyramid

/// Five horizontal bars, top tier first, centred like a pyramid.
struct PyramidView: View {
    let mix: MixResult

    var body: some View {
        let total = max(mix.activeGrams, 0.0001)
        VStack(spacing: 6) {
            ForEach(Tier.allCases) { tier in
                let share = mix.grams(in: tier) / total
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: tier.name).font(.footnote).foregroundStyle(Theme.inkSoft)
                        .frame(width: 92, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        let w = max(CGFloat(share) * g.size.width, share > 0 ? 3 : 0)
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.sunken)
                            RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.color(tier)).frame(width: w)
                        }
                    }
                    .frame(height: 16)
                    Text(verbatim: Fmt.percent(share * 100, decimals: 0)).font(Theme.figure(.footnote))
                        .foregroundStyle(Theme.ink).frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Family ring

struct FamilyRing: View {
    let mix: MixResult

    private var rows: [(Family, Double)] {
        Family.allCases.map { ($0, mix.grams(in: $0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        let rows = rows
        let total = max(rows.reduce(0) { $0 + $1.1 }, 0.0001)
        HStack(alignment: .center, spacing: Theme.Space.l) {
            Chart(rows, id: \.0) { row in
                SectorMark(angle: .value("share", row.1), innerRadius: .ratio(0.62), angularInset: 1.2)
                    .foregroundStyle(Theme.color(row.0))
            }
            .chartLegend(.hidden)
            .frame(width: 120, height: 120)
            .overlay {
                if let first = rows.first {
                    VStack(spacing: 0) {
                        Text(verbatim: Fmt.percent(first.1 / total * 100, decimals: 0)).font(Theme.displayBold(20))
                        Text(verbatim: first.0.name).font(.caption2).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: 70)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows.prefix(6), id: \.0) { row in
                    HStack(spacing: 6) {
                        Dot(color: Theme.color(row.0))
                        Text(verbatim: row.0.name).font(.footnote).foregroundStyle(Theme.ink)
                        Spacer(minLength: 4)
                        Text(verbatim: Fmt.percent(row.1 / total * 100, decimals: 0)).font(Theme.figure(.footnote, weight: .regular)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
