import SwiftData
import SwiftUI

/// Every fill detected across the library, ready to drill on a loop.
struct FillsView: View {
    @Environment(ProStore.self) private var store
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]

    struct FillItem: Identifiable {
        let id: String
        let song: Song
        let chart: DrumChart
        let bar: Int
        let hits: [DrumHit]
        let section: String?
    }

    @State private var items: [FillItem] = []
    @State private var loading = true
    @State private var proReason: ProReason?
    @State private var drill: (song: Song, chart: DrumChart, setup: StageSetup)?
    @State private var drillSetup: StageSetup?

    static let freeFills = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Fills")).font(Typo.display(28)).foregroundStyle(Palette.text)
                    Text(String(localized: "Pulled from your songs. Each drill loops the bar before the fill, then the fill."))
                        .font(Typo.body(14)).foregroundStyle(Palette.textDim)
                }
                .padding(.top, 14)

                if loading {
                    ProgressView().tint(Palette.brand).frame(maxWidth: .infinity, minHeight: 200)
                } else if items.isEmpty {
                    EmptyStateView(symbol: "flame",
                                   title: String(localized: "No fills yet"),
                                   message: String(localized: "Chart a song with some drum fills and they’ll collect here automatically."))
                        .glassCard()
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        let locked = !store.isPro && i >= FillsView.freeFills
                        fillCard(item, locked: locked)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: songs.filter { $0.status == .ready }.count) { await load() }
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .fullScreenCover(item: $drillSetup) { setup in
            if let drill { StageView(song: drill.song, chart: drill.chart, setup: setup) }
        }
    }

    private func fillCard(_ item: FillItem, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.song.title).font(Typo.body(15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text([item.section, String(localized: "bar \(item.bar + 1)"), "\(Int(item.chart.tempo.rounded())) BPM"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Typo.hud(12)).foregroundStyle(Palette.textDim)
                }
                Spacer()
                Text(difficulty(item)).font(Typo.hud(11, weight: .bold)).foregroundStyle(Palette.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.ember.opacity(0.14)))
            }
            BarRow(chart: item.chart, bar: item.bar, hits: item.hits, section: nil, isFill: true, playhead: nil, editing: false) { _, _ in }
                .blur(radius: locked ? 6 : 0)
                .overlay { if locked { Image(systemName: "lock.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.gold) } }
            Button {
                if locked { proReason = .fills; return }
                let setup = StageSetup(mode: .tap, bars: max(0, item.bar - 1)..<(item.bar + 1),
                                       rangeLabel: String(localized: "Fill · bar \(item.bar + 1)"), isFill: true,
                                       speed: 0.8, track: item.song.files.hasStems ? .drumless : .full,
                                       click: true, loop: true, speedTrainer: store.isPro)
                drill = (item.song, item.chart, setup)
                drillSetup = setup
            } label: {
                HStack {
                    Image(systemName: locked ? "lock.fill" : "repeat")
                    Text(locked ? String(localized: "Unlock with Pro") : String(localized: "Drill this fill"))
                    Spacer()
                    if locked { ProBadge() } else { Image(systemName: "chevron.right") }
                }
                .font(Typo.body(14, weight: .semibold)).foregroundStyle(locked ? Palette.gold : Palette.brand)
                .padding(.horizontal, 14).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14).fill((locked ? Palette.gold : Palette.brand).opacity(0.12)))
            }
            .buttonStyle(PressableStyle())
        }
        .glassCard()
    }

    private func difficulty(_ item: FillItem) -> String {
        let density = Double(item.hits.count) / Double(max(item.chart.beatsPerBar, 1))
        let bpmFactor = item.chart.tempo / 120
        let score = density * bpmFactor
        switch score {
        case ..<2.5: return String(localized: "EASY")
        case ..<4.5: return String(localized: "MEDIUM")
        default: return String(localized: "HARD")
        }
    }

    private func load() async {
        let ready = songs.filter { $0.status == .ready }
        var out: [FillItem] = []
        for song in ready {
            guard let chart = try? song.files.loadChart() else { continue }
            let byBar = Dictionary(grouping: chart.hits, by: \.bar)
            for bar in chart.fillBars {
                let section = chart.sections.first { bar >= $0.startBar && bar < $0.endBar }?.label
                out.append(FillItem(id: "\(song.id.uuidString)-\(bar)", song: song, chart: chart, bar: bar,
                                    hits: byBar[bar] ?? [], section: section))
            }
        }
        items = out
        loading = false
    }
}
