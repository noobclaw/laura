import SwiftUI
import UIKit

/// The full-screen play scene.
struct StageView: View {
    let song: Song
    let chart: DrumChart
    let setup: StageSetup

    @Environment(PlayerProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: StageModel?
    @State private var popup: JudgementEvent?
    @State private var showHeadphoneTip = false

    var body: some View {
        ZStack {
            LinearGradient(colors: profile.selectedSkin.background.reversed(), startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let model {
                if let result = model.result {
                    ResultsView(song: song, result: result,
                                onRetry: { model.restartFromResults() },
                                onClose: { dismiss() })
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                } else {
                    play(model)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model?.result?.id)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let m = StageModel(song: song, chart: chart, setup: setup)
            model = m
            m.start(profile: profile)
            if setup.mode == .kit && !m.engine.headphonesConnected { showHeadphoneTip = true }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model?.teardown()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, let model, case .playing = model.phase { model.togglePause() }
        }
    }

    @ViewBuilder
    private func play(_ model: StageModel) -> some View {
        GeometryReader { geo in
            let padsHeight: CGFloat = setup.mode == .tap ? 132 : 0
            ZStack(alignment: .top) {
                HighwayCanvas(frame: model.frameSnapshot(skin: profile.selectedSkin, mirrored: profile.leftHanded))
                    .frame(height: geo.size.height - padsHeight)
                    .ignoresSafeArea(edges: .top)

                hud(model).padding(.horizontal, 16).padding(.top, 4)

                if let beat = model.countInBeat, case .countIn = model.phase {
                    Text("\(beat)")
                        .font(Typo.hud(120, weight: .bold)).foregroundStyle(.white)
                        .neonGlow(Palette.brand, radius: 30)
                        .id(beat)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                        .frame(maxWidth: .infinity).padding(.top, geo.size.height * 0.26)
                        .accessibilityLabel(Text("Count in \(beat)"))
                }

                if let popup, Date.now.timeIntervalSince(popup.at) < 0.6 {
                    JudgementPopup(event: popup, combo: model.judge.combo)
                        .frame(maxWidth: .infinity)
                        .padding(.top, (geo.size.height - padsHeight) * (setup.mode == .tap ? 0.52 : 0.6))
                        .id(popup.id)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if setup.mode == .tap {
                    VStack {
                        Spacer()
                        TapPads(model: model, colors: profile.selectedSkin.laneColors, mirrored: profile.leftHanded)
                            .frame(height: padsHeight)
                    }
                }

                if setup.mode == .kit {
                    VStack {
                        Spacer()
                        KitListeningBar(showHeadphoneTip: showHeadphoneTip)
                            .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }

                if case .paused = model.phase { PauseOverlay(model: model, onQuit: { dismiss() }) }
                if case .failed(let message) = model.phase {
                    VStack(spacing: 16) {
                        EmptyStateView(symbol: "speaker.slash.fill", title: String(localized: "Playback couldn’t start", bundle: .l10n), message: message)
                        NeonButton(title: String(localized: "Back", bundle: .l10n), symbol: "chevron.left") { dismiss() }.frame(width: 220)
                    }
                    .glassCard().padding(30).frame(maxHeight: .infinity)
                }
            }
        }
        .onChange(of: model.judge.lastEvent?.id) { _, _ in
            guard let e = model.judge.lastEvent else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.6)) { popup = e }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.countInBeat)
    }

    private func hud(_ model: StageModel) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                Button { model.togglePause() } label: {
                    Image(systemName: "pause.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.black.opacity(0.35)))
                        .overlay(Circle().strokeBorder(Palette.stroke))
                }
                .accessibilityLabel(Text("Pause"))
                .accessibilityIdentifier("pause")
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(Typo.body(14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(setup.rangeLabel)
                        if setup.speedTrainer || model.speed < 0.999 { Text("· \(Int((model.speed * 100).rounded()))%").foregroundStyle(Palette.gold) }
                        if setup.loop && model.passes > 0 { Text(String(localized: "· pass \(model.passes + 1)", bundle: .l10n)) }
                    }
                    .font(Typo.hud(11)).foregroundStyle(Palette.textDim)
                }
                Spacer()
                if setup.mode != .watch {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int((model.judge.accuracy * 100).rounded()))%")
                            .font(Typo.hud(26, weight: .bold)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text(String(localized: "ACCURACY", bundle: .l10n)).hudLabel(size: 9)
                    }
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [Palette.brand, Palette.violet], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * model.progress)
                }
            }
            .frame(height: 4)
            if setup.mode != .watch && model.judge.combo >= 5 {
                HStack(spacing: 4) {
                    Text("\(model.judge.combo)").font(Typo.hud(20, weight: .bold)).foregroundStyle(Palette.gold)
                        .contentTransition(.numericText())
                    Text(String(localized: "COMBO", bundle: .l10n)).hudLabel(Palette.gold, size: 10)
                }
                .neonGlow(Palette.gold, radius: 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Pieces

struct JudgementPopup: View {
    let event: JudgementEvent
    let combo: Int

    private var color: Color {
        switch event.judgement {
        case .perfect: return Palette.gold
        case .great: return Palette.cyan
        case .good: return Palette.mint
        case .miss: return Palette.danger
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(event.judgement.title)
                .font(Typo.hud(30, weight: .bold)).italic()
                .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                .neonGlow(color, radius: 14)
            if event.judgement != .miss && abs(event.offset) > Judgement.perfectWindow {
                Text(event.offset < 0 ? String(localized: "EARLY", bundle: .l10n) : String(localized: "LATE", bundle: .l10n))
                    .font(Typo.hud(12, weight: .bold)).foregroundStyle(color.opacity(0.85))
            }
        }
    }
}

/// Six pads under the highway with true multi-touch, so flams and kick+snare land together.
struct TapPads: View {
    let model: StageModel
    let colors: [Color]
    let mirrored: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { slot in
                    let lane = mirrored ? 5 - slot : slot
                    let age = model.now - model.laneFlash[lane]
                    let lit = max(0, 1 - age / 0.18)
                    let c = colors[lane % colors.count]
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [c.opacity(0.22 + 0.5 * lit), c.opacity(0.08 + 0.2 * lit)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.opacity(0.5 + 0.5 * lit), lineWidth: 1.5))
                        .overlay(
                            VStack(spacing: 4) {
                                Text(DrumPiece.allCases[lane].laneLabel).font(Typo.hud(13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                            }
                        )
                        .shadow(color: c.opacity(0.8 * lit), radius: 14)
                        .scaleEffect(1 - 0.04 * lit)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 10).padding(.top, 6)
            MultiTouchSurface(lanes: 6) { slot in
                model.tap(lane: mirrored ? 5 - slot : slot)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Drum pads"))
            .accessibilityHint(Text("Six pads: kick, snare, hi-hat, tom, ride, crash"))
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }
}

/// UIKit view that reports every new touch's column immediately (no gesture recognizer delay).
struct MultiTouchSurface: UIViewRepresentable {
    let lanes: Int
    let onTouch: (Int) -> Void

    final class TouchView: UIView {
        var lanes = 6
        var onTouch: ((Int) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError() }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                let x = t.location(in: self).x
                let lane = min(lanes - 1, max(0, Int(x / max(bounds.width, 1) * CGFloat(lanes))))
                onTouch?(lane)
            }
        }
    }

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.lanes = lanes
        v.onTouch = onTouch
        return v
    }
    func updateUIView(_ v: TouchView, context: Context) {
        v.lanes = lanes
        v.onTouch = onTouch
    }
}

struct KitListeningBar: View {
    let showHeadphoneTip: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            if showHeadphoneTip {
                Label(String(localized: "Use headphones — otherwise the mic hears the backing track too.", bundle: .l10n), systemImage: "headphones")
                    .font(Typo.body(12, weight: .medium)).foregroundStyle(Palette.gold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Palette.gold.opacity(0.14)))
            }
            HStack(spacing: 8) {
                Circle().fill(Palette.danger).frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.3 : 0.8).opacity(pulse ? 1 : 0.6)
                Text(String(localized: "LISTENING TO YOUR KIT", bundle: .l10n)).hudLabel(Palette.text, size: 11)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.4)))
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
    }
}

struct PauseOverlay: View {
    let model: StageModel
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(String(localized: "PAUSED", bundle: .l10n)).font(Typo.display(30, weight: .heavy)).foregroundStyle(.white)
                    .neonGlow(Palette.brand, radius: 18)
                    .padding(.bottom, 12)
                NeonButton(title: String(localized: "Resume", bundle: .l10n), symbol: "play.fill") { model.togglePause() }
                NeonButton(title: String(localized: "Restart", bundle: .l10n), symbol: "arrow.counterclockwise", fill: [Palette.violet, Palette.cyan]) { model.restart() }
                Button(String(localized: "Quit", bundle: .l10n)) { onQuit() }
                    .accessibilityIdentifier("quit")
                    .font(Typo.body(16, weight: .semibold)).foregroundStyle(Palette.textDim).padding(.top, 6)
            }
            .padding(.horizontal, 48)
        }
        .transition(.opacity)
    }
}
