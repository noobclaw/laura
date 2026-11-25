import SwiftUI

/// Readable drum notation, one bar per row, with a live playhead and tap-to-fix editing.
struct ChartView: View {
    let song: Song
    @State var chart: DrumChart
    let onChange: (DrumChart) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var engine = PlaybackEngine()
    @State private var loaded = false
    @State private var playing = false
    @State private var now: Double = 0
    @State private var editing = false
    @State private var editPiece: DrumPiece = .snare
    @State private var dirty = false
    @State private var ticker: Timer?

    init(song: Song, chart: DrumChart, onChange: @escaping (DrumChart) -> Void) {
        self.song = song
        self._chart = State(initialValue: chart)
        self.onChange = onChange
    }

    private var hitsByBar: [Int: [DrumHit]] { Dictionary(grouping: chart.hits, by: \.bar) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if editing { editBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        let grouped = hitsByBar
                        ForEach(0..<chart.barCount, id: \.self) { bar in
                            BarRow(chart: chart, bar: bar, hits: grouped[bar] ?? [],
                                   section: chart.sections.first { $0.startBar == bar },
                                   isFill: chart.fillBars.contains(bar),
                                   playhead: playheadFraction(bar),
                                   editing: editing) { tick, row in
                                edit(bar: bar, tick: tick, row: row)
                            }
                            .id(bar)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: chart.bar(at: now)) { _, bar in
                    guard playing else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(bar, anchor: .center) }
                }
            }
        }
        .background(NeonBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            ticker?.invalidate()
            engine.stop()
            if dirty { persist() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                    .frame(width: 40, height: 40).background(Circle().fill(Palette.surface))
            }
            .accessibilityLabel(Text("Back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(Typo.display(16)).foregroundStyle(Palette.text).lineLimit(1)
                Text("\(Int(chart.tempo.rounded())) BPM · \(chart.meterLabel) · \(chart.hits.count) hits")
                    .font(Typo.hud(11)).foregroundStyle(Palette.textDim)
            }
            Spacer()
            Button {
                Haptics.select()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editing.toggle() }
            } label: {
                Image(systemName: editing ? "checkmark" : "pencil").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(editing ? .black : Palette.text)
                    .frame(width: 40, height: 40).background(Circle().fill(editing ? Palette.mint : Palette.surface))
            }
            .accessibilityLabel(Text(editing ? "Done editing" : "Edit chart"))
            Button { togglePlay() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .shadow(color: Palette.brand.opacity(0.6), radius: 10)
            }
            .accessibilityLabel(Text(playing ? "Pause" : "Play"))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var editBar: some View {
        VStack(spacing: 6) {
            Text(String(localized: "Pick a drum, then tap the staff to add or remove a hit."))
                .font(Typo.body(12)).foregroundStyle(Palette.textDim)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(DrumPiece.allCases) { p in
                        Button {
                            Haptics.select()
                            editPiece = p
                        } label: {
                            Text(p.displayName).font(Typo.body(13, weight: .semibold))
                                .foregroundStyle(editPiece == p ? .black : Palette.text)
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(Capsule().fill(editPiece == p ? Palette.color(p) : Palette.surface))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func playheadFraction(_ bar: Int) -> Double? {
        guard playing || now > 0 else { return nil }
        let a = chart.barStart(bar), b = chart.barStart(bar + 1)
        guard now >= a && now < b else { return nil }
        return (now - a) / max(b - a, 0.001)
    }

    private func togglePlay() {
        if !loaded {
            do {
                try engine.load(files: song.files, chart: chart)
                engine.track = .full
                loaded = true
            } catch { return }
        }
        if playing {
            engine.pause()
            ticker?.invalidate()
            playing = false
        } else {
            engine.play(from: now >= chart.duration - 0.5 ? 0 : now)
            playing = true
            let t = Timer(timeInterval: 1 / 30, repeats: true) { _ in
                Task { @MainActor in
                    now = engine.audibleTime
                    if now >= chart.duration { playing = false; ticker?.invalidate(); now = 0 }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        }
    }

    /// Toggle `editPiece` at the nearest 16th (or triplet 8th when the beat is triplet-based).
    private func edit(bar: Int, tick: Int, row: Int) {
        guard editing else { return }
        if let i = chart.hits.firstIndex(where: { $0.bar == bar && abs($0.tick - tick) <= 1 && $0.piece == editPiece }) {
            chart.hits.remove(at: i)
        } else {
            let t = chart.time(bar: bar, tick: tick)
            chart.hits.append(DrumHit(time: t, piece: editPiece, velocity: 0.8, bar: bar, tick: tick))
            chart.hits.sort { $0.time < $1.time }
        }
        Haptics.tap()
        dirty = true
    }

    private func persist() {
        do {
            try song.files.save(chart)
            song.hitCount = chart.hits.count
            song.fingerprint = chart.fingerprint()
            onChange(chart)
        } catch {}
    }
}

/// One bar of notation.
struct BarRow: View {
    let chart: DrumChart
    let bar: Int
    let hits: [DrumHit]
    let section: ChartSection?
    let isFill: Bool
    let playhead: Double?
    let editing: Bool
    var printMode = false
    let onTap: (_ tick: Int, _ row: Int) -> Void

    private var inkBase: Color { printMode ? .black : Palette.text }

    private let staffTop: CGFloat = 30
    private let gap: CGFloat = 8          // distance between staff lines
    private let leftPad: CGFloat = 30
    private let rightPad: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let section {
                Text(section.label.uppercased()).hudLabel(Palette.gold, size: 10).padding(.leading, 4)
            }
            GeometryReader { geo in
                Canvas { g, size in draw(&g, size) }
                    .contentShape(Rectangle())
                    .onTapGesture { p in
                        guard editing else { return }
                        let w = size(geo.size).width
                        let frac = max(0, min(0.999, (p.x - leftPad) / w))
                        let step = DrumChart.ticksPerBeat / 4
                        let tick = Int((frac * Double(chart.ticksPerBar) / Double(step)).rounded()) * step
                        onTap(min(tick, chart.ticksPerBar - step), 0)
                    }
            }
            .frame(height: 104)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(printMode ? Color.clear : (playhead != nil ? Palette.brand.opacity(0.10) : (isFill ? Palette.ember.opacity(0.07) : Palette.surface))))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(printMode ? Color.clear : (playhead != nil ? Palette.brand.opacity(0.6) : Palette.stroke)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private func size(_ s: CGSize) -> CGSize { CGSize(width: s.width - leftPad - rightPad, height: s.height) }

    private var accessibilitySummary: String {
        let counts = Dictionary(grouping: hits, by: \.piece).map { "\($0.value.count) \($0.key.displayName)" }.sorted().joined(separator: ", ")
        return String(localized: "Bar \(bar + 1)\(isFill ? ", fill" : ""): \(counts)")
    }

    private func yFor(_ staffPos: Int) -> CGFloat {
        // staffPos 0 = bottom line (E4); each step is half a line gap.
        staffTop + 4 * gap - CGFloat(staffPos) * gap / 2
    }

    private func draw(_ g: inout GraphicsContext, _ full: CGSize) {
        let w = full.width - leftPad - rightPad
        let ink = inkBase.opacity(0.9)
        let faint = inkBase.opacity(printMode ? 0.55 : 0.28)

        // Bar number + fill flag.
        g.draw(Text("\(bar + 1)").font(Typo.hud(10)).foregroundColor(printMode ? .gray : Palette.textFaint), at: CGPoint(x: 14, y: staffTop + 2 * gap))
        if isFill {
            g.draw(Text(Image(systemName: "flame.fill")).font(.system(size: 10)).foregroundColor(Palette.ember), at: CGPoint(x: 14, y: staffTop + 4 * gap + 12))
        }

        // Staff.
        for i in 0..<5 {
            let y = staffTop + CGFloat(i) * gap
            g.stroke(Path { p in p.move(to: CGPoint(x: leftPad, y: y)); p.addLine(to: CGPoint(x: leftPad + w, y: y)) }, with: .color(faint), lineWidth: 0.8)
        }
        g.stroke(Path { p in p.move(to: CGPoint(x: leftPad + w, y: staffTop)); p.addLine(to: CGPoint(x: leftPad + w, y: staffTop + 4 * gap)) },
                 with: .color(faint), lineWidth: 1)

        // Beat guides.
        let tpb = DrumChart.ticksPerBeat
        for beat in 0..<chart.beatsPerBar {
            let x = leftPad + w * CGFloat(beat * tpb) / CGFloat(chart.ticksPerBar)
            g.stroke(Path { p in p.move(to: CGPoint(x: x, y: staffTop - 6)); p.addLine(to: CGPoint(x: x, y: staffTop + 4 * gap + 6)) },
                     with: .color(inkBase.opacity(beat == 0 || printMode ? 0 : 0.06)), lineWidth: 1)
        }
        if editing {
            let step = tpb / 4
            for tick in stride(from: 0, to: chart.ticksPerBar, by: step) {
                let x = leftPad + w * CGFloat(tick) / CGFloat(chart.ticksPerBar) + noteInset(w)
                g.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: staffTop + 4 * gap + 14, width: 3, height: 3)), with: .color(Palette.textFaint))
            }
        }

        // Notes grouped per beat for stems/beams.
        let byBeat = Dictionary(grouping: hits, by: { $0.tick / tpb })
        let stemTop = staffTop - 14
        let stemBottom = staffTop + 4 * gap + 16
        for beatHits in byBeat.values {
            let handHits = beatHits.filter { !$0.piece.isFoot }
            let footHits = beatHits.filter { $0.piece.isFoot }
            let sub = subdivision(of: beatHits.map { $0.tick % tpb })
            for group in [(handHits, true), (footHits, false)] where !group.0.isEmpty {
                let up = group.1
                let ticks = Array(Set(group.0.map(\.tick))).sorted()
                var xs: [CGFloat] = []
                for tick in ticks {
                    let x = leftPad + w * CGFloat(tick) / CGFloat(chart.ticksPerBar) + noteInset(w)
                    xs.append(x)
                    let atTick = group.0.filter { $0.tick == tick }
                    let ys = atTick.map { yFor($0.piece.staffPosition) }
                    // Stem.
                    let stemX = up ? x + 4.5 : x - 4.5
                    let from = up ? (ys.max() ?? 0) : (ys.min() ?? 0)
                    g.stroke(Path { p in p.move(to: CGPoint(x: stemX, y: from)); p.addLine(to: CGPoint(x: stemX, y: up ? stemTop : stemBottom)) },
                             with: .color(ink), lineWidth: 1.1)
                    for h in atTick { drawHead(&g, h, x: x) }
                }
                // Beams.
                if ticks.count > 1, let first = xs.first, let last = xs.last {
                    let y = up ? stemTop : stemBottom
                    let dx: CGFloat = up ? 4.5 : -4.5
                    let beams = sub == 3 ? 1 : (sub >= 4 ? 2 : 1)
                    for b in 0..<beams {
                        let by = up ? y + CGFloat(b) * 4 : y - CGFloat(b) * 4
                        g.fill(Path(CGRect(x: first + dx, y: by - 1.5, width: last - first, height: 3)), with: .color(ink))
                    }
                    if sub == 3 {
                        g.draw(Text("3").font(Typo.hud(9)).foregroundColor(Palette.textDim),
                               at: CGPoint(x: (first + last) / 2 + dx, y: up ? y - 7 : y + 7))
                    }
                } else if ticks.count == 1, let t = ticks.first, t % tpb != 0, let x = xs.first {
                    // Lone off-beat note: flag.
                    let y = up ? stemTop : stemBottom
                    let sx = up ? x + 4.5 : x - 4.5
                    g.stroke(Path { p in p.move(to: CGPoint(x: sx, y: y)); p.addQuadCurve(to: CGPoint(x: sx + 6, y: y + (up ? 10 : -10)), control: CGPoint(x: sx + 7, y: y + (up ? 3 : -3))) },
                             with: .color(ink), lineWidth: 1.4)
                }
            }
        }

        // Playhead.
        if let ph = playhead {
            let x = leftPad + w * CGFloat(ph)
            var glow = g
            glow.addFilter(.blur(radius: 4))
            let line = Path { p in p.move(to: CGPoint(x: x, y: 6)); p.addLine(to: CGPoint(x: x, y: full.height - 6)) }
            glow.stroke(line, with: .color(Palette.brand), lineWidth: 4)
            g.stroke(line, with: .color(Palette.brand), lineWidth: 1.5)
        }
    }

    private func noteInset(_ w: CGFloat) -> CGFloat { min(10, w / CGFloat(chart.ticksPerBar) * 3) }

    /// 2 = eighths, 3 = triplets, 4 = sixteenths, 1 = quarters only.
    private func subdivision(of offsets: [Int]) -> Int {
        let tpb = DrumChart.ticksPerBeat
        if offsets.contains(where: { $0 % (tpb / 3) == 0 && $0 % (tpb / 2) != 0 }) { return 3 }
        if offsets.contains(where: { $0 % (tpb / 2) != 0 }) { return 4 }
        if offsets.contains(where: { $0 != 0 }) { return 2 }
        return 1
    }

    private func drawHead(_ g: inout GraphicsContext, _ h: DrumHit, x: CGFloat) {
        let y = yFor(h.piece.staffPosition)
        let c = printMode ? Color.black : Palette.color(h.piece)
        let alpha = h.isGhost ? 0.55 : 1
        if h.piece.isCymbal {
            let s: CGFloat = 4
            var p = Path()
            p.move(to: CGPoint(x: x - s, y: y - s)); p.addLine(to: CGPoint(x: x + s, y: y + s))
            p.move(to: CGPoint(x: x - s, y: y + s)); p.addLine(to: CGPoint(x: x + s, y: y - s))
            g.stroke(p, with: .color(c.opacity(alpha)), lineWidth: 1.8)
            if h.isOpen { g.stroke(Path(ellipseIn: CGRect(x: x - 3, y: y - 15, width: 6, height: 6)), with: .color(c), lineWidth: 1) }
        } else {
            let rect = CGRect(x: x - 4.8, y: y - 3.6, width: 9.6, height: 7.2)
            var head = g
            head.translateBy(x: rect.midX, y: rect.midY)
            head.rotate(by: .degrees(-20))
            head.fill(Path(ellipseIn: CGRect(x: -4.8, y: -3.6, width: 9.6, height: 7.2)), with: .color(c.opacity(alpha)))
            if h.isGhost {
                g.draw(Text("( )").font(.system(size: 11)).foregroundColor(c.opacity(0.7)), at: CGPoint(x: x, y: y))
            }
        }
        // Ledger line for crash (A5).
        if h.piece.staffPosition >= 10 {
            g.stroke(Path { p in p.move(to: CGPoint(x: x - 7, y: yFor(10))); p.addLine(to: CGPoint(x: x + 7, y: yFor(10))) },
                     with: .color(inkBase.opacity(0.5)), lineWidth: 0.8)
        }
    }
}
