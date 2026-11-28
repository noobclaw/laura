import SwiftUI

/// A record: grooves, a label (artwork or a generated label), optional spin.
struct VinylView: View {
    let albumKey: String
    let title: String
    var artwork: UIImage?
    var size: CGFloat
    var angle: Angle = .zero
    var highlighted = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.vinyl)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = sz.width / 2
                var radius = r * 0.96
                var i = 0
                while radius > r * 0.42 {
                    let ring = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                    ctx.stroke(ring, with: .color(.white.opacity(i % 2 == 0 ? 0.07 : 0.035)), lineWidth: max(0.5, sz.width / 240))
                    radius -= max(1.6, sz.width / 70)
                    i += 1
                }
                // Sheen.
                let sheen = Path { p in
                    p.move(to: c)
                    p.addArc(center: c, radius: r * 0.96, startAngle: .degrees(-130), endAngle: .degrees(-95), clockwise: false)
                    p.closeSubpath()
                }
                ctx.fill(sheen, with: .color(.white.opacity(0.06)))
            }
            label
                .frame(width: size * 0.4, height: size * 0.4)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.vinyl.opacity(0.5), lineWidth: 1))
            Circle().fill(Theme.vinyl).frame(width: max(3, size * 0.03), height: max(3, size * 0.03))
        }
        .frame(width: size, height: size)
        .rotationEffect(angle)
        .overlay(Circle().stroke(Theme.vinylRim, lineWidth: max(1, size / 120)))
        .overlay(Circle().stroke(highlighted ? Theme.signal : .clear, lineWidth: 2))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var label: some View {
        if let artwork {
            Image(uiImage: artwork).resizable().scaledToFill()
        } else {
            GeneratedLabel(seed: albumKey, title: title)
        }
    }
}

/// Deterministic record label for albums without artwork: a colour from the album name and its initial.
struct GeneratedLabel: View {
    let seed: String
    let title: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Rectangle().fill(GeneratedLabel.color(for: seed))
                Circle().stroke(Color.black.opacity(0.18), lineWidth: max(1, w / 40)).padding(w * 0.08)
                Text(initial)
                    .font(.custom("Anton-Regular", size: w * 0.42))
                    .foregroundStyle(Color.black.opacity(0.72))
                    .offset(y: -w * 0.04)
            }
        }
    }

    private var initial: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.first.map { String($0).uppercased() } ?? "♪"
    }

    /// Warm label colours that sit well on black vinyl.
    static let palette: [UInt32] = [0xD9CF4A, 0xE8A04A, 0xE86A4A, 0xC9B79C, 0x9CC2B0, 0xB7A6D9, 0xE3D7B0, 0x8FB3D9]
    static func color(for seed: String) -> Color {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Color(hex: palette[Int(h % UInt64(palette.count))])
    }
}

/// Hero graphic: a brass spindle with one record per source; record thickness follows its song count.
struct SpindleStack: View {
    struct Disc: Identifiable { let id: UUID; let name: String; let count: Int; let active: Bool }
    let discs: [Disc]
    var spin: Double = 0

    static func thicknesses(counts: [Int], total height: CGFloat, minimum: CGFloat = 4) -> [CGFloat] {
        let sum = max(1, counts.reduce(0, +))
        return counts.map { max(minimum, height * CGFloat($0) / CGFloat(sum)) }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let rx = min(size.width * 0.42, size.height * 0.75, 170)
            let ry = rx * 0.32
            let baseY = size.height - ry - 6
            let maxStack = size.height - ry * 2 - 34
            let list = discs.isEmpty ? [Disc(id: UUID(), name: "", count: 1, active: false)] : discs
            let heights = SpindleStack.thicknesses(counts: list.map(\.count), total: min(maxStack, CGFloat(list.count) * 26 + 20),
                                                   minimum: 6)
            // Rod.
            let rodTop: CGFloat = 8
            let rodRect = CGRect(x: cx - 5, y: rodTop, width: 10, height: baseY - rodTop)
            ctx.fill(Path(roundedRect: rodRect, cornerRadius: 5), with: .color(Theme.accent))
            var y = baseY
            for (i, d) in list.enumerated() {
                let h = heights[i]
                // Side band.
                var band = Path()
                band.addRect(CGRect(x: cx - rx, y: y - h, width: rx * 2, height: h))
                band.addEllipse(in: CGRect(x: cx - rx, y: y - ry, width: rx * 2, height: ry * 2))
                ctx.fill(band, with: .color(Color(hex: 0x070708)))
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - rx, y: y - h - ry, width: rx * 2, height: ry * 2)), with: .color(Theme.vinylRim), lineWidth: 1)
                // Top face.
                let top = CGRect(x: cx - rx, y: y - h - ry, width: rx * 2, height: ry * 2)
                ctx.fill(Path(ellipseIn: top), with: .color(Theme.vinyl))
                var g = rx * 0.94
                var k = 0
                while g > rx * 0.42 {
                    let gr = CGRect(x: cx - g, y: y - h - g * 0.32, width: g * 2, height: g * 0.64)
                    ctx.stroke(Path(ellipseIn: gr), with: .color(.white.opacity(k % 2 == 0 ? 0.08 : 0.04)), lineWidth: 0.8)
                    g -= 7; k += 1
                }
                let lr = rx * 0.34
                let labelColor = d.active ? Theme.signal : GeneratedLabel.color(for: d.name)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - lr, y: y - h - lr * 0.32, width: lr * 2, height: lr * 0.64)), with: .color(labelColor))
                // Rotating mark on the label shows the playing record spinning.
                if d.active {
                    let a = spin
                    let mx = cx + CGFloat(cos(a)) * lr * 0.7, my = y - h + CGFloat(sin(a)) * lr * 0.7 * 0.32
                    ctx.fill(Path(ellipseIn: CGRect(x: mx - 3, y: my - 1.5, width: 6, height: 3)), with: .color(.black.opacity(0.5)))
                }
                y -= h + 3
            }
            // Rod in front of the stack's top label.
            ctx.fill(Path(roundedRect: CGRect(x: cx - 5, y: rodTop, width: 10, height: max(0, y + 10 - rodTop)), cornerRadius: 5), with: .color(Theme.accent))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: rodTop - 2.5, width: 10, height: 5)), with: .color(Color(hex: 0xEDE48A)))
        }
        .accessibilityHidden(true)
    }
}

/// Progress ring used around the now-playing record and on the share card.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
