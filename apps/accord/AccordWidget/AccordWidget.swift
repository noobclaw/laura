import WidgetKit
import SwiftUI

/// Snapshot the app writes to the shared App Group (see WidgetBridge in the app).
struct WidgetSnapshot: Codable {
    struct Item: Codable, Hashable {
        var name: String
        var madeAt: Date
        var rating: Int
        /// top / heart / base shares
        var layers: [Double]
    }
    var items: [Item] = []
    var language: String = "en"
    var noir: Bool = false

    static let group = "group.com.noobclaw.accord"
    static let key = "accord.widget.snapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return s
    }
}

struct MaturationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct MaturationProvider: TimelineProvider {
    func placeholder(in context: Context) -> MaturationEntry {
        MaturationEntry(date: Date(), snapshot: WidgetSnapshot(items: [
            .init(name: "Evening Amber", madeAt: Date().addingTimeInterval(-9 * 86_400), rating: 4, layers: [0.2, 0.3, 0.5]),
            .init(name: "Bergamot Cologne", madeAt: Date().addingTimeInterval(-20 * 86_400), rating: 0, layers: [0.5, 0.3, 0.2]),
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (MaturationEntry) -> Void) {
        let s = WidgetSnapshot.load()
        completion(s.items.isEmpty && context.isPreview ? placeholder(in: context) : MaturationEntry(date: Date(), snapshot: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MaturationEntry>) -> Void) {
        let s = WidgetSnapshot.load()
        // Day counts change at midnight: one entry per day for a week.
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var entries = [MaturationEntry(date: Date(), snapshot: s)]
        for d in 1...7 {
            if let day = cal.date(byAdding: .day, value: d, to: start) { entries.append(MaturationEntry(date: day, snapshot: s)) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Strings come from the app's catalog in the language chosen inside the app.
private struct L {
    let bundle: Bundle
    init(_ code: String) {
        bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
    func callAsFunction(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: "Localizable") }
}

private struct Palette {
    let noir: Bool
    var bg: Color { noir ? Color(red: 0.05, green: 0.045, blue: 0.035) : Color(red: 0.965, green: 0.945, blue: 0.906) }
    var ink: Color { noir ? Color(red: 0.95, green: 0.92, blue: 0.86) : Color(red: 0.165, green: 0.141, blue: 0.125) }
    var soft: Color { noir ? Color(red: 0.66, green: 0.61, blue: 0.52) : Color(red: 0.42, green: 0.38, blue: 0.345) }
    var accent: Color { noir ? Color(red: 0.83, green: 0.69, blue: 0.39) : Color(red: 0.78, green: 0.58, blue: 0.12) }
    var layers: [Color] {
        noir ? [Color(red: 0.55, green: 0.78, blue: 0.68), Color(red: 0.88, green: 0.56, blue: 0.65), Color(red: 0.75, green: 0.54, blue: 0.33)]
             : [Color(red: 0.56, green: 0.68, blue: 0.55), Color(red: 0.77, green: 0.50, blue: 0.56), Color(red: 0.48, green: 0.35, blue: 0.27)]
    }
}

private func days(_ item: WidgetSnapshot.Item, at date: Date) -> Int {
    max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: item.madeAt),
                                           to: Calendar.current.startOfDay(for: date)).day ?? 0)
}

private struct Ring: View {
    let day: Int
    let p: Palette
    var size: CGFloat = 40
    var body: some View {
        let progress = min(Double(day) / 28, 1)
        ZStack {
            Circle().stroke(p.soft.opacity(0.25), lineWidth: 4)
            Circle().trim(from: 0, to: progress).stroke(progress >= 1 ? p.layers[0] : p.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(day)").font(.system(size: size * 0.36, weight: .semibold).monospacedDigit()).foregroundStyle(p.ink)
        }
        .frame(width: size, height: size)
    }
}

private struct MiniBottle: View {
    let layers: [Double]
    let p: Palette
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let total = max(layers.reduce(0, +), 0.0001)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(p.accent).frame(width: w * 0.42, height: h * 0.16)
                Rectangle().fill(p.ink.opacity(0.7)).frame(width: w * 0.2, height: h * 0.06)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: w * 0.22, style: .continuous).fill(p.ink.opacity(0.06))
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { i in
                            Rectangle().fill(p.layers[i]).frame(height: h * 0.78 * 0.8 * layers[safeIndex: i] / total)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.22, style: .continuous))
                    RoundedRectangle(cornerRadius: w * 0.22, style: .continuous).stroke(p.noir ? p.accent : p.ink, lineWidth: 1.2)
                }
            }
        }
    }
}

private extension Array where Element == Double {
    subscript(safeIndex i: Int) -> Double { indices.contains(i) ? self[i] : 0 }
}

struct MaturationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MaturationEntry

    var body: some View {
        let s = entry.snapshot
        let p = Palette(noir: s.noir)
        let t = L(s.language)
        let items = Array(s.items.prefix(family == .systemSmall ? 1 : 3))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("Batches")).font(.custom("BodoniModa-MediumItalic", size: 16)).foregroundStyle(p.ink)
                Spacer()
                Image(systemName: "hourglass.bottomhalf.filled").font(.caption).foregroundStyle(p.accent)
            }
            if items.isEmpty {
                Spacer()
                Text(t("No batches yet")).font(.footnote.weight(.semibold)).foregroundStyle(p.ink)
                Text(t("Save a batch in Accord to watch it mature here.")).font(.caption2).foregroundStyle(p.soft)
                Spacer()
            } else if family == .systemSmall, let item = items.first {
                HStack(alignment: .bottom) {
                    MiniBottle(layers: item.layers, p: p).frame(width: 36, height: 50)
                    Spacer()
                    Ring(day: days(item, at: entry.date), p: p, size: 50)
                }
                Spacer(minLength: 0)
                Text(item.name).font(.footnote.weight(.semibold)).foregroundStyle(p.ink).lineLimit(2)
                Text(String(format: t("Day %lld"), days(item, at: entry.date))).font(.caption2).foregroundStyle(p.soft)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 10) {
                        MiniBottle(layers: item.layers, p: p).frame(width: 18, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.footnote.weight(.semibold)).foregroundStyle(p.ink).lineLimit(1)
                            Text(String(format: t("Day %lld"), days(item, at: entry.date))).font(.caption2).foregroundStyle(p.soft)
                        }
                        Spacer()
                        Ring(day: days(item, at: entry.date), p: p, size: 28)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                p.bg
                if s.noir { RadialGradient(colors: [p.accent.opacity(0.18), .clear], center: .top, startRadius: 4, endRadius: 200) }
            }
        }
        .widgetURL(URL(string: "accord://batches"))
    }
}

@main
struct AccordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AccordMaturation", provider: MaturationProvider()) { entry in
            MaturationWidgetView(entry: entry)
        }
        .configurationDisplayName("Accord")
        .description("Days each batch has been maturing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
