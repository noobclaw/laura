import SwiftUI

struct SongDetailView: View {
    let song: Song

    @Environment(ProStore.self) private var store
    @Environment(PlayerProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss

    @State private var chart: DrumChart?
    @State private var loadError: String?
    @State private var selectedSection: ChartSection.ID?
    @State private var mode: PlayMode = .tap
    @State private var track: PlaybackTrack = .drumless
    @State private var speed: Double = 1
    @State private var click = false
    @State private var loop = false
    @State private var trainer = false
    @State private var proReason: ProReason?
    @State private var stageSetup: StageSetup?
    @State private var showChart = false
    @State private var notice: String?
    @State private var micDenied = false
    @State private var shareItem: ShareItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                if let chart {
                    titleBlock(chart)
                    statsRow(chart)
                    sectionPicker(chart)
                    modeCards
                    options
                    NeonButton(title: String(localized: "Start"), symbol: "play.fill") { start(chart) }
                        .accessibilityIdentifier("start")
                        .padding(.top, 4)
                } else if let loadError {
                    EmptyStateView(symbol: "exclamationmark.triangle", title: String(localized: "Chart unavailable"), message: loadError).glassCard()
                } else {
                    ProgressView().tint(Palette.brand).frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .task { load() }
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .fullScreenCover(item: $stageSetup) { setup in
            if let chart { StageView(song: song, chart: chart, setup: setup) }
        }
        .navigationDestination(isPresented: $showChart) {
            if let chart { ChartView(song: song, chart: chart) { updated in self.chart = updated } }
        }
        .alert(String(localized: "Heads up"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            if micDenied {
                Button(String(localized: "Open Settings")) { micDenied = false; MicPermission.openSettings() }
            }
            Button(String(localized: "OK"), role: .cancel) { micDenied = false }
        } message: { Text(notice ?? "") }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                    .frame(width: 40, height: 40).background(Circle().fill(Palette.surface))
            }
            .accessibilityLabel(Text("Back"))
            .accessibilityIdentifier("back")
            Spacer()
            Button { showChart = true } label: {
                Label(String(localized: "Chart"), systemImage: "music.note.list")
                    .font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 14).frame(height: 40).background(Capsule().fill(Palette.surface))
            }
            .disabled(chart == nil)
            .accessibilityIdentifier("chart-button")
            Menu {
                Button { export(.midi) } label: { Label("MIDI", systemImage: "pianokeys") }
                Button { export(.musicXML) } label: { Label("MusicXML", systemImage: "doc.richtext") }
                Button { export(.pdf) } label: { Label("PDF", systemImage: "doc.fill") }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                    .frame(width: 40, height: 40).background(Circle().fill(Palette.surface))
                    .overlay(alignment: .topTrailing) { if !store.isPro { ProBadge().scaleEffect(0.7).offset(x: 8, y: -6) } }
            }
            .disabled(chart == nil)
            .accessibilityLabel(Text("Export"))
        }
        .padding(.top, 8)
    }

    private func titleBlock(_ chart: DrumChart) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).font(Typo.display(24)).foregroundStyle(Palette.text).lineLimit(3)
                HStack(spacing: 8) {
                    GradeBadge(grade: song.bestGrade, size: 28)
                    if song.bestAccuracy > 0 {
                        Text(String(localized: "Best \(Int((song.bestAccuracy * 100).rounded()))%")).font(Typo.hud(13)).foregroundStyle(Palette.textDim)
                    } else {
                        Text(String(localized: "Not played yet")).font(Typo.hud(13)).foregroundStyle(Palette.textDim)
                    }
                    StarsView(stars: song.bestStars, size: 11)
                }
            }
            Spacer()
            FingerprintView(cells: song.fingerprint, cell: 7)
        }
    }

    private func statsRow(_ chart: DrumChart) -> some View {
        HStack(spacing: 10) {
            StatTile(label: String(localized: "TEMPO"), value: "\(Int(chart.tempo.rounded()))", unit: "BPM", accent: Palette.cyan)
            StatTile(label: String(localized: "METER"), value: chart.meterLabel, accent: Palette.violet)
            StatTile(label: String(localized: "FEEL"), value: chart.swing > 0.15 ? String(localized: "Swing") : String(localized: "Straight"), accent: Palette.gold)
            StatTile(label: String(localized: "BARS"), value: "\(chart.barCount)", accent: Palette.mint)
        }
    }

    private func sectionPicker(_ chart: DrumChart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "PRACTICE RANGE")).hudLabel()
                Spacer()
                Button {
                    selectedSection = nil
                    Haptics.select()
                } label: {
                    Text(String(localized: "Whole song")).font(Typo.body(13, weight: .semibold))
                        .foregroundStyle(selectedSection == nil ? Palette.brand : Palette.textDim)
                }
            }
            SectionStrip(sections: chart.sections, totalBars: chart.barCount, selected: selectedSection) { s in
                Haptics.select()
                selectedSection = selectedSection == s.id ? nil : s.id
            }
            .frame(height: 44)
            Text(rangeDescription(chart)).font(Typo.hud(12)).foregroundStyle(Palette.textFaint)
        }
        .glassCard()
    }

    private var modeCards: some View {
        HStack(spacing: 10) {
            ForEach(PlayMode.allCases) { m in
                let locked = m == .kit && !store.isPro
                Button {
                    if locked { proReason = .kitMode; return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = m }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: m.symbol).font(.system(size: 18, weight: .bold))
                                .foregroundStyle(mode == m ? Palette.brand : Palette.textDim)
                            Spacer()
                            if locked { ProBadge() }
                        }
                        Text(m.title).font(Typo.display(15)).foregroundStyle(Palette.text)
                        Text(m.subtitle).font(Typo.body(11)).foregroundStyle(Palette.textDim)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(mode == m ? Palette.brand.opacity(0.14) : Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(mode == m ? Palette.brand : Palette.stroke, lineWidth: mode == m ? 1.5 : 1))
                    .shadow(color: mode == m ? Palette.brand.opacity(0.35) : .clear, radius: 12)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(mode == m ? .isSelected : [])
                .accessibilityIdentifier("mode-\(m.rawValue)")
            }
        }
    }

    private var options: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "BACKING TRACK")).hudLabel()
                Picker("", selection: $track) {
                    ForEach(PlaybackTrack.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(localized: "SPEED")).hudLabel()
                    Spacer()
                    Text("\(Int((speed * 100).rounded()))%").font(Typo.hud(15, weight: .bold)).foregroundStyle(Palette.gold)
                        .contentTransition(.numericText())
                }
                Slider(value: $speed, in: 0.5...1, step: 0.05) { Text("Speed") }
                    .tint(Palette.gold)
                    .onChange(of: speed) { _, _ in Haptics.select() }
            }
            Divider().overlay(Palette.stroke)
            Toggle(isOn: $click) { optionLabel("metronome.fill", String(localized: "Click track"), Palette.cyan) }
            Toggle(isOn: $loop) { optionLabel("repeat", String(localized: "Loop the range"), Palette.mint) }
            Toggle(isOn: Binding(get: { trainer }, set: { on in
                if on && !store.isPro { proReason = .speedTrainer; return }
                trainer = on
                if on { loop = true; speed = min(speed, 0.7) }
            })) {
                HStack {
                    optionLabel("speedometer", String(localized: "Speed trainer"), Palette.ember)
                    if !store.isPro { ProBadge() }
                }
            }
        }
        .tint(Palette.brand)
        .glassCard()
    }

    private func optionLabel(_ symbol: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(color).frame(width: 22)
            Text(title).font(Typo.body(15, weight: .medium)).foregroundStyle(Palette.text)
        }
    }

    // MARK: Logic

    private func load() {
        guard chart == nil else { return }
        do {
            chart = try song.files.loadChart()
            if !song.files.hasStems { track = .full }
        } catch {
            loadError = String(localized: "This chart couldn’t be read. Delete the song and import it again.")
        }
    }

    private func range(_ chart: DrumChart) -> (Range<Int>, String) {
        if let id = selectedSection, let s = chart.sections.first(where: { $0.id == id }) {
            return (s.startBar..<s.endBar, s.label)
        }
        return (0..<chart.barCount, String(localized: "Whole song"))
    }

    private func rangeDescription(_ chart: DrumChart) -> String {
        let (r, label) = range(chart)
        let secs = chart.barStart(r.upperBound) - chart.barStart(r.lowerBound)
        return String(localized: "\(label) · bars \(r.lowerBound + 1)–\(r.upperBound) · \(formatDuration(secs))")
    }

    private func start(_ chart: DrumChart) {
        let (bars, label) = range(chart)
        let setup = StageSetup(mode: mode, bars: bars, rangeLabel: label, isFill: false, speed: speed, track: track,
                               click: click, loop: loop || trainer, speedTrainer: trainer,
                               sectionKey: selectedSection.flatMap { id in chart.sections.first { $0.id == id }?.key })
        if mode == .kit {
            switch MicPermission.current {
            case .granted:
                break
            case .undetermined:
                Task {
                    if await MicPermission.request() { stageSetup = setup }
                    else { micDenied = true; notice = String(localized: "Kit mode needs the microphone to hear your drums. You can turn it on in Settings › Groovelens.") }
                }
                return
            case .denied:
                micDenied = true
                notice = String(localized: "Kit mode needs the microphone to hear your drums. You can turn it on in Settings › Groovelens.")
                return
            }
        }
        stageSetup = setup
    }

    private func export(_ format: ChartExportFormat) {
        guard store.isPro else { proReason = .export; return }
        guard let chart else { return }
        do {
            shareItem = ShareItem(url: try ChartExporter.export(chart, title: song.title, format: format))
        } catch {
            notice = error.localizedDescription
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension StageSetup: Identifiable {
    var id: Int { hashValue }
}
