import SwiftUI

struct LevelRing: View {
    let level: Int
    let progress: Double
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(AngularGradient(colors: [Palette.brand, Palette.violet, Palette.brand], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.brand.opacity(0.7), radius: 8)
            Text("\(level)")
                .font(Typo.display(size * 0.32, weight: .heavy))
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level \(level)"))
    }
}

struct GradeBadge: View {
    let grade: Grade?
    var size: CGFloat = 44

    var body: some View {
        let color = grade.map(Palette.grade) ?? Palette.textFaint
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(color, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.1)))
                .shadow(color: color.opacity(grade == nil ? 0 : 0.7), radius: 10)
            Text(grade?.rawValue ?? "–")
                .font(Typo.display(size * 0.42, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(grade.map { "Grade \($0.rawValue)" } ?? "Not played yet"))
    }
}

struct StarsView: View {
    let stars: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? Palette.gold : Palette.textFaint.opacity(0.6))
            }
        }
        .accessibilityLabel(Text("\(stars) of 3 stars"))
    }
}

/// 16-step groove fingerprint, one colored cell per hit.
struct FingerprintView: View {
    let cells: [Int]
    var cell: CGFloat = 7
    var columns = 8

    var body: some View {
        let rows = Int(ceil(Double(cells.count) / Double(columns)))
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { c in
                        let idx = r * columns + c
                        let v = idx < cells.count ? cells[idx] : -1
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(v >= 0 ? Palette.lanes[v] : Color.white.opacity(0.08))
                            .frame(width: cell, height: cell)
                            .shadow(color: v >= 0 ? Palette.lanes[v].opacity(0.6) : .clear, radius: 3)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    var accent: Color = Palette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).hudLabel(size: 10)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Typo.hud(22, weight: .bold)).foregroundStyle(accent).contentTransition(.numericText())
                if let unit { Text(unit).font(Typo.hud(12)).foregroundStyle(Palette.textFaint) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 12)
        .accessibilityElement(children: .combine)
    }
}

struct SectionStrip: View {
    let sections: [ChartSection]
    let totalBars: Int
    var selected: ChartSection.ID?
    var onSelect: ((ChartSection) -> Void)?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(sections) { s in
                    let w = max(28, (geo.size.width - CGFloat(max(0, sections.count - 1)) * 4) * CGFloat(s.barCount) / CGFloat(max(totalBars, 1)))
                    Button {
                        Haptics.select()
                        onSelect?(s)
                    } label: {
                        Text(s.label)
                            .font(Typo.label(10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(selected == s.id ? Color.black : color(for: s.kind))
                            .frame(width: w, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected == s.id ? color(for: s.kind) : color(for: s.kind).opacity(0.14)))
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .disabled(onSelect == nil)
                }
            }
        }
        .frame(height: 30)
    }

    func color(for kind: SectionKind) -> Color {
        switch kind {
        case .intro, .outro: return Palette.textDim
        case .verse: return Palette.cyan
        case .chorus: return Palette.gold
        case .bridge: return Palette.violet
        case .part: return Palette.mint
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.brand.opacity(0.12)).frame(width: 84, height: 84)
                Image(systemName: symbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(Palette.brand)
            }
            .neonGlow(Palette.brand, radius: 18)
            Text(title).font(Typo.display(18)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text(message).font(Typo.body(14)).foregroundStyle(Palette.textDim).multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(Typo.hud(10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .leading, endPoint: .trailing)))
    }
}

func formatDuration(_ s: Double) -> String {
    let total = Int(s.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
