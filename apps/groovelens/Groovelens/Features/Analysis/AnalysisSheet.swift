import SwiftUI

/// The signature "unweave" scene: one mixed waveform pulls apart into six glowing drum strands while the analysis runs.
struct AnalysisSheet: View {
    let song: Song
    /// `true` when the user chose to open the finished chart.
    let onClose: (Bool) -> Void

    @Environment(AnalysisCenter.self) private var analysis
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Environment(PlayerProfile.self) private var profile
    @State private var proReason: ProReason?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var job: AnalysisJob? { analysis.job(for: song.id) }
    private var progress: Double { song.status == .ready ? 1 : (job?.progress ?? song.progress) }
    private var stage: AnalysisStage {
        if song.status == .ready { return .engraving }
        return job?.stage ?? AnalysisStage(rawValue: song.stageRaw) ?? .isolating
    }

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5).padding(.top, 10)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).hudLabel(song.status == .failed ? Palette.danger : Palette.gold)
                        Text(song.title).font(Typo.display(20)).foregroundStyle(Palette.text).lineLimit(2)
                    }
                    Spacer()
                    Button { onClose(false) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.textDim)
                            .frame(width: 36, height: 36).background(Circle().fill(Palette.surface))
                    }
                    .accessibilityLabel(Text("Close"))
                }
                .padding(.horizontal, 20).padding(.top, 14)

                UnweaveView(progress: progress, failed: song.status == .failed, reduceMotion: reduceMotion)
                    .frame(height: 260)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)

                Text("\(Int((progress * 100).rounded()))%")
                    .font(Typo.hud(44, weight: .bold)).foregroundStyle(Palette.text)
                    .contentTransition(.numericText(value: progress))
                    .animation(.easeOut(duration: 0.3), value: Int(progress * 100))
                    .neonGlow(Palette.brand, radius: 14)

                stageList.padding(.horizontal, 20).padding(.top, 16)
                liveTiles.padding(.horizontal, 20).padding(.top, 14)
                Spacer(minLength: 12)
                footer.padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled(false)
        .sheet(item: $proReason) { ProSheet(reason: $0) }
        .onChange(of: song.status) { _, s in if s == .ready { Haptics.success() } else if s == .failed { Haptics.error() } }
    }

    private var headline: String {
        switch song.status {
        case .ready: return String(localized: "CHART READY")
        case .failed: return String(localized: "SOMETHING WENT WRONG")
        case .analyzing: return String(localized: "ANALYZING ON DEVICE")
        }
    }

    private var stageList: some View {
        VStack(spacing: 10) {
            ForEach(AnalysisStage.allCases, id: \.rawValue) { s in
                let done = song.status == .ready || s.rawValue < stage.rawValue
                let active = song.status == .analyzing && s == stage
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(done ? Palette.mint.opacity(0.2) : Palette.surface).frame(width: 26, height: 26)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.mint)
                        } else if active {
                            ProgressView().controlSize(.mini).tint(Palette.gold)
                        } else {
                            Circle().fill(Palette.textFaint).frame(width: 6, height: 6)
                        }
                    }
                    Text(s.title).font(Typo.body(15, weight: active ? .semibold : .regular))
                        .foregroundStyle(done || active ? Palette.text : Palette.textFaint)
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: done)
            }
        }
        .glassCard()
    }

    private var liveTiles: some View {
        HStack(spacing: 10) {
            StatTile(label: String(localized: "TEMPO"), value: job?.tempo.map { "\(Int($0.rounded()))" } ?? (song.status == .ready ? "\(Int(song.tempo.rounded()))" : "—"), unit: "BPM", accent: Palette.cyan)
            StatTile(label: String(localized: "METER"), value: (job?.beatsPerBar ?? (song.status == .ready ? song.beatsPerBar : nil)).map { "\($0)/4" } ?? "—", accent: Palette.violet)
            StatTile(label: String(localized: "HITS"), value: (job?.hitCount ?? 0) > 0 ? "\(job!.hitCount)" : (song.hitCount > 0 ? "\(song.hitCount)" : "—"), accent: Palette.gold)
        }
    }

    @ViewBuilder private var footer: some View {
        switch song.status {
        case .ready:
            NeonButton(title: String(localized: "Open the chart"), symbol: "play.fill") { onClose(true) }
        case .failed:
            VStack(spacing: 12) {
                Text(song.errorMessage ?? String(localized: "Analysis failed")).font(Typo.body(14)).foregroundStyle(Palette.textDim)
                    .multilineTextAlignment(.center)
                NeonButton(title: String(localized: "Try again"), symbol: "arrow.clockwise", fill: [Palette.danger, Palette.brand]) {
                    if store.canAnalyzeAnotherSong(started: profile.analysesStarted) {
                        analysis.retry(song: song, context: context)
                    } else {
                        proReason = .songLimit
                    }
                }
            }
        case .analyzing:
            Text(String(localized: "Nothing leaves your iPhone. You can close this — analysis keeps going."))
                .font(Typo.body(13)).foregroundStyle(Palette.textFaint).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A mixed waveform that separates into six lanes as `progress` rises.
struct UnweaveView: View {
    let progress: Double
    let failed: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let mid = size.height / 2
                let sep = CGFloat(min(1, max(0, (progress - 0.05) / 0.6)))
                let eased = sep * sep * (3 - 2 * sep)
                let spacing = size.height * 0.13
                let steps = 140
                for lane in 0..<6 {
                    let color = failed ? Palette.danger : Palette.lanes[lane]
                    let targetY = mid + (CGFloat(lane) - 2.5) * spacing
                    var path = Path()
                    for i in 0...steps {
                        let x = size.width * CGFloat(i) / CGFloat(steps)
                        let u = Double(i) / Double(steps)
                        // Lane-specific rhythm: different pulse rates so each strand reads as its own instrument.
                        let rate = [2.0, 4.0, 8.0, 3.0, 6.0, 1.0][lane]
                        let phase = u * rate * .pi * 2 - t * (1.2 + Double(lane) * 0.15)
                        let pulse = pow(max(0, sin(phase)), 6)
                        let noise = sin(u * 37 + t * 3 + Double(lane)) * 0.35 + sin(u * 91 - t * 5) * 0.2
                        let mixedAmp = size.height * 0.22 * (0.4 + 0.6 * abs(noise))
                        let laneAmp = size.height * 0.055 * (0.15 + pulse)
                        let amp = CGFloat(mixedAmp) * (1 - eased) + CGFloat(laneAmp) * eased
                        // Separation sweeps left→right so the "unweaving" travels across.
                        let local = min(1, max(0, eased * 1.6 - CGFloat(1 - u) * 0.6))
                        let y0 = mid + CGFloat(noise) * amp * 0.6
                        let y1 = targetY + CGFloat(sin(phase)) * amp
                        let y = y0 + (y1 - y0) * local
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    var glow = g
                    glow.addFilter(.blur(radius: 6))
                    glow.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 4)
                    g.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 1.6)
                }
                // Scanning beam marking how far the analysis has got.
                let bx = size.width * CGFloat(progress)
                let beam = CGRect(x: bx - 30, y: 0, width: 60, height: size.height)
                g.fill(Path(beam), with: .linearGradient(Gradient(colors: [.clear, Palette.brand.opacity(failed ? 0 : 0.28), .clear]),
                                                          startPoint: CGPoint(x: beam.minX, y: 0), endPoint: CGPoint(x: beam.maxX, y: 0)))
            }
        }
    }
}
